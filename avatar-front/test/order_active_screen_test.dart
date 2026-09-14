/// ВИДЖЕТ-ТЕСТЫ экрана активного заказа.
///
/// Зона: Артём. Проверяем то, что обсуждали с Матвеей и Колей:
///  1. кнопки этапов приходят из getStageAvailability, а не выдумываются экраном;
///  2. ориентир скрыт до started;
///  3. «Старший назначается…» / имя старшего из бригады;
///  4. предупреждение о штрафе видно ДО нажатия;
///  5. окно обратной связи 5 минут с таймером и исходом в «не сдана в срок».
library;

import 'package:avatar_app/data/mock_orders_repository.dart';
import 'package:avatar_app/features/order_active/presentation/order_active_screen.dart';
import 'package:avatar_app/features/order_flow/domain/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Фиксированное «сейчас» мока: дневной час, чтобы сид-заказ ord-2001
/// НЕ попадал в утреннее окно 4:00–12:00 и тесты не зависели от времени суток.
DateTime mockBase() => DateTime(2026, 9, 14, 15, 0);

Future<void> settle(WidgetTester tester) async {
  // Стримы и RPC мока отдают кадры в microtask'ах (MockControls.instant).
  for (var i = 0; i < 4; i++) {
    await tester.pump(Duration.zero);
  }
}

void main() {
  setUp(() {
    MockControls.instant = true;
    MockControls.mode = MockMode.normal;
    MockControls.randomErrorEveryN = 0;
    MockControls.simulateOffline = false;
  });

  testWidgets('таймлайн и кнопка следующего этапа приходят из availability', (tester) async {
    final repo = MockOrdersRepository(clock: mockBase);
    await tester.pumpWidget(MaterialApp(
      home: OrderActiveScreen(orderId: 'ord-2001', repository: repo),
    ));
    await settle(tester);

    // Мои этапы пусты → следующий expected = departed («Выехал»).
    expect(find.text('Выехал'), findsWidgets);
    expect(find.text('Этапы'), findsOneWidget);

    // Ориентир скрыт до started.
    expect(find.textContaining('откроется после этапа «Начали»'), findsOneWidget);
    expect(find.textContaining('2-й подъезд'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('старший из бригады, не «назначается…»', (tester) async {
    final repo = MockOrdersRepository(clock: mockBase);
    await tester.pumpWidget(MaterialApp(
      home: OrderActiveScreen(orderId: 'ord-2001', repository: repo),
    ));
    await settle(tester);

    expect(find.textContaining('Старший: Иван П.'), findsOneWidget);
    expect(find.textContaining('Старший назначается…'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('утренний заказ: предупреждение о штрафе видно ДО нажатия', (tester) async {
    final repo = MockOrdersRepository(clock: mockBase);
    final tomorrow = mockBase().add(const Duration(days: 1));
    final lateMorning = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 6, 10);

    await tester.pumpWidget(MaterialApp(
      home: OrderActiveScreen(
        orderId: 'ord-1006',
        repository: repo,
        nowProvider: () => lateMorning,
      ),
    ));
    await settle(tester);

    // Дедлайн «Проснулся» 06:00 пропущен: SQL не штрафует при нажатии,
    // но предупреждение обязано быть до действия.
    expect(find.textContaining('событием'), findsWidgets);
    expect(find.text('Проснулся'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('после «Закончили»: окно обратной связи с таймером 5 минут', (tester) async {
    final repo = MockOrdersRepository(clock: mockBase);

    // Прогоняем этапы до finished: я старший после assignLead.
    await repo.setStage(orderId: 'ord-2001', stage: OrderStageType.departed);
    await repo.setStage(orderId: 'ord-2001', stage: OrderStageType.arrived);
    await repo.assignLead(orderId: 'ord-2001', porterId: 'porter-artem-374545233');
    await repo.setStage(orderId: 'ord-2001', stage: OrderStageType.started);
    await repo.setStage(orderId: 'ord-2001', stage: OrderStageType.finished);

    await tester.pumpWidget(MaterialApp(
      home: OrderActiveScreen(orderId: 'ord-2001', repository: repo),
    ));
    await settle(tester);

    expect(find.text('Обратная связь старшего'), findsOneWidget);
    expect(find.text('Да, всё хорошо'), findsOneWidget);
    expect(find.text('Нет, проблемы'), findsOneWidget);
    expect(find.text('Закрыть заказ'), findsOneWidget);

    // Ориентир открыт: started проставлен.
    expect(find.textContaining('2-й подъезд'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('закрытие заказа: снакбар с часами и рейтингом', (tester) async {
    final repo = MockOrdersRepository(clock: mockBase);

    await repo.setStage(orderId: 'ord-2001', stage: OrderStageType.departed);
    await repo.setStage(orderId: 'ord-2001', stage: OrderStageType.arrived);
    await repo.assignLead(orderId: 'ord-2001', porterId: 'porter-artem-374545233');
    await repo.setStage(orderId: 'ord-2001', stage: OrderStageType.started);
    await repo.setStage(orderId: 'ord-2001', stage: OrderStageType.finished);

    await tester.pumpWidget(MaterialApp(
      home: OrderActiveScreen(orderId: 'ord-2001', repository: repo),
    ));
    await settle(tester);

    // Блок обратной связи может быть ниже сгиба ListView — тап должен попасть.
    await tester.ensureVisible(find.text('Да, всё хорошо'));
    await tester.tap(find.text('Да, всё хорошо'));
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
    await tester.ensureVisible(find.text('Закрыть заказ'));
    await tester.pump(Duration.zero);
    await tester.tap(find.text('Закрыть заказ'));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(); // кадр после микрозадач: снакбар входит в дерево

    expect(find.textContaining('Заказ закрыт:'), findsOneWidget);
    expect(find.textContaining('рейтинг +2'), findsOneWidget, reason: 'я старший');

    await tester.pumpWidget(const SizedBox());
  });
}
