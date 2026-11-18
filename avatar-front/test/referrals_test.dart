/// ТЕСТЫ ЭКРАНА РЕФЕРАЛКИ (v2): data / empty+генерация / error / вкладка.
library;

import 'package:avatar_app/data/mock_orders_repository.dart';
import 'package:avatar_app/features/referrals/presentation/referrals_screen.dart';
import 'package:avatar_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('data: код, копирование, список со статусами', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ReferralsScreen(repository: MockOrdersRepository()),
    ));
    await settle(tester);
    expect(find.byKey(const Key('ref_code')), findsOneWidget);
    expect(find.text('ARTEM26'), findsOneWidget);
    expect(find.byKey(const Key('ref_entry')), findsNWidgets(2));
    expect(find.text('засчитан'), findsOneWidget);
    expect(find.text('новый'), findsOneWidget);
    expect(find.text('Приглашено: 2'), findsOneWidget);

    // Перехватываем платформенный канал: getData в тестах может виснуть,
    // а факт копирования доказываем пойманным Clipboard.setData.
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    await tester.tap(find.byKey(const Key('ref_copy')));
    await settle(tester, 2);
    expect(
      calls.any((c) =>
          c.method == 'Clipboard.setData' &&
          (c.arguments as Map)['text'] == 'ARTEM26'),
      isTrue,
      reason: 'кнопка копирования кладёт код в буфер',
    );
  });

  testWidgets('empty: нет кода — генерация; нет приглашённых — заглушка',
      (tester) async {
    MockControls.mode = MockMode.empty;
    await tester.pumpWidget(MaterialApp(
      home: ReferralsScreen(repository: MockOrdersRepository()),
    ));
    await settle(tester);
    expect(find.byKey(const Key('ref_gen')), findsOneWidget);
    expect(find.byKey(const Key('ref_empty')), findsOneWidget);

    await tester.tap(find.byKey(const Key('ref_gen')));
    await settle(tester);
    expect(find.byKey(const Key('ref_code')), findsOneWidget);
    expect(
      tester.widget<SelectableText>(find.byKey(const Key('ref_code'))).data,
      'ARTEM26',
    );
  });

  testWidgets('error: плашка и повтор оживают', (tester) async {
    MockControls.mode = MockMode.error;
    await tester.pumpWidget(MaterialApp(
      home: ReferralsScreen(repository: MockOrdersRepository()),
    ));
    await settle(tester);
    expect(find.byKey(const Key('ref_error')), findsOneWidget);

    MockControls.mode = MockMode.normal;
    await tester.tap(find.byKey(const Key('ref_retry')));
    await settle(tester);
    expect(find.byKey(const Key('ref_code')), findsOneWidget);
  });

  testWidgets('shell: вкладка «Рефералы» у грузчика', (tester) async {
    await tester.pumpWidget(AvatarApp(repository: MockOrdersRepository()));
    await settle(tester, 2);
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

    expect(find.text('Рефералы'), findsOneWidget);
    await tester.tap(find.text('Рефералы'));
    await settle(tester);
    expect(find.byKey(const Key('ref_code')), findsOneWidget);
  });
}
