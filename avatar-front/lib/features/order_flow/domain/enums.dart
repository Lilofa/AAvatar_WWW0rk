/// ЕДИНЫЙ СЛОВАРЬ СУЩНОСТЕЙ ПОТОКА ЗАКАЗА.
///
/// Зона: Артём (сквозной поток заказа).
/// Статус: ЧЕРНОВИК-КОНТРАКТ. Финальное слово по схеме — за Матвеем.
/// Любое расхождение с БД исправляется ЗДЕСЬ, а не по экранам.
///
/// ВАЖНО (грабля №7 из брифа): в боте norm() заменял ё→е, поэтому литералы
/// статусов были 'ушел', 'отменен'. В приложении мы НЕ наследуем этот баг:
/// здесь хранятся машинные enum-значения в snake_case без ё,
/// а человекочитаемые подписи — отдельно, в `labels.dart` (там ё на месте).
library;

// ─────────────────────────────────────────────────────────────
// РОЛИ
// ─────────────────────────────────────────────────────────────

enum UserRole {
  porter, // грузчик
  client, // заказчик
  dispatcher, // диспетчер
  admin; // админ (владелец бизнеса)

  static UserRole fromWire(String raw) => UserRole.values.firstWhere(
        (r) => r.name == raw,
        orElse: () => UserRole.porter,
      );
}

/// Вопрос Матвею: роли — одна или массив?
/// Артём (374545233) и грузчик, и диспетчер. Держим список до решения.
typedef UserRoles = Set<UserRole>;

// ─────────────────────────────────────────────────────────────
// СТАТУС ЗАКАЗА  (БД)
// ─────────────────────────────────────────────────────────────

/// new → approved → in_progress → completed, плюс cancelled.
/// Соответствие статусам бота («Статус бота» в Google Sheets):
///   новый        → new
///   в воронке    → new   (⚠ см. вопрос про воронку в CONTRACT_methods.md)
///   взят         → approved / in_progress
///   выполнен     → completed
///   не взят      → cancelled
///   отменен      → cancelled
///   закрыт       → completed (принудительно) — нужен флаг forceClosed
enum OrderStatus {
  new_, // `new` — зарезервированное слово в Dart
  approved,
  inProgress, // in_progress
  completed,
  cancelled;

  String get wire => switch (this) {
        OrderStatus.new_ => 'new',
        OrderStatus.approved => 'accepted', // 🔴 имя в БД Матвея — accepted
        OrderStatus.inProgress => 'in_progress',
        OrderStatus.completed => 'completed',
        OrderStatus.cancelled => 'cancelled',
      };

  static OrderStatus fromWire(String raw) {
    final v = raw.trim();
    if (v == 'accepted') return OrderStatus.approved; // 🔴 алиас: в БД Матвея accepted
    return OrderStatus.values.firstWhere(
      (s) => s.wire == v || s.name == v,
      orElse: () => OrderStatus.new_,
    );
  }

  bool get isTerminal =>
      this == OrderStatus.completed || this == OrderStatus.cancelled;

  bool get isLive => !isTerminal;
}

// ─────────────────────────────────────────────────────────────
// СРОЧНОСТЬ  («Тип заказа (срочность)» в таблице)
// ─────────────────────────────────────────────────────────────

/// Влияет на: интервалы воронки, дедлайн отклика, цвет плашки, сортировку ленты.
enum OrderUrgency {
  /// «Срочно» — immediate, все чаты сразу, дедлайн 1 час.
  urgent,

  /// «Замена» — immediate, как срочный, но ищем замену выбывшему.
  replacement,

  /// «Текущий» — normal, интервал 3 мин, дедлайн 3 часа.
  current,

  /// «Предварительный» — evening, рассылка только после 18:00, интервал 15 мин.
  preliminary,

  /// «Предварительный Новый» / «Заранее» — fast, интервал 5 мин.
  advance;

  /// immediate-режим: рассылка сразу во все чаты.
  bool get isImmediate => this == urgent || this == replacement;

  /// Дедлайн взятия заказа (из логики бота).
  Duration? get takeDeadline => switch (this) {
        OrderUrgency.urgent => const Duration(hours: 1),
        OrderUrgency.replacement => const Duration(hours: 1),
        OrderUrgency.current => const Duration(hours: 3),
        OrderUrgency.preliminary => null,
        OrderUrgency.advance => null,
      };

  /// Интервал между чатами воронки.
  Duration get funnelStep => switch (this) {
        OrderUrgency.urgent => Duration.zero,
        OrderUrgency.replacement => Duration.zero,
        OrderUrgency.current => const Duration(minutes: 3),
        OrderUrgency.preliminary => const Duration(minutes: 15),
        OrderUrgency.advance => const Duration(minutes: 5),
      };

  /// Предварительные заказы не рассылаются до 18:00.
  bool get eveningOnly => this == preliminary;

  static OrderUrgency fromWire(String raw) {
    final n = raw.trim().toLowerCase();
    // Без ё — по той же причине, что и в боте: нормализация ввода.
    if (n.contains('замен')) return OrderUrgency.replacement;
    if (n.startsWith('сроч')) return OrderUrgency.urgent;
    if (n.contains('заранее')) return OrderUrgency.advance;
    if (n.contains('новый')) return OrderUrgency.advance;
    if (n.startsWith('предвар')) return OrderUrgency.preliminary;
    if (n.startsWith('текущ')) return OrderUrgency.current;
    return OrderUrgency.current;
  }
}

// ─────────────────────────────────────────────────────────────
// ЭТАПЫ РАБОТ
// ─────────────────────────────────────────────────────────────

/// Порядок жёсткий: woke → departed → arrived → started → finished → feedback.
enum OrderStageType {
  woke, // «Проснулся» — ТОЛЬКО утренние заказы (начало 4:00–12:00)
  departed, // «Выехал»
  arrived, // «На месте»
  started, // «Начали» — ТОЛЬКО старший
  finished, // «Закончили» — ТОЛЬКО старший
  feedback; // Обратная связь старшего: Да/Нет + комментарий

  int get order => index;

  OrderStageType? get next =>
      index + 1 < OrderStageType.values.length ? values[index + 1] : null;

  /// Этап, который имеет право нажать только старший бригады.
  bool get leadOnly => this == started || this == finished || this == feedback;

  /// Этап существует только для утренних заказов.
  bool get morningOnly => this == woke;

  /// После этого этапа старшему открывается ориентир («Номер подъ-да»).
  bool get unlocksEntrance => this == started;

  static OrderStageType fromWire(String raw) =>
      OrderStageType.values.firstWhere(
        (s) => s.name == raw,
        orElse: () => OrderStageType.arrived,
      );
}

// ─────────────────────────────────────────────────────────────
// ОТКЛИК (ETA)
// ─────────────────────────────────────────────────────────────

enum ResponseStatus {
  pending, // ждёт диспетчера (5 минут, иначе автоотклонение)
  approved,
  declined,
  expired; // автоотклонение по таймауту — отдельный статус для UI

  bool get isFinal => this != ResponseStatus.pending;
}

// ─────────────────────────────────────────────────────────────
// РЕФЕРАЛЫ (v2, но статусы нужны уже в модели)
// ─────────────────────────────────────────────────────────────

enum ReferralStatus {
  fresh, // «новый»
  counted, // «засчитан» — пробыл в чате 5+ дней
  left; // «ушёл» — вышел/кикнут раньше

  static ReferralStatus fromWire(String raw) {
    final n = raw.trim().toLowerCase();
    if (n.startsWith('засчит')) return ReferralStatus.counted;
    // Без ё! В боте этот баг уже был: 'ушёл' != 'ушел'.
    if (n.startsWith('уш') || n.startsWith('ушел')) return ReferralStatus.left;
    return ReferralStatus.fresh;
  }
}

// ─────────────────────────────────────────────────────────────
// ТРАНЗАКЦИИ
// ─────────────────────────────────────────────────────────────

enum TransactionType {
  earning, // начисление за заказ
  bonus, // бонус (рефералка и т.п.)
  penalty, // штраф (−5 рейтинг и т.п.)
  payout; // выплата
}

// ─────────────────────────────────────────────────────────────
// КОНСТАНТЫ БИЗНЕС-ПРАВИЛ (единый источник, не разносить по экранам!)
// ─────────────────────────────────────────────────────────────

abstract final class BizRules {
  // ── Утренние заказы ────────────────────────────────────────
  /// Заказ считается утренним, если начало работ в этом окне.
  static const int morningStartHour = 4;
  static const int morningEndHour = 12;

  /// «Проснулся» — за 1 час до начала.
  static const Duration wokeLeadTime = Duration(hours: 1);

  /// «Выехал» — за 30 минут до начала.
  static const Duration departedLeadTime = Duration(minutes: 30);

  /// Штраф за пропуск утреннего дедлайна.
  static const int morningLatePenalty = 5;

  // ── Таймауты ───────────────────────────────────────────────
  /// Диспетчер одобряет/отклоняет ETA. 🔴 Матвей 12.09: 15 минут (в боте было 5).
  static const Duration etaApprovalTimeout = Duration(minutes: 15);

  /// Срочный заказ: пропуск `departed` дольше этого срока → cancelled.
  static const Duration urgentDepartedCancelGrace = Duration(minutes: 15);

  /// Диспетчер выбирает старшего, если бригада из разных чатов.
  static const Duration leadTimeout = Duration(minutes: 5);

  /// Обратная связь старшего после «Закончили».
  static const Duration feedbackTimeout = Duration(minutes: 5);

  // ── Овертайм ───────────────────────────────────────────────
  /// Плановая длительность + 15 минут → сигнал диспетчеру.
  static const Duration overtimeGrace = Duration(minutes: 15);

  /// Повторное уведомление диспетчеру — каждый час.
  static const Duration overtimeNotifyEvery = Duration(hours: 1);

  // ── Рейтинг ────────────────────────────────────────────────
  static const int ratingOnComplete = 1; // всем
  static const int ratingOnCompleteLead = 2; // старшему

  // ── Часы ───────────────────────────────────────────────────
  /// ceil(минуты / 30) × 0.5, затем × кол-во человек.
  static const int hoursStepMinutes = 30;
  static const double hoursStepValue = 0.5;

  // ── Рефералка ──────────────────────────────────────────────
  static const int referralDaysToCount = 5;

  // ── Вечерняя рассылка ──────────────────────────────────────
  static const int eveningBroadcastHour = 18;

  // ── Лимиты VK (на случай параллельной работы с ботами) ─────
  static const int vkMessageLimit = 4096;
  static const int vkMessageTruncateAt = 3900;

  /// Минут → «Кол-во Часов» на одного.
  static double hoursFromMinutes(int minutes) {
    if (minutes <= 0) return 0;
    final steps = (minutes / hoursStepMinutes).ceil();
    return steps * hoursStepValue;
  }

  /// «Кол-во Часов» × людей = «Сумма часов».
  static double totalHours(int minutes, int peopleCount) =>
      hoursFromMinutes(minutes) * (peopleCount < 1 ? 1 : peopleCount);

  /// Является ли заказ утренним (по локальному часу начала, Asia/Novosibirsk).
  static bool isMorningOrder(DateTime timeStartLocal) =>
      timeStartLocal.hour >= morningStartHour &&
      timeStartLocal.hour < morningEndHour;

  /// Дедлайн «Проснулся» (локальное время). null, если заказ не утренний.
  static DateTime? wokeDeadline(DateTime timeStartLocal) => isMorningOrder(timeStartLocal)
      ? timeStartLocal.subtract(wokeLeadTime)
      : null;

  /// Дедлайн «Выехал» (локальное время). null, если заказ не утренний.
  static DateTime? departedDeadline(DateTime timeStartLocal) =>
      isMorningOrder(timeStartLocal)
          ? timeStartLocal.subtract(departedLeadTime)
          : null;

  /// Момент, после которого заказ считается просроченным.
  static DateTime overtimeAt(DateTime timeStartLocal, int plannedDurationMin) =>
      timeStartLocal
          .add(Duration(minutes: plannedDurationMin))
          .add(overtimeGrace);
}

// ─────────────────────────────────────────────────────────────
// ТРАНСПОРТ (решение Матвея 12.09: тариф зависит от типа транспорта)
// ─────────────────────────────────────────────────────────────

enum TransportType {
  none,
  gazelle,
  truck;

  String get wire => name;

  static TransportType fromWire(String? raw) => switch (raw) {
        'gazelle' => TransportType.gazelle,
        'truck' => TransportType.truck,
        _ => TransportType.none,
      };

  /// transport_fee из RPC quote_order.
  int get feeRub => switch (this) {
        TransportType.none => 0,
        TransportType.gazelle => 1500,
        TransportType.truck => 3000,
      };
}

/// urgency_multiplier из RPC quote_order.
/// ⚠️ OPEN QUESTION Матвею: replacement в его таблице нет; считаем как urgent (1.5),
/// т.к. замена тоже immediate. Пометить в следующем пинге.
double urgencyMultiplier(OrderUrgency u) => switch (u) {
      OrderUrgency.urgent => 1.5,
      OrderUrgency.replacement => 1.5,
      OrderUrgency.current => 1.0,
      OrderUrgency.preliminary => 0.9,
      OrderUrgency.advance => 0.8,
    };

// ─────────────────────────────────────────────────────────────
// REALTIME-СОБЫТИЯ (финальные каналы Матвея, блок 10)
// ─────────────────────────────────────────────────────────────

enum OrderEvent {
  statusChanged('status_changed'),
  stageAdded('stage_added'),
  leadAssigned('lead_assigned'),
  stageDeadlineMissed('stage_deadline_missed'),
  orderCancelled('order_cancelled'),
  feedbackTimeout('feedback_timeout'),
  forceClosed('force_closed');

  const OrderEvent(this.wire);
  final String wire;

  static OrderEvent? fromWire(String raw) =>
      OrderEvent.values.firstWhere((e) => e.wire == raw, orElse: () => statusChanged);
}

enum FeedEvent {
  orderCreated('order_created'),
  orderTaken('order_taken'),
  orderCancelled('order_cancelled'),
  replacementNeeded('replacement_needed');

  const FeedEvent(this.wire);
  final String wire;
}
