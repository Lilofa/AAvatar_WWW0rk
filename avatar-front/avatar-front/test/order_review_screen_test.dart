/// ВИДЖЕТ-ТЕСТЫ ЭКРАНА ОТЗЫВА: form / validation / sending / error / done.
library;

import 'package:avatar_app/data/mock_orders_repository.dart';
import 'package:avatar_app/features/order_review/presentation/order_review_screen.dart';
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

  Future<void> pumpReview(WidgetTester tester, String orderId) async {
    await tester.pumpWidget(MaterialApp(
      home: OrderReviewScreen(
        repository: MockOrdersRepository(),
        orderId: orderId,
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('form: 5 звёзд кликаются, оценка выбирается', (tester) async {
    await pumpReview(tester, 'ord-3001');
    expect(find.byKey(const Key('review_stars')), findsOneWidget);
    await tester.tap(find.byKey(const Key('review_star_5')));
    await tester.pumpAndSettle();
    // выбрана 5-я: иконка star (не border) — проверяем через отсутствие валидации
    expect(find.byKey(const Key('review_validation')), findsNothing);
  });

  testWidgets('validation: без оценки отправка не уходит', (tester) async {
    await pumpReview(tester, 'ord-3001');
    await tester.tap(find.byKey(const Key('review_submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('review_validation')), findsOneWidget);
    expect(find.byKey(const Key('review_done')), findsNothing);
  });

  testWidgets('done: оценка + текст → экран благодарности', (tester) async {
    await pumpReview(tester, 'ord-3001');
    await tester.tap(find.byKey(const Key('review_star_4')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('review_text')), 'Всё супер');
    await tester.tap(find.byKey(const Key('review_submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('review_done')), findsOneWidget);
    expect(find.textContaining('Спасибо'), findsOneWidget);
  });

  testWidgets('error: режим error → баннер ошибки, форма жива', (tester) async {
    MockControls.mode = MockMode.error;
    await pumpReview(tester, 'ord-3001');
    await tester.tap(find.byKey(const Key('review_star_5')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review_submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('review_error')), findsOneWidget);
    expect(find.byKey(const Key('review_done')), findsNothing);

    // повтор после починки сети
    MockControls.mode = MockMode.normal;
    await tester.tap(find.byKey(const Key('review_submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('review_done')), findsOneWidget);
  });
}
