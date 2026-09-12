/// СТАТУС-МАШИНА ПОТОКА ЗАКАЗА — чистые функции, без Flutter и без сети.
///
/// Зона: Артём. Это единственное место, где живут правила этапов.
/// Экраны НЕ вычисляют правила сами — они спрашивают здесь (или у бэка).
///
/// ⚠️ Разделение ответственности:
///   - КЛИЕНТ использует эти функции только для UX (скрыть/задизейблить кнопку,
///     показать предупреждение о штрафе ДО нажатия).
///   - СЕРВЕР (Матвей) проверяет то же самое и является источником истины.
///   Если правила разъехались — баг лечится здесь и в `getStageAvailability` у Матвея,
///   а не добавлением проверки в виджет.
library;

import 'enums.dart';
import 'models.dart';

/// Почему этап недоступен. Тексты — для тултипа/снакбара, уже на русском.
enum StageBlockReason {
  orderNotApproved,
  orderNotLive,
  wrongStageOrder,
  leadOnly,
  notMorningOrder,
  notInBrigade,
  alreadyDone,
  feedbackTimeoutExpired,
  unknown;

  String describe() => switch (this) {
        StageBlockReason.orderNotApproved => 'Заказ ещё не одобрен диспетчером',
        StageBlockReason.orderNotLive => 'Заказ закрыт — этапы недоступны',
        StageBlockReason.wrongStageOrder => 'Сначала завершите предыдущий этап',
        StageBlockReason.leadOnly => 'Этот этап нажимает только старший бригады',
        StageBlockReason.notMorningOrder => 'Этап «Проснулся» только для утренних заказов',
        StageBlockReason.notInBrigade => 'Вы не в бригаде этого заказа',
        StageBlockReason.alreadyDone => 'Этап уже отмечен',
        StageBlockReason.feedbackTimeoutExpired =>
          'Окно обратной связи закрылось (5 минут)',
        StageBlockReason.unknown => 'Действие сейчас недоступно',
      };
}

/// Решение по одному этапу: можно ли жать и что будет.
class StageDecision {
  const StageDecision({
    required this.stage,
    required this.allowed,
    this.blockReason,
    this.late = false,
    this.penalty = 0,
    this.deadline,
    this.warning,
  });

  final OrderStageType stage;
  final bool allowed;
  final StageBlockReason? blockReason;

  /// Дедлайн уже пропущен (для утренних этапов).
  final bool late;

  /// Штраф к рейтингу, если нажать сейчас.
  final int penalty;

  final DateTime? deadline;

  /// Готовый текст предупреждения для ConfirmSheet.
  final String? warning;

  String get blockedText => blockReason?.describe() ?? '';

  static StageDecision allow(OrderStageType s) =>
      StageDecision(stage: s, allowed: true);

  static StageDecision block(OrderStageType s, StageBlockReason r) =>
      StageDecision(stage: s, allowed: false, blockReason: r);
}

/// Полная картина по заказу для текущего пользователя.
class FlowSnapshot {
  const FlowSnapshot({
    required this.order,
    required this.decisions,
    required this.isLead,
    required this.inBrigade,
    required this.doneStages,
    this.overdue = false,
    this.feedbackRemaining,
  });

  final Order order;
  final Map<OrderStageType, StageDecision> decisions;
  final bool isLead;
  final bool inBrigade;

  /// Уже проставленные этапы (в порядке фиксации).
  final List<OrderStageType> doneStages;

  /// План + 15 минут прошло, а заказ не закрыт.
  final bool overdue;

  /// Сколько осталось на обратную связь старшего.
  final Duration? feedbackRemaining;

  StageDecision of(OrderStageType s) =>
      decisions[s] ?? StageDecision.block(s, StageBlockReason.unknown);

  bool canPress(OrderStageType s) => of(s).allowed;

  /// Следующий этап, который нужно нажать (для подсветки в таймлайне).
  OrderStageType? get nextStage => OrderFlowMachine.nextExpected(
        doneStages,
        morning: order.isMorning,
      );
}

abstract final class OrderFlowMachine {
  /// Какая стадия сейчас «следующая ожидаемая» по списку уже сделанных.
  ///
  /// Логика «от самого позднего сделанного», а не «первый несделанный».
  /// Иначе пропущенный `woke` (грузчик проспал, получил штраф, заказ вернулся
  /// в ленту, потом его снова взяли) навсегда заблокировал бы `departed`.
  ///
  /// [morning] = false для НЕутренних заказов: этап `woke` у них не существует
  /// вовсе, поэтому через него перешагиваем, а не блокируемся.
  static OrderStageType? nextExpected(
    List<OrderStageType> done, {
    bool morning = true,
  }) {
    var highest = -1;
    for (final s in done) {
      if (s.order > highest) highest = s.order;
    }
    for (final s in OrderStageType.values) {
      if (s.order <= highest) continue;
      if (s.morningOnly && !morning) continue;
      return s;
    }
    return null; // всё сделано
  }

  /// Утренние дедлайны: «Проснулся» за 1 час, «Выехал» за 30 минут.
  /// Возвращает null, если заказ не утренний или у этапа нет дедлайна.
  static DateTime? deadlineFor(OrderStageType stage, Order order) =>
      switch (stage) {
        OrderStageType.woke => order.wokeDeadline,
        OrderStageType.departed => order.departedDeadline,
        _ => null,
      };

  /// Штраф за нажатие этапа сейчас (−5 за пропущенный утренний дедлайн).
  static int penaltyFor(OrderStageType stage, Order order, DateTime now) {
    final dl = deadlineFor(stage, order);
    if (dl == null) return 0;
    return now.isAfter(dl) ? BizRules.morningLatePenalty : 0;
  }

  /// Готовый текст предупреждения ПЕРЕД нажатием.
  /// Требование из бота: грузчик должен знать о штрафе до действия.
  static String? warningFor(OrderStageType stage, Order order, DateTime now) {
    final dl = deadlineFor(stage, order);
    if (dl == null) return null;

    final diff = dl.difference(now);
    final label = stage == OrderStageType.woke ? '«Проснулся»' : '«Выехал»';

    if (diff.isNegative) {
      final late = -diff;
      return 'Дедлайн $label пропущен ${_humanize(late)}. '
          'Штраф −${BizRules.morningLatePenalty} к рейтингу и +1 к счётчику провалов. '
          'Заказ может вернуться в ленту.';
    }

    if (diff <= const Duration(minutes: 15)) {
      return 'До дедлайна $label осталось ${_humanize(diff)}. '
          'Если не успеете — штраф −${BizRules.morningLatePenalty}.';
    }

    return null;
  }

  /// Главная проверка: можно ли пользователю нажать этап.
  static StageDecision decide({
    required OrderStageType stage,
    required Order order,
    required List<OrderStageType> done,
    required bool isLead,
    required bool inBrigade,
    required DateTime now,
    DateTime? finishedAt,
  }) {
    if (order.status == OrderStatus.new_) {
      return StageDecision.block(stage, StageBlockReason.orderNotApproved);
    }
    // isLive == !isTerminal, поэтому сначала ловим new_, потом terminal —
    // иначе cancelled/completed проваливался бы в orderNotApproved и UI показал бы
    // «заказ ещё не одобрен» вместо «заказ закрыт».
    if (!order.status.isLive) {
      return StageDecision.block(stage, StageBlockReason.orderNotLive);
    }
    if (!inBrigade) {
      return StageDecision.block(stage, StageBlockReason.notInBrigade);
    }
    if (done.contains(stage)) {
      return StageDecision.block(stage, StageBlockReason.alreadyDone);
    }

    // «Проснулся» существует только для утренних заказов (4:00–12:00).
    if (stage.morningOnly && !order.isMorning) {
      return StageDecision.block(stage, StageBlockReason.notMorningOrder);
    }

    // started / finished / feedback — только старший.
    if (stage.leadOnly && !isLead) {
      return StageDecision.block(stage, StageBlockReason.leadOnly);
    }

    // Обратная связь — окно 5 минут после «Закончили».
    if (stage == OrderStageType.feedback && finishedAt != null) {
      final deadline = finishedAt.add(BizRules.feedbackTimeout);
      if (now.isAfter(deadline)) {
        return StageDecision.block(stage, StageBlockReason.feedbackTimeoutExpired);
      }
    }

    // Порядок этапов: жать можно только следующий ожидаемый.
    final expected = nextExpected(done, morning: order.isMorning);
    if (expected == null) {
      return StageDecision.block(stage, StageBlockReason.alreadyDone);
    }
    if (stage != expected) {
      return StageDecision.block(stage, StageBlockReason.wrongStageOrder);
    }

    final penalty = penaltyFor(stage, order, now);
    final dl = deadlineFor(stage, order);
    final warn = warningFor(stage, order, now);

    return StageDecision(
      stage: stage,
      allowed: true,
      late: penalty > 0,
      penalty: penalty,
      deadline: dl,
      warning: warn,
    );
  }

  /// Собрать полную картину для экрана `order_active`.
  ///
  /// 🔴 [myPorterId] обязателен: этапы в БД хранятся ПО ГРУЗЧИКАМ
  /// (`OrderStages(order_id, porter_id, stage, timestamp)`). Если не фильтровать,
  /// чужой «Выехал» засчитается мне и я увижу разблокированную кнопку «На месте»,
  /// хотя сам ещё не выехал. Это ровно тот баг, который на проде выглядит как
  /// «грузчик нажал этап, которого не проходил».
  static FlowSnapshot snapshot({
    required Order order,
    required List<OrderStage> stages,
    required String myPorterId,
    required bool isLead,
    required bool inBrigade,
    required DateTime now,
  }) {
    // Мои этапы.
    final mine = stages.where((s) => s.porterId == myPorterId).toList();
    final done = mine.map((s) => s.stage).toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    // `finished` жмёт только старший, но окно обратной связи общее для заказа —
    // поэтому смотрим finished по всем, а не только по себе.
    DateTime? finishedAt;
    for (final s in stages) {
      if (s.stage == OrderStageType.finished) {
        if (finishedAt == null || s.at.isAfter(finishedAt)) finishedAt = s.at;
      }
    }

    final decisions = <OrderStageType, StageDecision>{};
    for (final s in OrderStageType.values) {
      decisions[s] = decide(
        stage: s,
        order: order,
        done: done,
        isLead: isLead,
        inBrigade: inBrigade,
        now: now,
        finishedAt: finishedAt,
      );
    }

    Duration? feedbackRemaining;
    if (finishedAt != null && !done.contains(OrderStageType.feedback)) {
      final deadline = finishedAt.add(BizRules.feedbackTimeout);
      feedbackRemaining = deadline.difference(now);
      if (feedbackRemaining.isNegative) feedbackRemaining = Duration.zero;
    }

    return FlowSnapshot(
      order: order,
      decisions: decisions,
      isLead: isLead,
      inBrigade: inBrigade,
      doneStages: done,
      overdue: order.isOverdueAt(now),
      feedbackRemaining: feedbackRemaining,
    );
  }

  /// Можно ли откликнуться на заказ.
  static bool canRespond(Order order, DateTime now) {
    if (!order.isOpenForResponse) return false;
    final dl = order.urgency.takeDeadline;
    if (dl == null) return true;
    // Дедлайн считается от создания заказа; если createdAt нет — не блокируем.
    final created = order.createdAt;
    if (created == null) return true;
    return now.isBefore(created.add(dl));
  }

  /// 🔴 Матвей 12.09: срочный заказ, у которого `departed` не нажат дольше
  /// [BizRules.urgentDepartedCancelGrace] после начала работ, бэкенд отменяет
  /// (событие order_cancelled, reason deadline).
  /// ⚠️ OPEN QUESTION: для несрочных и для «departed до начала» дедлайнов у Матвея
  /// правило не прописано — уточнить в следующем пинге. Здесь: immediate-заказы,
  /// точка отсчёта — время начала работ.
  static bool urgentDepartedMissCancels(Order order, DateTime now) {
    if (!order.urgency.isImmediate) return false;
    final deadline = order.timeStart.add(BizRules.urgentDepartedCancelGrace);
    return now.isAfter(deadline);
  }

  /// Рейтинг за завершение: +2 старшему, +1 остальным.
  static int ratingForCompletion({required bool isLead}) =>
      isLead ? BizRules.ratingOnCompleteLead : BizRules.ratingOnComplete;

  /// Итог штрафа за утренний провал: рейтинг −5, fail +1, заказ в ленту.
  static ({int ratingDelta, int failDelta, bool returnToFeed}) morningFailure() => (
        ratingDelta: -BizRules.morningLatePenalty,
        failDelta: 1,
        returnToFeed: true,
      );

  static String _humanize(Duration d) {
    final m = d.inMinutes;
    if (m < 1) return 'меньше минуты';
    if (m < 60) return '$m мин';
    final h = d.inHours;
    final rest = m % 60;
    return rest == 0 ? '$h ч' : '$h ч $rest мин';
  }
}
