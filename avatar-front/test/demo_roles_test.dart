import 'package:avatar_app/data/mock_orders_repository.dart';
import 'package:avatar_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    MockControls.instant = true;
    MockControls.mode = MockMode.normal;
    MockControls.randomErrorEveryN = 0;
    MockControls.simulateDispatcher = false;
    MockControls.demoRoles = MockControls.allDemoRoles;
  });
  tearDown(() => MockControls.demoRoles = MockControls.allDemoRoles);

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> login(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('login_phone')), '+79991234567');
    await tester.ensureVisible(find.byKey(const Key('login_consent')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('login_consent')));
    await tester.ensureVisible(find.byKey(const Key('login_send_code')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('login_send_code')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('login_code')), '1234');
    await tester.tap(find.byKey(const Key('login_submit')));
    await settle(tester);
  }

  Future<void> pickRole(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(const Key('demo_strip')));
    await settle(tester);
    await tester.tap(find.byKey(Key('demo_role_$name')));
    await settle(tester);
  }

  testWidgets('демо: переключение ролей перестраивает вкладки без падений',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
        AvatarApp(repository: MockOrdersRepository(), demoMode: true));
    await settle(tester);
    await login(tester);
    expect(find.textContaining('роль: Все роли'), findsOneWidget);
    expect(find.text('Диспетчер'), findsOneWidget);

    // Заказчик: одна вкладка — без нижней панели, сразу кабинет.
    await pickRole(tester, 'Заказчик');
    expect(find.textContaining('роль: Заказчик'), findsOneWidget);
    expect(find.byKey(const Key('shell_nav')), findsNothing);
    expect(find.text('Кабинет'), findsOneWidget);

    // Грузчик: лента и рефералы.
    await pickRole(tester, 'Грузчик');
    expect(find.text('Лента'), findsOneWidget);
    expect(find.text('Рефералы'), findsOneWidget);
    expect(find.text('Диспетчер'), findsNothing);

    // Админ: пульт диспетчера.
    await pickRole(tester, 'Админ');
    expect(find.text('Пульт диспетчера'), findsOneWidget);

    // И обратно ко всем ролям.
    await pickRole(tester, 'Все роли');
    expect(find.byKey(const Key('shell_nav')), findsOneWidget);
  });
}
