/// ТЕСТЫ МОК-РЕПОЗИТОРИЯ (Dart).
///
/// Зона: Артём. Защищают поведение, против которого верстаются экраны.
/// Главный тест файла вырос из бага, пойманного ГЛАЗАМИ на первом скрине:
/// заказ со статусом in_progress светился в ленте «Доступные заказы».
library;

import 'package:avatar_app/core/error/app_failure.dart';
import 'package:avatar_app/data/mock_orders_repository.dart';
import 'package:avatar_app/data/orders_repository.dart';
import 'package:avatar_app/features/order_flow/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    MockControls.instant = true;
    MockControls.mode = MockMode.normal;
    MockControls.randomErrorEveryN = 0;
    MockControls.simulateOffline = false;
    MockControls.simulateRaceCondition = false;
  });

  group('Лента «Доступные заказы»', () {
    test('🔴 НЕ показывает заказы, которые уже идут (in_progress)', () async {
      final repo = MockOrdersRepository();
      final feed = await repo.watchFeed().first;

      // ord-2001 — активный заказ из сида (пр-т Карла Маркса, 30).
      expect(feed.any((o) => o.id == 'ord-2001'), isFalse,
          reason: 'идущий заказ не может предлагаться для отклика');
      expect(feed.every((o) => o.status == OrderStatus.new_), isTrue);
    });

    test('показывает все открытые: срочный, замену, текущие, утренний, предварительный', () async {
      final repo = MockOrdersRepository();
      final feed = await repo.watchFeed().first;
      final ids = feed.map((o) => o.id).toSet();
      expect(ids, containsAll(['ord-1001', 'ord-1002', 'ord-1003', 'ord-1004', 'ord-1005']));
      // срочные сверху
      expect(feed.first.urgency, OrderUrgency.urgent);
    });

    test('onlyMine: мои живые заказы, включая активный', () async {
      final repo = MockOrdersRepository();
      final mine = await repo.watchFeed(filter: const FeedFilter(onlyMine: true)).first;
      expect(mine.any((o) => o.id == 'ord-2001'), isTrue);
    });

    test('empty-режим: лента пустая для EmptyState', () async {
      MockControls.mode = MockMode.empty;
      final repo = MockOrdersRepository();
      final feed = await repo.watchFeed().first;
      expect(feed, isEmpty);
    });
  });

  group('Диспетчерские действия доходят до бригады', () {
    test('forceCloseOrder: стрим статуса приносит completed + forceClosed', () async {
      final repo = MockOrdersRepository();
      final statuses = <OrderStatus>[];
      final sub = repo.watchOrderStatus(orderId: 'ord-2001').listen(statuses.add);
      await Future<void>.delayed(Duration.zero);

      await repo.forceCloseOrder(orderId: 'ord-2001', comment: 'Клиент отменил');
      await Future<void>.delayed(Duration.zero);

      expect(statuses.last, OrderStatus.completed);
      final order = await repo.getOrder(orderId: 'ord-2001');
      expect(order.forceClosed, isTrue);
      await sub.cancel();
    });

    test('approveResponse: заказ → approved, я в бригаде, отклик → approved', () async {
      final repo = MockOrdersRepository();
      final resp = await repo.respondToOrder(orderId: 'ord-1002', etaMinutes: 10);
      await repo.approveResponse(responseId: resp.id);

      final order = await repo.getOrder(orderId: 'ord-1002');
      expect(order.status, OrderStatus.approved);

      final takers = await repo.watchOrderTakers(orderId: 'ord-1002').first;
      expect(takers.any((t) => t.porter.id == 'porter-artem-374545233'), isTrue);
    });
  });

  group('Этапы и отклики: ошибки прилетают AppFailure', () {
    test('не-старший не может «Начали»', () async {
      final repo = MockOrdersRepository();
      expect(
        () => repo.setStage(orderId: 'ord-2001', stage: OrderStageType.started),
        throwsA(isA<AppFailure>().having((f) => f.code, 'code', FailureCode.leadOnly)),
      );
    });

    test('второй отклик на тот же заказ блокируется', () async {
      final repo = MockOrdersRepository();
      await repo.respondToOrder(orderId: 'ord-1001', etaMinutes: 15);
      expect(
        () => repo.respondToOrder(orderId: 'ord-1001', etaMinutes: 20),
        throwsA(isA<AppFailure>()
            .having((f) => f.code, 'code', FailureCode.responseAlreadyExists)),
      );
    });

    test('гонка: simulateRaceCondition → «заказ занят»', () async {
      MockControls.simulateRaceCondition = true;
      final repo = MockOrdersRepository();
      expect(
        () => repo.respondToOrder(orderId: 'ord-1001', etaMinutes: 15),
        throwsA(isA<AppFailure>()
            .having((f) => f.code, 'code', FailureCode.orderAlreadyTaken)),
      );
    });
  });
}
