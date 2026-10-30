/// ТЕСТЫ КАБИНЕТА: шапка профиля, секции, empty/error, FAB.
library;

import 'package:avatar_app/data/mock_orders_repository.dart';
import 'package:avatar_app/features/client_orders/presentation/client_cabinet_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    MockControls.instant = true;
    MockControls.mode = MockMode.normal;
    MockControls.randomErrorEveryN = 0;
    MockControls.simulateOffline = false;
    MockControls.simulateDispatcher = false;
  });

  tearDown(() {
    MockControls.instant = false;
    MockControls.mode = MockMode.normal;
    MockControls.simulateDispatcher = true;
  });

  Future<void> settle(WidgetTester tester, [int frames = 4]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('data: шапка профиля, роли, секция заказчика с оценкой',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ClientCabinetScreen(repository: MockOrdersRepository()),
    ));
    await settle(tester);
    expect(find.byKey(const Key('cab_profile')), findsOneWidget);
    expect(find.text('Артём'), findsOneWidget);
    expect(find.text('грузчик'), findsOneWidget);
    expect(find.text('заказчик'), findsOneWidget);
    expect(find.text('диспетчер'), findsOneWidget);
    expect(find.byKey(const Key('cab_client_section')), findsOneWidget);
    // завершённый чужой заказ клиента можно оценить (кнопка ниже сгиба)
    await tester.scrollUntilVisible(
      find.byKey(const Key('client_order_review_btn')),
      200,
      scrollable: find.descendant(
        of: find.byKey(const Key('client_orders_list')),
        matching: find.byType(Scrollable),
      ),
    );
    await settle(tester, 2);
    expect(find.byKey(const Key('client_order_review_btn')), findsOneWidget);
    expect(find.byKey(const Key('client_create_fab')), findsOneWidget);
  });

  testWidgets('empty: нет заказов — заглушка', (tester) async {
    MockControls.mode = MockMode.empty;
    await tester.pumpWidget(MaterialApp(
      home: ClientCabinetScreen(repository: MockOrdersRepository()),
    ));
    await settle(tester);
    expect(find.byKey(const Key('cab_empty')), findsOneWidget);
  });

  testWidgets('error: плашка и повтор', (tester) async {
    MockControls.mode = MockMode.error;
    await tester.pumpWidget(MaterialApp(
      home: ClientCabinetScreen(repository: MockOrdersRepository()),
    ));
    await settle(tester);
    expect(find.byKey(const Key('cab_error')), findsOneWidget);
    MockControls.mode = MockMode.normal;
    await tester.tap(find.byKey(const Key('cab_retry')));
    await settle(tester);
    expect(find.byKey(const Key('cab_profile')), findsOneWidget);
  });
}
