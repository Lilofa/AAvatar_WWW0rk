/// ВИДЖЕТ-ТЕСТЫ ЧАТА ЗАКАЗА: loading / data / empty / error + отправка.
library;

import 'package:avatar_app/data/mock_orders_repository.dart';
import 'package:avatar_app/features/order_chat/presentation/order_chat_screen.dart';
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

  Future<void> pumpChat(WidgetTester tester, String orderId) async {
    await tester.pumpWidget(MaterialApp(
      home: OrderChatScreen(
        repository: MockOrdersRepository(),
        orderId: orderId,
      ),
    ));
  }

  testWidgets('data: сид-сообщение диспетчера рисуется пузырём', (tester) async {
    await pumpChat(tester, 'ord-2001');
    await tester.pumpAndSettle();
    expect(
      find.text('Бригада на месте, начинайте. Клиент ждёт у подъезда.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('chat_list')), findsOneWidget);
  });

  testWidgets('data: отправка добавляет сообщение в ленту чата', (tester) async {
    await pumpChat(tester, 'ord-2001');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('chat_input')), 'Поднимаемся');
    await tester.tap(find.byKey(const Key('chat_send')));
    await tester.pumpAndSettle();
    expect(find.text('Поднимаемся'), findsOneWidget);
    expect(find.byKey(const Key('chat_input')), findsOneWidget);
  });

  testWidgets('empty: заказ без сообщений — заглушка «Напишите первым»',
      (tester) async {
    await pumpChat(tester, 'ord-1001');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat_empty')), findsOneWidget);
  });

  testWidgets('error: режим error → плашка и «Повторить»; повтор оживает',
      (tester) async {
    MockControls.mode = MockMode.error;
    await pumpChat(tester, 'ord-2001');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat_error')), findsOneWidget);
    expect(find.byKey(const Key('chat_retry')), findsOneWidget);

    MockControls.mode = MockMode.normal;
    await tester.tap(find.byKey(const Key('chat_retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat_error')), findsNothing);
    expect(find.byKey(const Key('chat_list')), findsOneWidget);
  });

  testWidgets('sending: пустое сообщение не отправляется', (tester) async {
    await pumpChat(tester, 'ord-2001');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat_send')));
    await tester.pumpAndSettle();
    // лента не изменилась: по-прежнему одно сид-сообщение
    expect(find.text('Бригада на месте, начинайте. Клиент ждёт у подъезда.'),
        findsOneWidget);
    expect(find.text('Поднимаемся'), findsNothing);
  });
}
