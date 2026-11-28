/// Удаление аккаунта из кабинета (App Store 5.1.1(v), Политика п. 10).
library;

import 'package:avatar_app/core/ui/sign_out.dart';
import 'package:avatar_app/data/mock_orders_repository.dart';
import 'package:avatar_app/features/client_orders/presentation/client_cabinet_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    MockControls.instant = true;
    MockControls.mode = MockMode.normal;
    MockControls.randomErrorEveryN = 0;
    MockControls.simulateDispatcher = false;
  });

  tearDown(() {
    MockControls.instant = false;
    MockControls.simulateDispatcher = true;
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<int> open(WidgetTester tester) async {
    var signedOut = 0;
    await tester.pumpWidget(MaterialApp(
      home: SignOutProvider(
        onSignOut: () async => signedOut++,
        child: ClientCabinetScreen(repository: MockOrdersRepository()),
      ),
    ));
    await settle(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('cab_delete_account')),
      300,
      scrollable: find.descendant(
        of: find.byKey(const Key('client_orders_list')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.byKey(const Key('cab_delete_account')));
    await settle(tester);
    return signedOut;
  }

  testWidgets('отмена — ничего не происходит', (tester) async {
    await open(tester);
    expect(find.text('Удалить аккаунт?'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await settle(tester);
    expect(find.byKey(const Key('delete_account_done')), findsNothing);
  });

  testWidgets('подтверждение — аккаунт удалён и выход', (tester) async {
    var signedOut = 0;
    await tester.pumpWidget(MaterialApp(
      home: SignOutProvider(
        onSignOut: () async => signedOut++,
        child: ClientCabinetScreen(repository: MockOrdersRepository()),
      ),
    ));
    await settle(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('cab_delete_account')),
      300,
      scrollable: find.descendant(
        of: find.byKey(const Key('client_orders_list')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.byKey(const Key('cab_delete_account')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('delete_account_confirm')));
    await settle(tester);
    expect(find.byKey(const Key('delete_account_done')), findsOneWidget);
    expect(signedOut, 1);
  });
}
