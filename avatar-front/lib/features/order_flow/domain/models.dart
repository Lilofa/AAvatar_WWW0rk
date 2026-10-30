/// МОДЕЛИ ПОТОКА ЗАКАЗА (read-модели для UI).
///
/// Зона: Артём. Статус: ЧЕРНОВИК-КОНТРАКТ, финал — за Матвеем.
///
/// Принцип: UI-модель НЕ равна строке БД. Здесь только то, что нужно экранам,
/// и всё уже нормализовано (время локальное, деньги в double, статусы в enum).
/// Маппинг из DTO — в `data/mappers/` у Матвея.
library;

import 'enums.dart';

/// Краткая карточка человека (бригада, старший, автор отзыва).
class PorterBrief {
  const PorterBrief({
    required this.id,
    required this.name,
    this.rating = 0,
    this.completedCount = 0,
    this.failCount = 0,
    this.avatarUrl,
    this.isLead = false,
  });

  final String id;
  final String name;
  final int rating;
  final int completedCount;
  final int failCount;
  final String? avatarUrl;
  final bool isLead;

  PorterBrief copyWith({bool? isLead, int? rating}) => PorterBrief(
        id: id,
        name: name,
        rating: rating ?? this.rating,
        completedCount: completedCount,
        failCount: failCount,
        avatarUrl: avatarUrl,
        isLead: isLead ?? this.isLead,
      );
}

/// Заказ — то, что видит грузчик в ленте и на активном заказе.
class Order {
  const Order({
    required this.id,
    required this.clientId,
    required this.address,
    required this.timeStart,
    required this.plannedDurationMin,
    required this.peopleCount,
    required this.status,
    required this.urgency,
    required this.taskTitle,
    required this.taskDescription,
    this.entrance,
    this.transport = TransportType.none,
    this.clientPhone,
    this.extraComments,
    this.clientTariffHint,
    this.porterTariffHint,
    this.resultComment,
    this.coords,
    this.createdAt,
    this.myResponseStatus,
    this.feedbackMissed = false,
    this.forceClosed = false,
    this.isReplacement = false,
    this.clientIsMe = false,
  });

  final String id;
  final String clientId;
  final String address;

  /// Локальное время (Asia/Novosibirsk). На проводе — UTC, конвертит mapper.
  final DateTime timeStart;
  final int plannedDurationMin;
  final int peopleCount;
  final OrderStatus status;
  final OrderUrgency urgency;

  /// «Наименование» и «Что делать» из таблицы.
  final String taskTitle;
  final String taskDescription;

  /// 🔴 «Номер подъ-да» — ОРИЕНТИР. Грузчикам НЕ отдаётся до этапа `started`.
  /// Скрывается на бэке (RLS), здесь поле просто null. Не скрывать на клиенте!
  final String? entrance;

  final TransportType transport;
  final String? clientPhone;
  final String? extraComments;

  /// «Подсказка Клиент Тариф» / «Подсказка Грузчик Тариф».
  final String? clientTariffHint;
  final String? porterTariffHint;

  /// «КОМЕНТАРИИ, Результат заявки» — обратная связь старшего.
  final String? resultComment;

  final GeoPoint? coords;
  final DateTime? createdAt;

  /// Мой отклик на этот заказ в ленте (Матвей, блок 2): null/pending/approved/declined.
  final ResponseStatus? myResponseStatus;

  /// Обратная связь старшего не сдана в срок (feedback_timeout).
  final bool feedbackMissed;

  /// Заказ закрыт принудительно диспетчером.
  final bool forceClosed;
  final bool isReplacement;

  /// Я — заказчик этого заказа (нельзя откликаться на свою заявку).
  final bool clientIsMe;

  bool get isMorning => BizRules.isMorningOrder(timeStart);

  bool get isUrgentNow => urgency.isImmediate;

  /// Просрочен: плановая длительность + 15 минут.
  bool isOverdueAt(DateTime now) =>
      status == OrderStatus.inProgress &&
      now.isAfter(BizRules.overtimeAt(timeStart, plannedDurationMin));

  DateTime get overtimeAt => BizRules.overtimeAt(timeStart, plannedDurationMin);

  /// 🔴 SQL Матвея: дедлайны считаются для ВСЕХ заказов (time_start − 1 ч / − 30 мин);
  /// утренность ограничивает только доступность этапа woke.
  DateTime? get wokeDeadline => timeStart.subtract(BizRules.wokeLeadTime);

  DateTime? get departedDeadline => timeStart.subtract(BizRules.departedLeadTime);

  /// Можно ли ещё откликнуться.
  bool get isOpenForResponse => status == OrderStatus.new_;
}

class GeoPoint {
  const GeoPoint({required this.lat, required this.lng});
  final double lat;
  final double lng;
}

/// Отклик грузчика с ETA.
class OrderResponse {
  const OrderResponse({
    required this.id,
    required this.orderId,
    required this.porterId,
    required this.etaMinutes,
    required this.status,
    required this.createdAt,
    this.decidedAt,
    this.decidedBy,
    this.declineReason,
    this.porterName,
  });

  final String id;
  final String orderId;
  final String porterId;
  final int etaMinutes;
  final ResponseStatus status;
  final DateTime createdAt;
  final DateTime? decidedAt;
  final String? decidedBy;
  final String? declineReason;

  /// Имя грузчика (диспетчерский пульт; join profiles).
  final String? porterName;

  /// Момент автоотклонения, если диспетчер не решил.
  DateTime get expiresAt =>
      createdAt.add(BizRules.etaApprovalTimeout);

  bool isExpiredAt(DateTime now) =>
      status == ResponseStatus.pending && now.isAfter(expiresAt);

  Duration remainingAt(DateTime now) => expiresAt.difference(now);
}

/// Участник бригады.
class OrderTaker {
  const OrderTaker({
    required this.orderId,
    required this.porter,
    required this.isLead,
    this.etaMinutes,
    this.joinedAt,
  });

  final String orderId;
  final PorterBrief porter;
  final bool isLead;
  final int? etaMinutes;
  final DateTime? joinedAt;
}

/// Запись этапа (для таймлайна).
class OrderStage {
  const OrderStage({
    required this.orderId,
    required this.porterId,
    required this.stage,
    required this.at,
    this.porterName,
    this.comment,
    this.late = false,
  });

  final String orderId;
  final String porterId;
  final OrderStageType stage;
  final DateTime at;
  final String? porterName;
  final String? comment;

  /// Этап зафиксирован с нарушением дедлайна (штраф уже применён).
  final bool late;
}

/// Что можно нажать прямо сейчас. Источник истины — бэкенд (Матвей).
class StageAvailability {
  const StageAvailability({
    required this.available,
    required this.isLead,
    this.nextRequired,
    this.wokeDeadline,
    this.departedDeadline,
    this.isLate = false,
    this.penaltyIfPressedNow = 0,
    this.blockedReason,
    this.feedbackDeadline,
  });

  final List<OrderStageType> available;
  final bool isLead;
  final OrderStageType? nextRequired;
  final DateTime? wokeDeadline;
  final DateTime? departedDeadline;
  final bool isLate;

  /// 🔴 Сколько спишется с рейтинга, если нажать сейчас (−5 за утренний дедлайн).
  final int penaltyIfPressedNow;

  /// «только старший», «заказ ещё не одобрен» и т.п.
  final String? blockedReason;

  /// Дедлайн обратной связи старшего (5 минут после `finished`).
  final DateTime? feedbackDeadline;

  bool canPress(OrderStageType s) => available.contains(s);

  static const empty = StageAvailability(available: [], isLead: false);
}

/// Результат нажатия этапа.
class StageResult {
  const StageResult({
    required this.stage,
    required this.at,
    this.ratingDelta = 0,
    this.late = false,
    this.orderReturnedToFeed = false,
    this.message,
  });

  final OrderStageType stage;
  final DateTime at;
  final int ratingDelta;
  final bool late;

  /// Заказ возвращён в ленту из-за пропуска утреннего дедлайна.
  final bool orderReturnedToFeed;
  final String? message;
}

/// Итог закрытия заказа — показываем грузчику.
class OrderCompletion {
  const OrderCompletion({
    required this.orderId,
    required this.minutesWorked,
    required this.hours,
    required this.totalHours,
    required this.ratingDelta,
    required this.finishedAt,
    this.moneyDelta,
    this.adjustedByDispatcher = false,
  });

  final String orderId;
  final int minutesWorked;

  /// «Кол-во Часов» (на человека).
  final double hours;

  /// «Сумма часов» (× людей).
  final double totalHours;
  final int ratingDelta;
  final DateTime finishedAt;

  /// Если баланс в MVP — иначе null.
  final double? moneyDelta;

  /// Часы поправлены диспетчером вручную (orders.minutes_adjusted_by_admin).
  final bool adjustedByDispatcher;
}

/// Отзыв заказчика.
class Review {
  const Review({
    required this.id,
    required this.orderId,
    required this.clientId,
    required this.porterId,
    required this.rating,
    required this.createdAt,
    this.text,
    this.porterName,
  });

  final String id;
  final String orderId;
  final String clientId;
  final String porterId;
  final int rating; // 1..5
  final String? text;
  final DateTime createdAt;
  final String? porterName;
}

/// Профиль грузчика (экран history/баланс).
class PorterProfile {
  const PorterProfile({
    required this.userId,
    required this.name,
    required this.rating,
    required this.completedCount,
    required this.failCount,
    this.balance = 0,
    this.isActive = true,
    this.referralCode,
    this.referralsCount = 0,
  });

  final String userId;
  final String name;
  final int rating;
  final int completedCount;

  /// Сколько раз провалил утренний дедлайн / не вышел.
  final int failCount;
  /// 🔴 MVP: всегда 0.00 (решение Матвея: денег в MVP нет). Экран баланса не рисуем.
  final double balance;
  final bool isActive;
  final String? referralCode;
  final int referralsCount;
}

/// Заявка на создание заказа (мастер заказчика).
class CreateOrderRequest {
  const CreateOrderRequest({
    required this.address,
    required this.timeStart,
    required this.peopleCount,
    required this.plannedDurationMin,
    required this.taskTitle,
    required this.taskDescription,
    required this.urgency,
    required this.tariff,
    this.entrance,
    this.transport = TransportType.none,
    this.phone,
    this.extraComments,
    this.coords,
  });

  final String address;
  final DateTime timeStart;
  final int peopleCount;
  final int plannedDurationMin;
  final String taskTitle;
  final String taskDescription;
  final OrderUrgency urgency;
  final String tariff;
  final String? entrance;
  final TransportType transport;
  final String? phone;
  final String? extraComments;
  final GeoPoint? coords;
}

class AddressSuggestion {
  const AddressSuggestion({
    required this.title,
    required this.fullAddress,
    this.coords,
  });
  final String title;
  final String fullAddress;
  final GeoPoint? coords;
}

/// Расчёт тарифа (калькулятор заказчика).
/// 🔴 Формулы пока нет — ждём от Матвея/бизнесмена. См. CONTRACT_methods.md, блок 8.
class TariffQuote {
  const TariffQuote({
    required this.price,
    required this.currency,
    required this.breakdown,
    this.hours,
  });
  final double price;
  final String currency; // 'RUB'
  final List<QuoteLine> breakdown;
  final double? hours;
}

class QuoteLine {
  const QuoteLine({required this.label, required this.amount});
  final String label;
  final double amount;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.orderId,
    required this.authorId,
    required this.text,
    required this.sentAt,
    this.authorName,
    this.authorRole,
    this.isMine = false,
    this.attachmentUrl,
  });

  final String id;
  final String orderId;
  final String authorId;
  final String? authorName;
  final UserRole? authorRole;
  final String text;
  final DateTime sentAt;
  final bool isMine;
  final String? attachmentUrl;
}

class PorterLocation {
  const PorterLocation({
    required this.porterId,
    required this.point,
    required this.at,
    this.porterName,
  });
  final String porterId;
  final String? porterName;
  final GeoPoint point;
  final DateTime at;
}
