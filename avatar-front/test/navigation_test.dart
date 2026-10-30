/// ТЕСТЫ ВРЕМЕННОЙ НАВИГАЦИИ (до роутинга Коли):
/// лента → активный заказ → чат; «Мои заказы» → отзыв.
///
/// ⚠️ Активный экран держит Timer.periodic(15 c) — pumpAndSettle с ним
/// не успокаивается никогда, поэтому только ограниченные pump (как в
/// order_active_screen_test Артёма).
library;

import 'package:avatar_app/data/mock_orders_repository.dart';
import 'package:avatar_app/features/client_orders/presentation/client_cabinet_screen.dart';
import 'package:avatar_app/features/order_active/presentation/order_active_screen.dart';
import 'package:avatar_app/features/order_feed/presentation/order_feed_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    MockControls.instant = true;
    MockControls.mode = MockMode.normal;
    MockControls.randomErrorEveryN = 1000000;
    MockControls.simulateOffline = false;
  });

  tearDown(() {
    MockControls.instant = false;
    MockControls.mode = MockMode.normal;
    MockControls.randomErrorEveryN = 9;
    MockControls.simulateOffline = false;
  });

  /// Несколько кадров вместо pumpAndSettle: стримы мока мгновенные
  /// (MockControls.instant), а периодические таймеры не даём бесконечить.
  Future<void> settle(WidgetTester tester, [int frames = 4]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('лента → тап по карточке открывает активный заказ с чатом',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: OrderFeedScreen(
        repository: MockOrdersRepository(),
        onOpenOrder: (id) => Navigator.of(
                tester.element(find.byType(OrderFeedScreen)))
            .push(MaterialPageRoute(
          builder: (_) => OrderActiveScreen(
            repository: MockOrdersRepository(),
            orderId: id,
          ),
        )),
      ),
    ));
    await settle(tester);
    await tester.tap(find.byType(TmpOrderCard).first);
    await settle(tester);
    expect(find.byKey(const Key('active_chat_btn')), findsOneWidget);
  });

  testWidgets('активный заказ: кнопка чата открывает экран чата', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: OrderActiveScreen(
        repository: MockOrdersRepository(),
        orderId: 'ord-2001',
      ),
    ));
    await settle(tester);
    await tester.tap(find.byKey(const Key('active_chat_btn')));
    await settle(tester);
    expect(find.text('Чат по заказу'), findsOneWidget);
    expect(find.byKey(const Key('chat_input')), findsOneWidget);
  });

  testWidgets('грузчик не видит кнопку отзыва на чужом завершённом заказе',
      (tester) async {
    // mock-текущий пользователь — грузчик, а заказ принадлежит client-demo-1
    await tester.pumpWidget(MaterialApp(
      home: OrderActiveScreen(
        repository: MockOrdersRepository(),
        orderId: 'ord-3001',
      ),
    ));
    await settle(tester);
    expect(find.byKey(const Key('active_review_btn')), findsNothing);
  });

  testWidgets('«Мои заказы»: список, отзыв на завершённом, вход в отзыв',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ClientCabinetScreen(repository: MockOrdersRepository()),
    ));
    await settle(tester);
    expect(find.byKey(const Key('client_orders_list')), findsOneWidget);

    // завершённый заказ может быть ниже сгиба — доскроллим
    await tester.scrollUntilVisible(
      find.byKey(const Key('client_order_review_btn')),
      200,
      scrollable: find.descendant(
        of: find.byKey(const Key('client_orders_list')),
        matching: find.byType(Scrollable),
      ),
    );
    await settle(tester, 2);
    await tester.tap(find.byKey(const Key('client_order_review_btn')).first);
    await settle(tester);
    expect(find.byKey(const Key('review_stars')), findsOneWidget);
  });

  testWidgets('лента: кнопка «Мои заказы» видна только если колбэк передан',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: OrderFeedScreen(repository: MockOrdersRepository()),
    ));
    await settle(tester);
    expect(find.byKey(const Key('feed_my_client_orders')), findsNothing);
  });
}
