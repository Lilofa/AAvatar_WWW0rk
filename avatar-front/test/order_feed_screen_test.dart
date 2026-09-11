/// ВИДЖЕТ-ТЕСТЫ экрана ленты: те самые «четыре состояния», за которые ревьюит Коля.
///
/// Зона: Артём. Проверям, что OrderFeedScreen:
///   1. стартует в loading (shimmer), а не мигает пустотой;
///   2. приходит в data и рисует карточки из репозитория;
///   3. в режиме empty показывает осмысленный текст И кнопку;
///   4. в режиме error показывает готовый текст из AppFailure и «Повторить».
library;

import 'package:avatar_app/data/mock_orders_repository.dart';
import 'package:avatar_app/features/order_feed/presentation/order_feed_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  setUp(() {
    MockControls.instant = true;
    MockControls.mode = MockMode.normal;
    MockControls.randomErrorEveryN = 0;
    MockControls.simulateOffline = false;
    MockControls.simulateRaceCondition = false;
  });

  testWidgets('loading → data: карточки приходят из репозитория', (tester) async {
    await tester.pumpWidget(wrap(OrderFeedScreen(repository: MockOrdersRepository())));

    // Первый кадр — shimmer, не пустота и не спиннер.
    expect(find.text('Доступные заказы'), findsOneWidget);
    await tester.pump(); // стрим отдаёт первый кадр
    expect(find.text('Заказов сейчас нет'), findsNothing);

    await tester.pumpAndSettle();
    // Сид мока: срочный заказ на Ленина, 12 должен быть в ленте.
    expect(find.textContaining('ул. Ленина, 12'), findsWidgets);
    expect(find.textContaining('Срочно'), findsWidgets);
    // Формулировка для грузчика: никакого «дедлайна».
    expect(find.textContaining('Успеть взять до'), findsWidgets);
    expect(find.textContaining('дедлайн'), findsNothing);
  });

  testWidgets('empty: текст + действие, а не голая картинка', (tester) async {
    MockControls.mode = MockMode.empty;
    await tester.pumpWidget(wrap(OrderFeedScreen(repository: MockOrdersRepository())));
    await tester.pumpAndSettle();

    expect(find.text('Заказов сейчас нет'), findsOneWidget);
    expect(find.text('Обновить'), findsOneWidget);
  });

  testWidgets('error: текст из AppFailure и кнопка «Повторить»', (tester) async {
    MockControls.mode = MockMode.error;
    await tester.pumpWidget(wrap(OrderFeedScreen(repository: MockOrdersRepository())));
    await tester.pumpAndSettle();

    // Текст приходит готовым из Failures.server() — не сочиняется в виджете.
    expect(find.textContaining('Ошибка на сервере'), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);
  });

  testWidgets('retry из error возвращает в data', (tester) async {
    MockControls.mode = MockMode.error;
    await tester.pumpWidget(wrap(OrderFeedScreen(repository: MockOrdersRepository())));
    await tester.pumpAndSettle();
    expect(find.text('Повторить'), findsOneWidget);

    MockControls.mode = MockMode.normal;
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();

    expect(find.textContaining('ул. Ленина, 12'), findsWidgets);
  });

  testWidgets('debug-меню состояний открывается (showMockSwitch)', (tester) async {
    await tester.pumpWidget(wrap(
      OrderFeedScreen(repository: MockOrdersRepository(), showMockSwitch: true),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.bug_report_outlined));
    await tester.pumpAndSettle();

    expect(find.text('empty'), findsOneWidget);
    expect(find.text('error'), findsOneWidget);
  });
}
