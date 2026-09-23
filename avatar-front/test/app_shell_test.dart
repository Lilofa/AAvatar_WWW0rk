/// ТЕСТЫ APP-SHELL: вход по SMS, табы по ролям, пульт диспетчера.
library;

import 'package:avatar_app/data/mock_orders_repository.dart';
import 'package:avatar_app/features/order_flow/domain/enums.dart';
import 'package:avatar_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    MockControls.instant = true;
    MockControls.mode = MockMode.normal;
    MockControls.randomErrorEveryN = 1000000;
    MockControls.simulateOffline = false;
    MockControls.simulateDispatcher = false;
  });

  tearDown(() {
    MockControls.instant = false;
    MockControls.mode = MockMode.normal;
    MockControls.randomErrorEveryN = 9;
    MockControls.simulateOffline = false;
    MockControls.simulateDispatcher = true;
  });

  Future<void> settle(WidgetTester tester, [int frames = 4]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> login(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('login_phone')), '+79991234567');
    await tester.tap(find.byKey(const Key('login_send_code')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('login_code')), '1234');
    await tester.tap(find.byKey(const Key('login_submit')));
    await settle(tester);
  }

  testWidgets('вход по SMS: код принят, shell с табами по ролям', (tester) async {
    await tester.pumpWidget(AvatarApp(repository: MockOrdersRepository()));
    await settle(tester, 2);
    expect(find.byKey(const Key('login_phone')), findsOneWidget);
    expect(find.text('Используем силу с умом'), findsOneWidget);

    await login(tester);
    expect(find.byKey(const Key('shell_nav')), findsOneWidget);
    // mock-профиль: грузчик + диспетчер → две вкладки, клиентской нет
    expect(find.text('Лента'), findsOneWidget);
    expect(find.text('Диспетчер'), findsOneWidget);
    expect(find.text('Мои заказы'), findsNothing);
  });

  testWidgets('вход: код 0000 → ошибка, остаёмся на логине', (tester) async {
    await tester.pumpWidget(AvatarApp(repository: MockOrdersRepository()));
    await settle(tester, 2);
    await tester.enterText(find.byKey(const Key('login_phone')), '+79991234567');
    await tester.tap(find.byKey(const Key('login_send_code')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('login_code')), '0000');
    await tester.tap(find.byKey(const Key('login_submit')));
    await settle(tester);
    expect(find.byKey(const Key('login_error')), findsOneWidget);
    expect(find.byKey(const Key('shell_nav')), findsNothing);
  });

  testWidgets('диспетчер: одобрение отклика с ETA', (tester) async {
    final repo = MockOrdersRepository();
    await repo.respondToOrder(orderId: 'ord-1001', etaMinutes: 20);
    await tester.pumpWidget(AvatarApp(repository: repo));
    await settle(tester, 2);
    await login(tester);

    await tester.tap(find.text('Диспетчер'));
    await settle(tester);
    expect(find.byKey(const Key('disp_list')), findsOneWidget);

    await tester.tap(find.ancestor(
      of: find.textContaining('ул. Ленина, 12'),
      matching: find.byKey(const Key('disp_order_card')),
    ));
    await settle(tester);
    expect(find.byKey(const Key('disp_response_card')), findsOneWidget);
    expect(find.text('Артём'), findsWidgets);

    await tester.tap(find.byKey(const Key('disp_approve_0')));
    await settle(tester);
    expect(find.text('Нет откликов, ожидающих решения.'), findsOneWidget);
    // одобренный отклик → грузчик в бригаде
    expect(find.text('Артём'), findsWidgets);
  });

  testWidgets('диспетчер: принудительное закрытие с комментарием', (tester) async {
    final repo = MockOrdersRepository();
    await tester.pumpWidget(AvatarApp(repository: repo));
    await settle(tester, 2);
    await login(tester);
    await tester.tap(find.text('Диспетчер'));
    await settle(tester);
    await tester.tap(find.ancestor(
      of: find.textContaining('ул. Ленина, 12'),
      matching: find.byKey(const Key('disp_order_card')),
    ));
    await settle(tester);

    await tester.tap(find.byKey(const Key('disp_force_btn')));
    await settle(tester, 2);
    await tester.enterText(
        find.byKey(const Key('disp_force_comment')), 'Клиент отменил');
    await tester.tap(find.byKey(const Key('disp_force_confirm')));
    await settle(tester);

    final order = await repo.getOrder(orderId: 'ord-1001');
    expect(order.status, OrderStatus.completed);
    expect(order.forceClosed, isTrue);
  });
}
