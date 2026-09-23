/// АУДИТ-ПРОБЫ МОКА (регессии, пойманные на живом прогоне 20.09):
///  1. случайные mock-ошибки не должны стрелять в демо (default = 0);
///  2. до одобрения диспетчером этапы заблокированы С ПРИЧИНОЙ на экране;
///  3. одобрение отклика обновляет список пульта (статус approved).
library;


import 'package:avatar_app/data/mock_orders_repository.dart';
import 'package:avatar_app/features/order_active/presentation/order_active_screen.dart';
import 'package:avatar_app/features/order_flow/domain/enums.dart';
import 'package:avatar_app/features/order_flow/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    MockControls.instant = true;
    MockControls.mode = MockMode.normal;
    MockControls.simulateOffline = false;
    MockControls.simulateDispatcher = false;
    // randomErrorEveryN НЕ трогаем: проверяем именно дефолт.
  });

  tearDown(() {
    MockControls.instant = false;
    MockControls.mode = MockMode.normal;
    MockControls.simulateOffline = false;
    MockControls.simulateDispatcher = true;
  });

  test('демо-режим: 40 вызовов подряд без случайных сбоев', () async {
    final repo = MockOrdersRepository();
    for (var i = 0; i < 40; i++) {
      await repo.getOrder(orderId: 'ord-1002');
    }
    await repo.submitClientReview(orderId: 'ord-3001', rating: 5, text: 'ок');
  });

  test('этапы до одобрения: заблокированы с человекочитаемой причиной', () async {
    final repo = MockOrdersRepository();
    final a = await repo.getStageAvailability(orderId: 'ord-1002'); // created
    expect(a.available, isEmpty);
    expect(a.blockedReason, 'Заказ ещё не одобрен диспетчером');
  });

  testWidgets('активный заказ created: причина блока видна на экране',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: OrderActiveScreen(
        repository: MockOrdersRepository(),
        orderId: 'ord-1002',
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Заказ ещё не одобрен диспетчером'), findsOneWidget);
  });

  test('одобрение отклика: пульт видит approved без переподписки', () async {
    final repo = MockOrdersRepository();
    List<Order>? last;
    final sub = repo.watchDispatcherOrders().listen((l) => last = l);
    addTearDown(sub.cancel);
    await Future<void>.delayed(Duration.zero);

    final resp = await repo.respondToOrder(orderId: 'ord-1001', etaMinutes: 15);
    expect(resp.status, ResponseStatus.pending);
    await repo.approveResponse(responseId: resp.id);

    await Future<void>.delayed(Duration.zero);
    expect(last, isNotNull);
    final order = last!.firstWhere((o) => o.id == 'ord-1001');
    expect(order.status, OrderStatus.approved);
  });
}
