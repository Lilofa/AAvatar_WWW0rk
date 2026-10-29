/// ТЕСТЫ MVP-КУСКОВ: отклик с ETA (диалог) и визард создания заявки.
library;

import 'package:avatar_app/data/mock_orders_repository.dart';
import 'package:avatar_app/features/client_orders/presentation/client_cabinet_screen.dart';
import 'package:avatar_app/features/create_order/presentation/create_order_screen.dart';
import 'package:avatar_app/features/order_feed/presentation/order_feed_screen.dart';
import 'package:avatar_app/features/order_response/presentation/respond_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    MockControls.instant = true;
    MockControls.mode = MockMode.normal;
    MockControls.randomErrorEveryN = 1000000;
    MockControls.simulateOffline = false;
    MockControls.simulateDispatcher = false; // без висящих Timer в тестах
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

  /// Тап по элементу, который может быть ниже сгиба экрана.
  Future<void> tapKey(WidgetTester tester, Key key) async {
    final target = find.byKey(key);
    // ensureVisible на длинной форме недоскрапливает — доскралливаем явно
    if (target.hitTestable().evaluate().isEmpty) {
      final scroller = find
          .ancestor(of: target, matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(target, 120, scrollable: scroller);
    }
    await tester.pumpAndSettle();
    await tester.tap(target);
    await settle(tester, 2);
  }

  group('отклик с ETA', () {
    testWidgets('диалог: ETA 20 → отклик отправлен, чип статуса на карточке',
        (tester) async {
      final repo = MockOrdersRepository();
      await tester.pumpWidget(MaterialApp(
        home: OrderFeedScreen(
          repository: repo,
          onRespond: (order) => RespondDialog.show(
            tester.element(find.byType(OrderFeedScreen)),
            repository: repo,
            order: order,
          ),
        ),
      ));
      await settle(tester);
      expect(find.byKey(const Key('feed_respond_btn')), findsWidgets);

      await tester.tap(find.byKey(const Key('feed_respond_btn')).first);
      await settle(tester, 2);
      expect(find.byKey(const Key('respond_eta')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('respond_eta')), '20');
      await tester.tap(find.byKey(const Key('respond_confirm')));
      await settle(tester);
      // диалог закрылся без ошибки валидации
      expect(find.byKey(const Key('respond_eta')), findsNothing);
      expect(find.byKey(const Key('respond_error')), findsNothing);

      // ПРОДУКТОВО: чип статуса приезжает в живую ленту событием
      // (мок: _emitFeed на отклике; live: триггер из order_responses)
      await settle(tester, 4);
      expect(find.byKey(const Key('feed_my_response_chip')), findsWidgets);
      expect(find.textContaining('Отклик отправлен'), findsOneWidget);
    });

    testWidgets('диалог: ETA 0 не проходит валидацию', (tester) async {
      final repo = MockOrdersRepository();
      await tester.pumpWidget(MaterialApp(
        home: OrderFeedScreen(
          repository: repo,
          onRespond: (order) => RespondDialog.show(
            tester.element(find.byType(OrderFeedScreen)),
            repository: repo,
            order: order,
          ),
        ),
      ));
      await settle(tester);
      await tester.tap(find.byKey(const Key('feed_respond_btn')).first);
      await settle(tester, 2);
      await tester.enterText(find.byKey(const Key('respond_eta')), '0');
      await tester.tap(find.byKey(const Key('respond_confirm')));
      await settle(tester, 2);
      expect(find.byKey(const Key('respond_error')), findsOneWidget);
    });
  });

  group('визард создания заявки', () {
    testWidgets('автодополнение адреса + калькулятор + создание',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: CreateOrderScreen(repository: MockOrdersRepository()),
      ));
      await settle(tester, 2);

      await tester.enterText(find.byKey(const Key('create_address')), 'Ленина');
      // дебаунс 400 мс
      await tester.pump(const Duration(milliseconds: 500));
      await settle(tester, 2);
      expect(find.byKey(const Key('create_suggest_box')), findsOneWidget);
      await tapKey(tester, const Key('create_suggest_0'));

      await tapKey(tester, const Key('create_people_plus'));
      await tapKey(tester, const Key('create_duration_plus'));
      await tapKey(tester, const Key('create_urgency_urgent'));
      await tapKey(tester, const Key('create_transport_gazelle'));

      await tapKey(tester, const Key('create_quote_btn'));
      expect(find.byKey(const Key('create_quote_panel')), findsOneWidget);
      expect(find.textContaining('Итого:'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('create_title')));
      await tester.enterText(
          find.byKey(const Key('create_title')), 'Коробки с вещами');
      // submit вызываем колбэком: геометрия длинной формы — не предмет теста
      tester
          .widget<FilledButton>(find.byKey(const Key('create_submit')))
          .onPressed!();
      await settle(tester);
      expect(find.byKey(const Key('create_done')), findsOneWidget);
    });

    testWidgets('без адреса и названия — ошибка валидации, заказ не создан',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: CreateOrderScreen(repository: MockOrdersRepository()),
      ));
      await settle(tester, 2);
      await tapKey(tester, const Key('create_submit'));
      expect(find.byKey(const Key('create_error')), findsOneWidget);
      expect(find.byKey(const Key('create_done')), findsNothing);
    });

    testWidgets('FAB «Создать заявку» есть в «Моих заказах» и открывает визард',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ClientCabinetScreen(repository: MockOrdersRepository()),
      ));
      await settle(tester);
      await tester.tap(find.byKey(const Key('client_create_fab')));
      await settle(tester, 2);
      expect(find.byKey(const Key('create_submit')), findsOneWidget);
    });
  });
}
