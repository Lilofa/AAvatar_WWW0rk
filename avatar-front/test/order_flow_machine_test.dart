/// ЮНИТ-ТЕСТЫ БИЗНЕС-ПРАВИЛ ПОТОКА ЗАКАЗА.
///
/// Зона: Артём. Это единственная часть недели 1, которая НЕ зависит
/// ни от Коли (виджеты), ни от Матвея (Supabase) — поэтому делается сразу.
///
/// Запуск: `flutter test test/order_flow_machine_test.dart`
///
/// Эти тесты = формализованная логика бота raspredelenie. Если Матвей
/// реализует валидацию этапов на бэке иначе, тесты покажут расхождение
/// ДО того, как оно всплывёт на проде у живого грузчика.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:avatar_app/core/error/app_failure.dart';
import 'package:avatar_app/features/order_flow/domain/enums.dart';
import 'package:avatar_app/features/order_flow/domain/models.dart';
import 'package:avatar_app/features/order_flow/domain/order_state_machine.dart';

/// Опорное «сейчас»: 2026-09-11 05:30 локально.
final now = DateTime(2026, 9, 11, 5, 30);

Order buildOrder({
  String id = 'o1',
  required DateTime timeStart,
  OrderStatus status = OrderStatus.approved,
  OrderUrgency urgency = OrderUrgency.current,
  int peopleCount = 2,
  int plannedDurationMin = 60,
  DateTime? createdAt,
}) =>
    Order(
      id: id,
      clientId: 'c1',
      address: 'г. Новосибирск, ул. Ленина, 12',
      timeStart: timeStart,
      plannedDurationMin: plannedDurationMin,
      peopleCount: peopleCount,
      status: status,
      urgency: urgency,
      taskTitle: 'Переезд',
      taskDescription: 'Спустить коробки',
      entrance: '2-й подъезд',
      createdAt: createdAt,
    );

/// Утренний заказ: начало 07:00 → woke-дедлайн 06:00, departed-дедлайн 06:30.
final morningOrder = buildOrder(
  timeStart: DateTime(2026, 9, 11, 7, 0),
  plannedDurationMin: 180,
  peopleCount: 4,
);

/// Не утренний заказ: начало 14:00 → этапа «Проснулся» нет вовсе.
final dayOrder = buildOrder(timeStart: DateTime(2026, 9, 11, 14, 0));

StageDecision d({
  required Order order,
  required OrderStageType stage,
  List<OrderStageType> done = const [],
  bool isLead = false,
  bool inBrigade = true,
  DateTime? at,
  DateTime? finishedAt,
}) =>
    OrderFlowMachine.decide(
      stage: stage,
      order: order,
      done: done,
      isLead: isLead,
      inBrigade: inBrigade,
      now: at ?? now,
      finishedAt: finishedAt,
    );

void main() {
  group('Утренние заказы: этап «Проснулся» и дедлайны', () {
    test('утренний заказ (4:00–12:00) распознаётся', () {
      expect(morningOrder.isMorning, isTrue);
      expect(dayOrder.isMorning, isFalse);
      expect(buildOrder(timeStart: DateTime(2026, 9, 11, 4, 0)).isMorning, isTrue);
      expect(buildOrder(timeStart: DateTime(2026, 9, 11, 11, 59)).isMorning, isTrue);
      expect(buildOrder(timeStart: DateTime(2026, 9, 11, 12, 0)).isMorning, isFalse);
      expect(buildOrder(timeStart: DateTime(2026, 9, 11, 3, 59)).isMorning, isFalse);
    });

    test('дедлайны: «Проснулся» за 1 час, «Выехал» за 30 минут', () {
      expect(morningOrder.wokeDeadline, DateTime(2026, 9, 11, 6, 0));
      expect(morningOrder.departedDeadline, DateTime(2026, 9, 11, 6, 30));
    });

    test('у НЕутреннего заказа дедлайнов нет', () {
      expect(dayOrder.wokeDeadline, isNull);
      expect(dayOrder.departedDeadline, isNull);
    });

    test('woke разрешён до дедлайна и БЕЗ штрафа', () {
      final r = d(order: morningOrder, stage: OrderStageType.woke, at: DateTime(2026, 9, 11, 5, 30));
      expect(r.allowed, isTrue);
      expect(r.late, isFalse);
      expect(r.penalty, 0);
      expect(r.warning, isNull);
    });

    test('woke после дедлайна: разрешён, но штраф −5 и предупреждение', () {
      final r = d(order: morningOrder, stage: OrderStageType.woke, at: DateTime(2026, 9, 11, 6, 10));
      expect(r.allowed, isTrue);
      expect(r.late, isTrue);
      expect(r.penalty, BizRules.morningLatePenalty);
      expect(r.penalty, 5);
      expect(r.warning!.toLowerCase(), contains('штраф'));
      expect(r.warning, contains('−5'));
    });

    test('предупреждение приходит ЗАРАНЕЕ, когда до дедлайна < 15 минут', () {
      final r = d(order: morningOrder, stage: OrderStageType.woke, at: DateTime(2026, 9, 11, 5, 50));
      expect(r.allowed, isTrue);
      expect(r.penalty, 0, reason: 'штрафа ещё нет');
      expect(r.warning, isNotNull, reason: 'но предупредить обязаны');
      expect(r.warning, contains('осталось'));
    });

    test('departed штрафует после своего дедлайна (30 мин до начала)', () {
      final early = d(
        order: morningOrder,
        stage: OrderStageType.departed,
        done: const [OrderStageType.woke],
        at: DateTime(2026, 9, 11, 6, 20),
      );
      expect(early.penalty, 0);

      final late = d(
        order: morningOrder,
        stage: OrderStageType.departed,
        done: const [OrderStageType.woke],
        at: DateTime(2026, 9, 11, 6, 35),
      );
      expect(late.penalty, 5);
      expect(late.late, isTrue);
    });

    test('woke на НЕутреннем заказе заблокирован', () {
      final r = d(order: dayOrder, stage: OrderStageType.woke);
      expect(r.allowed, isFalse);
      expect(r.blockReason, StageBlockReason.notMorningOrder);
      expect(r.blockedText, contains('утренних'));
    });

    test('на неутреннем заказе ожидаемый первый этап — departed, не woke', () {
      expect(
        OrderFlowMachine.nextExpected(const [], morning: false),
        OrderStageType.departed,
      );
      expect(
        OrderFlowMachine.nextExpected(const [], morning: true),
        OrderStageType.woke,
      );
    });

    test('провал утреннего дедлайна: −5 рейтинг, +1 fail, заказ в ленту', () {
      final f = OrderFlowMachine.morningFailure();
      expect(f.ratingDelta, -5);
      expect(f.failDelta, 1);
      expect(f.returnToFeed, isTrue);
    });
  });

  group('Роль старшего (lead)', () {
    test('started и finished доступны ТОЛЬКО старшему', () {
      const done = [OrderStageType.departed, OrderStageType.arrived];

      final asPorter = d(order: dayOrder, stage: OrderStageType.started, done: done, isLead: false);
      expect(asPorter.allowed, isFalse);
      expect(asPorter.blockReason, StageBlockReason.leadOnly);

      final asLead = d(order: dayOrder, stage: OrderStageType.started, done: done, isLead: true);
      expect(asLead.allowed, isTrue);
    });

    test('feedback тоже только у старшего', () {
      const done = [
        OrderStageType.departed,
        OrderStageType.arrived,
        OrderStageType.started,
        OrderStageType.finished,
      ];
      final finishedAt = now.subtract(const Duration(minutes: 1));

      expect(
        d(order: dayOrder, stage: OrderStageType.feedback, done: done, isLead: false, finishedAt: finishedAt)
            .blockReason,
        StageBlockReason.leadOnly,
      );
      expect(
        d(order: dayOrder, stage: OrderStageType.feedback, done: done, isLead: true, finishedAt: finishedAt)
            .allowed,
        isTrue,
      );
    });

    test('departed и arrived доступны обычному грузчику', () {
      expect(
        d(order: dayOrder, stage: OrderStageType.departed, isLead: false).allowed,
        isTrue,
      );
      expect(
        d(order: dayOrder, stage: OrderStageType.arrived, done: const [OrderStageType.departed], isLead: false)
            .allowed,
        isTrue,
      );
    });

    test('рейтинг за завершение: +1 всем, +2 старшему', () {
      expect(OrderFlowMachine.ratingForCompletion(isLead: false), 1);
      expect(OrderFlowMachine.ratingForCompletion(isLead: true), 2);
      expect(BizRules.ratingOnComplete, 1);
      expect(BizRules.ratingOnCompleteLead, 2);
    });
  });

  group('Порядок этапов', () {
    test('нельзя перепрыгнуть через arrived', () {
      final r = d(
        order: dayOrder,
        stage: OrderStageType.started,
        done: const [OrderStageType.departed],
        isLead: true,
      );
      expect(r.allowed, isFalse);
      expect(r.blockReason, StageBlockReason.wrongStageOrder);
    });

    test('нельзя нажать этап дважды', () {
      final r = d(
        order: dayOrder,
        stage: OrderStageType.arrived,
        done: const [OrderStageType.departed, OrderStageType.arrived],
      );
      expect(r.allowed, isFalse);
      expect(r.blockReason, StageBlockReason.alreadyDone);
    });

    test('после всех этапов ожидаемого нет', () {
      expect(
        OrderFlowMachine.nextExpected(OrderStageType.values.toList(), morning: true),
        isNull,
      );
    });

    test('порядок enum совпадает с порядком в боте', () {
      expect(OrderStageType.values, [
        OrderStageType.woke,
        OrderStageType.departed,
        OrderStageType.arrived,
        OrderStageType.started,
        OrderStageType.finished,
        OrderStageType.feedback,
      ]);
      expect(OrderStageType.woke.next, OrderStageType.departed);
      expect(OrderStageType.feedback.next, isNull);
    });
  });

  group('Обратная связь старшего: окно 5 минут', () {
    test('внутри окна — разрешено, снаружи — закрыто', () {
      const done = [
        OrderStageType.departed,
        OrderStageType.arrived,
        OrderStageType.started,
        OrderStageType.finished,
      ];

      final inWindow = d(
        order: dayOrder,
        stage: OrderStageType.feedback,
        done: done,
        isLead: true,
        finishedAt: now.subtract(const Duration(minutes: 4)),
      );
      expect(inWindow.allowed, isTrue);

      final outWindow = d(
        order: dayOrder,
        stage: OrderStageType.feedback,
        done: done,
        isLead: true,
        finishedAt: now.subtract(const Duration(minutes: 6)),
      );
      expect(outWindow.allowed, isFalse);
      expect(outWindow.blockReason, StageBlockReason.feedbackTimeoutExpired);
    });

    test('таймаут = 5 минут', () {
      expect(BizRules.feedbackTimeout, const Duration(minutes: 5));
      expect(BizRules.etaApprovalTimeout, const Duration(minutes: 15)); // Матвей 12.09
      expect(BizRules.leadTimeout, const Duration(minutes: 5));
    });
  });

  group('Статус заказа блокирует этапы', () {
    test('new (ещё не одобрен) — этапы недоступны', () {
      final o = buildOrder(timeStart: DateTime(2026, 9, 11, 14, 0), status: OrderStatus.new_);
      expect(
        d(order: o, stage: OrderStageType.departed).blockReason,
        StageBlockReason.orderNotApproved,
      );
    });

    test('completed / cancelled — этапы недоступны', () {
      for (final s in [OrderStatus.completed, OrderStatus.cancelled]) {
        final o = buildOrder(timeStart: DateTime(2026, 9, 11, 14, 0), status: s);
        expect(d(order: o, stage: OrderStageType.departed).allowed, isFalse);
        expect(d(order: o, stage: OrderStageType.departed).blockReason, StageBlockReason.orderNotLive);
        expect(s.isTerminal, isTrue);
      }
    });

    test('грузчик не из бригады не может жать этапы', () {
      final o = buildOrder(timeStart: DateTime(2026, 9, 11, 14, 0), status: OrderStatus.inProgress);
      expect(
        d(order: o, stage: OrderStageType.departed, inBrigade: false).blockReason,
        StageBlockReason.notInBrigade,
      );
    });
  });

  group('Расчёт часов (ceil(мин/30) × 0.5)', () {
    test('формула на одного', () {
      expect(BizRules.hoursFromMinutes(1), 0.5);
      expect(BizRules.hoursFromMinutes(30), 0.5);
      expect(BizRules.hoursFromMinutes(31), 1.0);
      expect(BizRules.hoursFromMinutes(60), 1.0);
      expect(BizRules.hoursFromMinutes(61), 1.5);
      expect(BizRules.hoursFromMinutes(100), 2.0);
      expect(BizRules.hoursFromMinutes(180), 3.0);
      expect(BizRules.hoursFromMinutes(0), 0.0);
      expect(BizRules.hoursFromMinutes(-10), 0.0);
    });

    test('«Сумма часов» = часы × кол-во человек', () {
      expect(BizRules.totalHours(100, 2), 4.0);
      expect(BizRules.totalHours(60, 4), 4.0);
      expect(BizRules.totalHours(31, 3), 3.0);
      // Защита от нуля/отрицательного числа людей.
      expect(BizRules.totalHours(60, 0), 1.0);
    });
  });

  group('Отклик и дедлайны срочности', () {
    test('срочный заказ: дедлайн отклика 1 час', () {
      expect(OrderUrgency.urgent.takeDeadline, const Duration(hours: 1));
      expect(OrderUrgency.replacement.takeDeadline, const Duration(hours: 1));
      expect(OrderUrgency.current.takeDeadline, const Duration(hours: 3));
      expect(OrderUrgency.preliminary.takeDeadline, isNull);
      expect(OrderUrgency.advance.takeDeadline, isNull);
    });

    test('canRespond: внутри дедлайна — да, снаружи — нет', () {
      final fresh = buildOrder(
        timeStart: DateTime(2026, 9, 11, 14, 0),
        status: OrderStatus.new_, // открыт для откликов
        urgency: OrderUrgency.urgent,
        createdAt: now.subtract(const Duration(minutes: 30)),
      );
      final stale = buildOrder(
        timeStart: DateTime(2026, 9, 11, 14, 0),
        status: OrderStatus.new_,
        urgency: OrderUrgency.urgent,
        createdAt: now.subtract(const Duration(minutes: 70)),
      );

      // Контрольный: уже взятый заказ — откликнуться нельзя regardless дедлайна.
      final taken = buildOrder(
        timeStart: DateTime(2026, 9, 11, 14, 0),
        status: OrderStatus.approved,
        urgency: OrderUrgency.urgent,
        createdAt: now.subtract(const Duration(minutes: 1)),
      );
      expect(OrderFlowMachine.canRespond(taken, now), isFalse);
      expect(OrderFlowMachine.canRespond(fresh, now), isTrue);
      expect(OrderFlowMachine.canRespond(stale, now), isFalse);
    });

    test('immediate-режим только у срочного и замены', () {
      expect(OrderUrgency.urgent.isImmediate, isTrue);
      expect(OrderUrgency.replacement.isImmediate, isTrue);
      expect(OrderUrgency.current.isImmediate, isFalse);
      expect(OrderUrgency.advance.isImmediate, isFalse);
    });

    test('интервалы воронки совпадают с ботом', () {
      expect(OrderUrgency.urgent.funnelStep, Duration.zero);
      expect(OrderUrgency.current.funnelStep, const Duration(minutes: 3));
      expect(OrderUrgency.preliminary.funnelStep, const Duration(minutes: 15));
      expect(OrderUrgency.advance.funnelStep, const Duration(minutes: 5));
      expect(OrderUrgency.preliminary.eveningOnly, isTrue);
      expect(OrderUrgency.urgent.eveningOnly, isFalse);
      expect(BizRules.eveningBroadcastHour, 18);
    });
  });

  group('Просрочка (план + 15 минут)', () {
    test('овертайм считается от времени начала', () {
      final o = buildOrder(
        timeStart: now.subtract(const Duration(minutes: 90)),
        plannedDurationMin: 60,
        status: OrderStatus.inProgress,
      );
      expect(o.overtimeAt, now.subtract(const Duration(minutes: 15)));
      expect(o.isOverdueAt(now), isTrue);
    });

    test('не просрочен, пока план + 15 не истекли', () {
      final o = buildOrder(
        timeStart: now.subtract(const Duration(minutes: 40)),
        plannedDurationMin: 60,
        status: OrderStatus.inProgress,
      );
      expect(o.isOverdueAt(now), isFalse);
    });

    test('закрытый заказ не считается просроченным', () {
      final o = buildOrder(
        timeStart: now.subtract(const Duration(days: 2)),
        plannedDurationMin: 60,
        status: OrderStatus.completed,
      );
      expect(o.isOverdueAt(now), isFalse);
    });

    test('грейс = 15 минут, повторное уведомление каждый час', () {
      expect(BizRules.overtimeGrace, const Duration(minutes: 15));
      expect(BizRules.overtimeNotifyEvery, const Duration(hours: 1));
    });
  });

  group('Снапшот потока для экрана order_active', () {
    test('собирает доступные этапы, овертайм и остаток на фидбек', () {
      final o = buildOrder(
        timeStart: DateTime(2026, 9, 11, 7, 0),
        status: OrderStatus.inProgress,
        plannedDurationMin: 180,
      );
      final stages = [
        OrderStage(orderId: o.id, porterId: 'me', stage: OrderStageType.woke, at: DateTime(2026, 9, 11, 5, 55)),
        OrderStage(orderId: o.id, porterId: 'me', stage: OrderStageType.departed, at: DateTime(2026, 9, 11, 6, 25)),
        OrderStage(orderId: o.id, porterId: 'me', stage: OrderStageType.arrived, at: DateTime(2026, 9, 11, 6, 55)),
        OrderStage(orderId: o.id, porterId: 'me', stage: OrderStageType.started, at: DateTime(2026, 9, 11, 7, 5)),
      ];

      final snap = OrderFlowMachine.snapshot(
        order: o,
        stages: stages,
        myPorterId: 'me',
        isLead: true,
        inBrigade: true,
        now: DateTime(2026, 9, 11, 8, 0),
      );

      expect(snap.doneStages, [
        OrderStageType.woke,
        OrderStageType.departed,
        OrderStageType.arrived,
        OrderStageType.started,
      ]);
      expect(snap.nextStage, OrderStageType.finished);
      expect(snap.canPress(OrderStageType.finished), isTrue);
      expect(snap.canPress(OrderStageType.arrived), isFalse);
      expect(snap.isLead, isTrue);
      expect(snap.overdue, isFalse, reason: 'план 180 мин, прошло 55 мин');
      expect(snap.feedbackRemaining, isNull, reason: 'ещё не закончили');
    });

    test('после finished тикает 5-минутное окно обратной связи', () {
      final o = buildOrder(
        timeStart: DateTime(2026, 9, 11, 7, 0),
        status: OrderStatus.inProgress,
      );
      final finishedAt = DateTime(2026, 9, 11, 9, 0);
      final stages = [
        OrderStage(orderId: o.id, porterId: 'me', stage: OrderStageType.departed, at: DateTime(2026, 9, 11, 6, 40)),
        OrderStage(orderId: o.id, porterId: 'me', stage: OrderStageType.arrived, at: DateTime(2026, 9, 11, 6, 58)),
        OrderStage(orderId: o.id, porterId: 'me', stage: OrderStageType.started, at: finishedAt),
        OrderStage(orderId: o.id, porterId: 'me', stage: OrderStageType.finished, at: finishedAt),
      ];

      final snap = OrderFlowMachine.snapshot(
        order: o,
        stages: stages,
        myPorterId: 'me',
        isLead: true,
        inBrigade: true,
        now: finishedAt.add(const Duration(minutes: 2)),
      );

      expect(snap.feedbackRemaining, const Duration(minutes: 3));
      expect(snap.canPress(OrderStageType.feedback), isTrue);
      expect(snap.nextStage, OrderStageType.feedback);

      final expired = OrderFlowMachine.snapshot(
        order: o,
        stages: stages,
        myPorterId: 'me',
        isLead: true,
        inBrigade: true,
        now: finishedAt.add(const Duration(minutes: 9)),
      );
      expect(expired.feedbackRemaining, Duration.zero);
      expect(expired.canPress(OrderStageType.feedback), isFalse);
    });
  });

  group('Парсинг wire-значений (защита от багов миграции)', () {
    test('статусы заказа из строк БД', () {
      expect(OrderStatus.fromWire('new'), OrderStatus.new_);
      expect(OrderStatus.fromWire('in_progress'), OrderStatus.inProgress);
      expect(OrderStatus.fromWire('cancelled'), OrderStatus.cancelled);
      expect(OrderStatus.fromWire('что-то неведомое'), OrderStatus.new_);
      expect(OrderStatus.inProgress.wire, 'in_progress');
      expect(OrderStatus.new_.wire, 'new');
    });

    test('срочность парсится из русских названий колонок таблицы', () {
      expect(OrderUrgency.fromWire('Срочно'), OrderUrgency.urgent);
      expect(OrderUrgency.fromWire('замена'), OrderUrgency.replacement);
      expect(OrderUrgency.fromWire('Текущий'), OrderUrgency.current);
      expect(OrderUrgency.fromWire('Предварительный'), OrderUrgency.preliminary);
      expect(OrderUrgency.fromWire('Предварительный Новый'), OrderUrgency.advance);
      expect(OrderUrgency.fromWire('Заранее'), OrderUrgency.advance);
    });

    test('🔴 wire-алиас: accepted из БД Матвея = approved', () {
      expect(OrderStatus.fromWire('accepted'), OrderStatus.approved);
      expect(OrderStatus.fromWire('approved'), OrderStatus.approved);
      expect(OrderStatus.approved.wire, 'accepted');
    });

    test('🔴 грабля №7: статусы рефералов сравниваются БЕЗ ё', () {
      expect(ReferralStatus.fromWire('ушел'), ReferralStatus.left);
      expect(ReferralStatus.fromWire('ушёл'), ReferralStatus.left);
      expect(ReferralStatus.fromWire('УШЕЛ'), ReferralStatus.left);
      expect(ReferralStatus.fromWire('засчитан'), ReferralStatus.counted);
      expect(ReferralStatus.fromWire('новый'), ReferralStatus.fresh);
      expect(BizRules.referralDaysToCount, 5);
    });
  });

  group('Ориентир «Номер подъ-да»', () {
    test('открывается только этапом started', () {
      expect(OrderStageType.started.unlocksEntrance, isTrue);
      expect(OrderStageType.arrived.unlocksEntrance, isFalse);
      expect(OrderStageType.departed.unlocksEntrance, isFalse);
    });

    test('модель допускает entrance == null (бэк скрывает его до started)', () {
      final hidden = Order(
        id: 'x',
        clientId: 'c',
        address: 'ул. Ленина, 1',
        timeStart: now,
        plannedDurationMin: 60,
        peopleCount: 2,
        status: OrderStatus.approved,
        urgency: OrderUrgency.current,
        taskTitle: 't',
        taskDescription: 'd',
      );
      expect(hidden.entrance, isNull,
          reason: 'Экран обязан корректно рисовать заказ БЕЗ ориентира');
    });
  });

  group('AppFailure: UI-решения по коду ошибки', () {
    test('«заказ занят» закрывает экран, а не показывает снакбар', () {
      expect(Failures.orderAlreadyTaken().isFatalForScreen, isTrue);
      expect(Failures.orderClosed().isFatalForScreen, isTrue);
      expect(Failures.offline().isFatalForScreen, isFalse);
      expect(Failures.server().isFatalForScreen, isFalse);
    });

    test('кнопка «Повторить» — только там, где она имеет смысл', () {
      expect(Failures.offline().showRetry, isTrue);
      expect(Failures.timeout().showRetry, isTrue);
      expect(Failures.server().showRetry, isTrue);
      expect(Failures.orderAlreadyTaken().showRetry, isFalse);
      expect(Failures.leadOnly().showRetry, isFalse);
    });

    test('все тексты ошибок уже на русском и непустые', () {
      for (final f in [
        Failures.offline(),
        Failures.timeout(),
        Failures.server(),
        Failures.orderAlreadyTaken(),
        Failures.orderClosed(),
        Failures.leadOnly(),
        Failures.wrongStageOrder(),
        Failures.responseExpired(),
        Failures.feedbackWindowClosed(),
        Failures.unauthorized(),
        Failures.validation('eta', 'Проверьте значение'),
      ]) {
        expect(f.message.trim(), isNotEmpty);
        expect(f.message, isNot(contains('Exception')));
      }
    });

    test('каждый StageBlockReason имеет человекочитаемый текст', () {
      for (final r in StageBlockReason.values) {
        expect(r.describe().trim(), isNotEmpty);
        expect(r.describe(), isNot(r.name));
      }
    });
  });

  group('РЕГРЕССИЯ: этапы считаются по конкретному грузчику', () {
    test('чужой «Выехал» НЕ разблокирует мне «На месте»', () {
      final o = buildOrder(
        timeStart: DateTime(2026, 9, 11, 14, 0),
        status: OrderStatus.inProgress,
      );

      final snap = OrderFlowMachine.snapshot(
        order: o,
        stages: [
          OrderStage(
            orderId: 'o1',
            porterId: 'ivan', // уехал Иван, а не я
            stage: OrderStageType.departed,
            at: DateTime(2026, 9, 11, 13, 20),
          ),
        ],
        myPorterId: 'me',
        isLead: false,
        inBrigade: true,
        now: DateTime(2026, 9, 11, 13, 40),
      );

      expect(snap.doneStages, isEmpty, reason: 'у меня ещё нет ни одного этапа');
      expect(snap.nextStage, OrderStageType.departed,
          reason: 'я обязан нажать «Выехал» сам, а не унаследовать от Ивана');
      expect(snap.canPress(OrderStageType.arrived), isFalse);
      expect(snap.canPress(OrderStageType.departed), isTrue);
    });
  });

  group('РЕГРЕССИЯ: пропущенный woke не блокирует остальной поток', () {
    test('грузчик проспал «Проснулся», но «Выехал»/«Начали» доступны', () {
      // Сценарий из жизни: утренний заказ, woke пропущен → штраф −5, заказ
      // вернулся в ленту, его взяли заново. Если искать «первый несделанный»
      // этап, поток залипнет на woke навсегда.
      final o = buildOrder(
        timeStart: DateTime(2026, 9, 11, 7, 0),
        status: OrderStatus.inProgress,
      );

      expect(
        OrderFlowMachine.nextExpected(
          const [OrderStageType.departed, OrderStageType.arrived],
          morning: true,
        ),
        OrderStageType.started,
        reason: 'считаем от самого позднего сделанного, а не от первого пропуска',
      );

      final snap = OrderFlowMachine.snapshot(
        order: o,
        stages: [
          OrderStage(
            orderId: 'o1',
            porterId: 'me',
            stage: OrderStageType.departed,
            at: DateTime(2026, 9, 11, 6, 40),
            late: true,
          ),
          OrderStage(
            orderId: 'o1',
            porterId: 'me',
            stage: OrderStageType.arrived,
            at: DateTime(2026, 9, 11, 6, 58),
          ),
        ],
        myPorterId: 'me',
        isLead: true,
        inBrigade: true,
        now: DateTime(2026, 9, 11, 7, 1),
      );

      expect(snap.canPress(OrderStageType.started), isTrue);
      expect(snap.canPress(OrderStageType.woke), isFalse,
          reason: 'поезд ушёл: woke задним числом не нажимается');
    });
  });
}
