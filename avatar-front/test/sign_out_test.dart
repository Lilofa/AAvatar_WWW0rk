import 'package:avatar_app/data/mock_orders_repository.dart';
import 'package:avatar_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Баг владельца: «Не работает кнопка выйти». Кнопки не было вовсе —
/// теперь она есть на всех корневых вкладках и возвращает на экран входа.
void main() {
  setUp(() {
    MockControls.instant = true;
    MockControls.mode = MockMode.normal;
    MockControls.randomErrorEveryN = 0;
  });

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> login(WidgetTester tester) async {
    await tester.enterText(
        find.byKey(const Key('login_phone')), '+79991234567');
    await tester.tap(find.byKey(const Key('login_send_code')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('login_code')), '1234');
    await tester.tap(find.byKey(const Key('login_submit')));
    await settle(tester);
  }

  testWidgets('выход: подтверждение → экран входа; повторный вход работает',
      (tester) async {
    await tester.pumpWidget(AvatarApp(repository: MockOrdersRepository()));
    await settle(tester);
    await login(tester);
    expect(find.byKey(const Key('shell_nav')), findsOneWidget);

    // Кнопка видна на активной вкладке (лента).
    final btn = find.byKey(const Key('sign_out_btn')).hitTestable();
    expect(btn, findsOneWidget);

    // Отмена — остаёмся внутри.
    await tester.tap(btn);
    await settle(tester);
    await tester.tap(find.text('Отмена'));
    await settle(tester);
    expect(find.byKey(const Key('shell_nav')), findsOneWidget);

    // Подтверждение — на экран входа.
    await tester.tap(btn);
    await settle(tester);
    await tester.tap(find.byKey(const Key('sign_out_confirm')));
    await settle(tester);
    expect(find.byKey(const Key('auth_login')), findsOneWidget);
    expect(find.byKey(const Key('shell_nav')), findsNothing);

    await login(tester);
    expect(find.byKey(const Key('shell_nav')), findsOneWidget);
  });

  testWidgets('кнопка выхода есть на каждой вкладке', (tester) async {
    await tester.pumpWidget(AvatarApp(repository: MockOrdersRepository()));
    await settle(tester);
    await login(tester);
    for (final tab in ['Мои заказы', 'Рефералы', 'Диспетчер', 'Лента']) {
      await tester.tap(find.text(tab));
      await settle(tester);
      expect(
          find.byKey(const Key('sign_out_btn')).hitTestable(), findsOneWidget,
          reason: 'вкладка $tab');
    }
  });
}
