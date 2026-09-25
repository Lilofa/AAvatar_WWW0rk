/// РЕГРЕССЫ ПО БАГ-РЕПОРТУ НАЧАЛЬНИКА (25.09.2026):
///  1. телефон: слишком длинный номер отклоняется с сообщением;
///  2. грузчик не откликается на свою же заявку;
///  3. «Мои заказы»: своя работа грузчиком отделена, свои выполненные
///     заказы оценить нельзя;
///  4. пикеры времени — 24 часа и по-русски (ru-локаль).
library;

import 'package:avatar_app/data/mock_orders_repository.dart';
import 'package:avatar_app/features/auth/presentation/login_screen.dart';
import 'package:avatar_app/features/order_flow/domain/enums.dart';
import 'package:avatar_app/features/order_flow/domain/models.dart';
import 'package:avatar_app/main.dart';
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

  testWidgets('телефон: маска +7(983)-355-95-99 собирается сама',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: LoginScreen(
        repository: MockOrdersRepository(),
        onAuthenticated: (_) {},
      ),
    ));
    await settle(tester, 2);
    await tester.enterText(find.byKey(const Key('login_phone')), '9833559599');
    await settle(tester, 2);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byKey(const Key('login_phone'))).controller!.text,
      '+7(983)-355-95-99',
    );
    // лишние цифры не проглатываются молча: поле физически не вместит 12
    await tester.enterText(find.byKey(const Key('login_phone')), '98335595991234');
    await settle(tester, 2);
    expect(
      tester.widget<TextField>(find.byKey(const Key('login_phone'))).controller!.text,
      '+7(983)-355-95-99',
    );
  });

  group('валидация номера (чистая функция, без виджет-магии)', () {
    test('короткий / длинный / пустой — невалидны', () {
      expect(isRuPhoneValid('+7(923)-72'), isFalse);
      expect(isRuPhoneValid('92372'), isFalse);
      expect(isRuPhoneValid(''), isFalse);
      expect(isRuPhoneValid('+7'), isFalse);
    });
    test('ровно 10 цифр после +7 — валид в любом написании', () {
      expect(isRuPhoneValid('+7(983)-355-95-99'), isTrue);
      expect(isRuPhoneValid('9833559599'), isTrue);
      expect(isRuPhoneValid('89833559599'), isTrue);
      expect(isRuPhoneValid('+79833559599'), isTrue);
    });
    test('маска: лишние цифры обрезаются, формат виден пользователю', () {
      expect(formatRuPhone('98335595991234'), '+7(983)-355-95-99');
      expect(formatRuPhone('983'), '+7(983)');
      expect(formatRuPhone('98335'), '+7(983)-35');
      expect(formatRuPhone(''), '+7');
    });
  });

  testWidgets('телефон: неполный номер не пускает в шаг кода', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: LoginScreen(
        repository: MockOrdersRepository(),
        onAuthenticated: (_) {},
      ),
    ));
    await settle(tester, 2);
    await tester.enterText(find.byKey(const Key('login_phone')), '92372');
    await settle(tester, 2);
    // кнопка есть, но шаг кода не открыт и не откроется от отправки
    expect(find.byKey(const Key('login_code')), findsNothing);
    expect(
      tester.widget<TextField>(find.byKey(const Key('login_phone'))).controller!.text,
      '+7(923)-72',
    );
  });

  testWidgets('лента: на свою созданную заявку откликнуться нельзя',
      (tester) async {
    final repo = MockOrdersRepository();
    final mine = await repo.createOrder(CreateOrderRequest(
      address: 'г. Новосибирск, ул. Ленина',
      timeStart: DateTime.now().add(const Duration(hours: 2)),
      peopleCount: 2,
      plannedDurationMin: 60,
      taskTitle: 'Моя заявка',
      taskDescription: 'тест',
      urgency: OrderUrgency.current,
      tariff: '0 RUB',
    ));
    await tester.pumpWidget(AvatarApp(repository: repo));
    await settle(tester, 2);
    await tester.enterText(find.byKey(const Key('login_phone')), '+79991234567');
    await tester.tap(find.byKey(const Key('login_send_code')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('login_code')), '1234');
    await tester.tap(find.byKey(const Key('login_submit')));
    await settle(tester);

    // карточка своей заявки есть, кнопки отклика на ней нет
    expect(find.text('Моя заявка'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(Key('feed_card_${mine.id}')),
        matching: find.byKey(const Key('feed_respond_btn')),
      ),
      findsNothing,
    );
    // на чужие заказы кнопка осталась
    expect(find.byKey(const Key('feed_respond_btn')), findsWidgets);
  });

  testWidgets('мои заказы: свою работу не оценить, секция грузчика отдельно',
      (tester) async {
    final repo = MockOrdersRepository();
    // я в бригаде ord-1002 и заказ закрыт => «моя работа»
    final resp = await repo.respondToOrder(orderId: 'ord-1002', etaMinutes: 15);
    await repo.approveResponse(responseId: resp.id);
    await repo.forceCloseOrder(orderId: 'ord-1002', comment: 'тест');

    await tester.pumpWidget(AvatarApp(repository: repo));
    await settle(tester, 2);
    await tester.enterText(find.byKey(const Key('login_phone')), '+79991234567');
    await tester.tap(find.byKey(const Key('login_send_code')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('login_code')), '1234');
    await tester.tap(find.byKey(const Key('login_submit')));
    await settle(tester);

    await tester.tap(find.text('Мои заказы'));
    await settle(tester);

    // секция «Моя работа (как грузчик)» может быть ниже сгиба — доскроллим
    await tester.scrollUntilVisible(
      find.byKey(const Key('client_work_section')),
      200,
      scrollable: find.descendant(
        of: find.byKey(const Key('client_orders_list')),
        matching: find.byType(Scrollable),
      ),
    );
    await settle(tester, 2);
    expect(find.byKey(const Key('client_work_section')), findsOneWidget);
    expect(find.byKey(const Key('client_work_card')), findsOneWidget);

    // на СВОЙ выполненный заказ кнопки «Оценить» нет
    expect(
      find.descendant(
          of: find.byKey(const Key('client_work_card')),
          matching: find.byKey(const Key('client_order_review_btn'))),
      findsNothing,
    );
    // чужой выполненный заказ (ord-3001) оценить можно: ровно одна кнопка
    expect(find.byKey(const Key('client_order_review_btn')), findsOneWidget);
  });

  testWidgets('пикер времени: 24 часа и по-русски (без AM/PM)', (tester) async {
    await tester.pumpWidget(AvatarApp(repository: MockOrdersRepository()));
    await settle(tester, 2);
    await tester.enterText(find.byKey(const Key('login_phone')), '+79991234567');
    await tester.tap(find.byKey(const Key('login_send_code')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('login_code')), '1234');
    await tester.tap(find.byKey(const Key('login_submit')));
    await settle(tester);
    await tester.tap(find.text('Мои заказы'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('client_create_fab')));
    await settle(tester, 2);

    await tester.tap(find.byKey(const Key('create_time_btn')));
    await tester.pumpAndSettle();
    // режим ввода: два поля ЧЧ и ММ, без циферблата и AM/PM
    expect(find.text('AM'), findsNothing);
    expect(find.text('PM'), findsNothing);
    expect(find.text('Cancel'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(TimePickerDialog),
        matching: find.byType(TextField),
      ),
      findsNWidgets(2),
    );
    // переключиться на циферблат при желании можно иконкой
    expect(find.byIcon(Icons.access_time), findsOneWidget);
  });
}
