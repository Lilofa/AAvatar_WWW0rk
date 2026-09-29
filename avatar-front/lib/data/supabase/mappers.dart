/// МАППЕРЫ: строка БД Матвея → UI-модели Артёма.
///
/// Зона: Артём. Чистые функции без Supabase-типов — тестируются без бэкенда.
///
/// 🔑 Правила:
///  * Время на проводе — UTC (timestamptz). UI живёт в настенном времени
///    Asia/Novosibirsk (UTC+7), поэтому конвертация здесь, в одном месте.
///  * `entrance` в БД — int, в модели — String? («Номер подъ-да»).
///  * `expired` у отклика в БД НЕ хранится: это pending, у которого вышел
///    5-минутный таймаут одобрения (считаем по now, часы внедрены для тестов).
///  * Срочность `replacement` в БД — флаг is_replacement + wire 'urgent'.
library;

import 'dart:convert';

import '../orders_repository.dart';
import '../../features/order_flow/domain/enums.dart';
import '../../features/order_flow/domain/models.dart';

/// Смещение Новосибирска от UTC (без летнего времени).
const Duration kNskOffset = Duration(hours: 7);

/// UTC (с провода) → настенное время Новосибирска; null-safe вариант.
DateTime? nskFromWireOpt(Object? v) => v == null ? null : nskFromWire(v);

/// 🔴 НЕ зависит от часового пояса МАШИНЫ (баг 20.09: песочница UTC маскировала,
/// машина Артёма +7 поймала). Возвращаем НАИВНЫЙ DateTime с настенным
/// временем НСК: сначала сдвигаем в UTC-компонентах, потом снимаем зону.
DateTime nskFromWire(Object? v) {
  if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);
  final dt = v is DateTime ? v : DateTime.parse(v.toString());
  final utc = dt.isUtc ? dt : dt.toUtc();
  final s = DateTime.fromMillisecondsSinceEpoch(
    utc.millisecondsSinceEpoch + kNskOffset.inMilliseconds,
    isUtc: true,
  );
  return DateTime(s.year, s.month, s.day, s.hour, s.minute, s.second, s.millisecond);
}

/// Настенное время Новосибирска → UTC-строка для записи в БД.
/// Наивный вход трактуем КАК НСК, зону навешиваем через DateTime.utc
/// (toUtc() на наивном DateTime трактовал бы его как локальное время машины).
String nskToWireUtc(DateTime nskWall) {
  final u = nskWall.subtract(kNskOffset);
  return DateTime.utc(u.year, u.month, u.day, u.hour, u.minute, u.second, u.millisecond)
      .toIso8601String();
}

double _num(Object? v, [double d = 0]) =>
    v == null ? d : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? d);

int _int(Object? v, [int d = 0]) =>
    v == null ? d : (v is num ? v.toInt() : int.tryParse(v.toString()) ?? d);

bool _bool(Object? v, [bool d = false]) =>
    v == null ? d : (v is bool ? v : v.toString() == 'true' || v.toString() == 't');

String? _str(Object? v) {
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

Map<String, dynamic>? _jsonMap(Object? v) {
  if (v == null) return null;
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
  if (v is String) {
    try {
      final d = jsonDecode(v);
      if (d is Map) return d.map((k, val) => MapEntry(k.toString(), val));
    } catch (_) {}
  }
  return null;
}

GeoPoint? _geo(Object? v) {
  final m = _jsonMap(v);
  if (m == null) return null;
  final lat = m['lat'] ?? m['latitude'];
  final lng = m['lng'] ?? m['lon'] ?? m['longitude'];
  if (lat == null || lng == null) return null;
  return GeoPoint(lat: _num(lat), lng: _num(lng));
}

// ─────────────────────────────────────────────────────────────
// ЗАКАЗ
// ─────────────────────────────────────────────────────────────

/// Строка `orders` → [Order].
///
/// [myResponseStatus] подставляется репозиторием отдельно (join откликов).
Order orderFromRow(
  Map<String, dynamic> row, {
  ResponseStatus? myResponseStatus,
  DateTime? now,
  bool clientIsMe = false,
}) {
  final urgencyRaw = _str(row['urgency']) ?? 'current';
  final isReplacement = _bool(row['is_replacement']);
  final timeStart = row['scheduled_at'] ?? row['available_from'] ?? row['created_at'];
  final entrance = row['entrance'];
  final cargo = _str(row['cargo_type']);
  return Order(
    id: row['id'] as String,
    clientId: _str(row['client_id']) ?? '',
    address: _str(row['address_from']) ?? _str(row['address_to']) ?? '',
    timeStart: nskFromWire(timeStart),
    plannedDurationMin: _int(row['planned_duration_min'], 60),
    peopleCount: _int(row['people_count'], 1),
    status: OrderStatus.fromWire(_str(row['status']) ?? 'created'),
    urgency: OrderUrgency.fromWire(urgencyRaw, isReplacement: isReplacement),
    taskTitle: _str(row['task_title']) ?? cargo ?? 'Заказ',
    taskDescription: _str(row['task_description']) ?? _str(row['comment']) ?? '',
    entrance: entrance?.toString(),
    transport: TransportType.fromWire(_str(row['transport'])),
    clientPhone: _str(row['client_phone']),
    extraComments: _str(row['comment']),
    clientTariffHint: _str(row['tariff_hint']),
    porterTariffHint: _str(row['tariff_hint']),
    resultComment: _str(row['result_comment']),
    coords: _geo(row['coords_from']) ?? _geo(row['coords_to']),
    createdAt: nskFromWireOpt(row['created_at']),
    myResponseStatus: myResponseStatus,
    feedbackMissed: _bool(row['feedback_missed']),
    // Матвей 20.09: устойчивый флаг форс-закрытия (миграция ...fixes_for_artem).
    forceClosed: _bool(row['force_closed']),
    isReplacement: isReplacement,
    clientIsMe: clientIsMe,
  );
}

/// Строка `order_responses` → [OrderResponse].
///
/// `expired` вычисляем: pending + вышел 5-минутный таймаут одобрения.
OrderResponse responseFromRow(
  Map<String, dynamic> row, {
  required DateTime now,
  String? porterName,
}) {
  final createdAt = nskFromWire(row['created_at']);
  final raw = _str(row['status']) ?? 'pending';
  var status = switch (raw) {
    'approved' => ResponseStatus.approved,
    'declined' => ResponseStatus.declined,
    _ => ResponseStatus.pending,
  };
  final resp = OrderResponse(
    id: row['id'] as String,
    orderId: row['order_id'] as String,
    porterId: _str(row['porter_id']) ?? '',
    etaMinutes: _int(row['eta_minutes']),
    status: status,
    createdAt: createdAt,
    decidedAt: nskFromWireOpt(row['decided_at']),
    decidedBy: _str(row['decided_by']),
    declineReason: _str(row['decline_reason']),
    porterName: porterName,
  );
  if (status == ResponseStatus.pending && now.isAfter(resp.expiresAt)) {
    status = ResponseStatus.expired;
    return OrderResponse(
      id: resp.id,
      orderId: resp.orderId,
      porterId: resp.porterId,
      etaMinutes: resp.etaMinutes,
      status: status,
      createdAt: resp.createdAt,
      decidedAt: resp.expiresAt,
      decidedBy: resp.decidedBy,
      declineReason: resp.declineReason,
      porterName: porterName,
    );
  }
  return resp;
}

// ─────────────────────────────────────────────────────────────
// ЭТАПЫ / БРИГАДА
// ─────────────────────────────────────────────────────────────

OrderStage stageFromRow(Map<String, dynamic> row, {String? porterName}) => OrderStage(
      orderId: row['order_id'] as String,
      porterId: _str(row['porter_id']) ?? '',
      stage: OrderStageType.fromWire(_str(row['stage']) ?? 'arrived'),
      at: nskFromWire(row['created_at']),
      porterName: porterName,
      // Штраф/опоздание бэкенд считает в mark_stage; история приходит без флага.
      late: _bool(row['late']),
    );

/// jsonb из `get_stage_availability` → [StageAvailability].
StageAvailability availabilityFromJson(Map<String, dynamic> j) {
  final available = (j['available'] as List? ?? const [])
      .map((e) => OrderStageType.fromWire(e.toString()))
      .toList();
  final next = _str(j['next_required']);
  return StageAvailability(
    available: available,
    isLead: _bool(j['is_lead']),
    nextRequired: next == null ? null : OrderStageType.fromWire(next),
    wokeDeadline: nskFromWireOpt(j['woke_deadline']),
    departedDeadline: nskFromWireOpt(j['departed_deadline']),
    isLate: _bool(j['is_late']),
    penaltyIfPressedNow: _int(j['penalty_if_pressed_now']),
    blockedReason: _str(j['blocked_reason']),
    // Матвей 20.09: feedback_deadline = finished_at + 5 мин (null до finished).
    feedbackDeadline: nskFromWireOpt(j['feedback_deadline']),
  );
}

/// jsonb из `mark_stage` → [StageResult].
StageResult stageResultFromJson(Map<String, dynamic> j, {required DateTime at}) {
  final penalty = _int(j['penalty']);
  return StageResult(
    stage: OrderStageType.fromWire(_str(j['stage']) ?? 'arrived'),
    at: at,
    ratingDelta: -penalty,
    late: penalty > 0,
    orderReturnedToFeed: _bool(j['order_returned_to_feed']),
    message: _bool(j['already_set'])
        ? 'Этап уже был отмечен'
        : _str(j['message']) ?? (penalty > 0 ? 'Штраф −$penalty к рейтингу' : null),
  );
}

/// jsonb из `finish_order` → [OrderCompletion].
OrderCompletion completionFromJson(Map<String, dynamic> j) => OrderCompletion(
      orderId: _str(j['order_id']) ?? '',
      minutesWorked: _int(j['minutes_worked']),
      hours: _num(j['hours']),
      totalHours: _num(j['total_hours']),
      ratingDelta: _int(j['rating_delta']),
      finishedAt: nskFromWire(j['finished_at']),
      moneyDelta: j['money_delta'] == null ? null : _num(j['money_delta']),
      adjustedByDispatcher: _bool(j['adjusted_by_dispatcher']),
    );

/// Строка `order_takers` + профиль → [OrderTaker].
OrderTaker takerFromRow(
  Map<String, dynamic> row, {
  required PorterBrief porter,
  int? etaMinutes,
}) =>
    OrderTaker(
      orderId: row['order_id'] as String,
      porter: porter.copyWith(isLead: _bool(row['is_lead'])),
      isLead: _bool(row['is_lead']),
      etaMinutes: etaMinutes,
      joinedAt: nskFromWireOpt(row['joined_at']),
    );

// ─────────────────────────────────────────────────────────────
// ЛЮДИ
// ─────────────────────────────────────────────────────────────

Set<UserRole> rolesFromProfileRow(Map<String, dynamic> row) {
  final arr = (row['roles'] as List? ?? const [])
      .map((e) => UserRole.fromWire(e.toString()))
      .toSet();
  if (arr.isNotEmpty) return arr;
  return {UserRole.fromWire(_str(row['role']) ?? 'client')};
}

PorterBrief briefFromProfileRow(Map<String, dynamic> row, {bool isLead = false}) =>
    PorterBrief(
      id: row['id'] as String,
      name: _str(row['full_name']) ?? 'Грузчик',
      rating: _num(row['rating']).round(),
      completedCount: _int(row['completed_count']),
      // Матвей 20.09: profiles.fail_count инкрементит process_order_deadlines.
      failCount: _int(row['fail_count']),
      avatarUrl: _str(row['avatar_url']),
      isLead: isLead,
    );

PorterProfile porterProfileFromRow(Map<String, dynamic> row,
        {int referralsCount = 0}) =>
    PorterProfile(
      userId: row['id'] as String,
      name: _str(row['full_name']) ?? 'Грузчик',
      rating: _num(row['rating']).round(),
      completedCount: _int(row['completed_count']),
      failCount: _int(row['fail_count']),
      balance: 0, // MVP: денег нет (решение Матвея).
      isActive: !_bool(row['is_blocked']),
      referralCode: _str(row['referral_code']),
      referralsCount: referralsCount,
    );

UserProfile userProfileFromRow(Map<String, dynamic> row) => UserProfile(
      id: row['id'] as String,
      phone: _str(row['phone']) ?? '',
      roles: rolesFromProfileRow(row),
      name: _str(row['full_name']) ?? 'Клиент',
      avatarUrl: _str(row['avatar_url']),
      isActive: !_bool(row['is_blocked']),
    );

// ─────────────────────────────────────────────────────────────
// ОТЗЫВЫ / ЧАТ / ГЕО
// ─────────────────────────────────────────────────────────────

Review reviewFromRow(Map<String, dynamic> row, {String? porterName}) => Review(
      id: row['id'] as String,
      orderId: _str(row['order_id']) ?? '',
      clientId: _str(row['author_id']) ?? '',
      porterId: _str(row['target_id']) ?? '',
      rating: _int(row['rating'], 5),
      text: _str(row['text']),
      createdAt: nskFromWire(row['created_at']),
      porterName: porterName,
    );

ChatMessage messageFromRow(
  Map<String, dynamic> row, {
  required String myId,
  String? authorName,
  UserRole? authorRole,
}) =>
    ChatMessage(
      id: row['id'] as String,
      orderId: row['order_id'] as String,
      authorId: _str(row['author_id']) ?? '',
      text: _str(row['text']) ?? '',
      sentAt: nskFromWire(row['created_at']),
      authorName: authorName,
      authorRole: authorRole,
      isMine: _str(row['author_id']) == myId,
    );

PorterLocation locationFromRow(Map<String, dynamic> row, {String? porterName}) =>
    PorterLocation(
      porterId: _str(row['porter_id']) ?? '',
      porterName: porterName,
      point: GeoPoint(lat: _num(row['lat']), lng: _num(row['lng'])),
      at: nskFromWire(row['created_at']),
    );

/// Маска телефона для списков: +7 ••• •••-••-99 (последние две цифры).
String maskPhone(String? phone) {
  final d = (phone ?? '').replaceAll(RegExp(r'\D'), '');
  if (d.length < 4) return 'номер скрыт';
  return '+7 ••• •••-••-${d.substring(d.length - 2)}';
}

// ─────────────────────────────────────────────────────────────
// ТАРИФ / АДРЕСА / ЗАПИСЬ ЗАКАЗА
// ─────────────────────────────────────────────────────────────

/// jsonb из `quote_order_detailed` (Матвей, 20.09) → [TariffQuote].
///
/// Контракт: { total: numeric, lines: [{label, amount}] }.
/// Если lines вдруг нет (старый бэк) — раскладываем total на работы+транспорт.
TariffQuote quoteFromDetailedJson(
  Map<String, dynamic> j, {
  required int plannedDurationMin,
  required TransportType transport,
}) {
  final total = _num(j['total']);
  final rawLines = j['lines'] as List?;
  final hours = (plannedDurationMin / 30).ceil() * 0.5;
  final breakdown = <QuoteLine>[
    if (rawLines != null)
      for (final l in rawLines)
        QuoteLine(
          label: _str((l as Map)['label']) ?? 'Позиция',
          amount: _num(l['amount']),
        )
    else ...[
      QuoteLine(
        label: 'Работы с коэффициентами',
        amount: (total - transport.feeRub).clamp(0, double.infinity).toDouble(),
      ),
      if (transport.feeRub > 0)
        QuoteLine(label: 'Транспорт', amount: transport.feeRub.toDouble()),
    ],
  ];
  return TariffQuote(
    price: total,
    currency: 'RUB',
    hours: hours,
    breakdown: breakdown,
  );
}

/// Элемент `results` из edge-функции search-address → [AddressSuggestion].
AddressSuggestion suggestionFromJson(Map<String, dynamic> j) {
  final full = _str(j['display_name']) ?? '';
  final title = full
      .split(',')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .take(2)
      .join(', ');
  return AddressSuggestion(
    title: title.isEmpty ? full : title,
    fullAddress: full,
    coords: (j['lat'] == null || j['lng'] == null)
        ? null
        : GeoPoint(lat: _num(j['lat']), lng: _num(j['lng'])),
  );
}

/// [CreateOrderRequest] → карта для INSERT в `orders`.
///
/// Время: настенное НСК → UTC. Срочность: replacement → wire 'urgent' + флаг.
Map<String, dynamic> orderInsertFromRequest(
  CreateOrderRequest r, {
  required String clientId,
}) =>
    {
      'client_id': clientId,
      'address_from': r.address,
      'address_to': r.address,
      'scheduled_at': nskToWireUtc(r.timeStart),
      'people_count': r.peopleCount,
      'planned_duration_min': r.plannedDurationMin,
      'task_title': r.taskTitle,
      'task_description': r.taskDescription,
      'urgency': r.urgency.wire,
      'is_replacement': r.urgency == OrderUrgency.replacement,
      'transport': r.transport.wire,
      'tariff_hint': r.tariff,
      'client_phone': r.phone,
      'comment': r.extraComments,
      'entrance': r.entrance == null ? null : int.tryParse(r.entrance!),
      if (r.coords != null)
        'coords_from': {'lat': r.coords!.lat, 'lng': r.coords!.lng},
      // Матвей 20.09: price NOT NULL, при создании ставим 0 — триггер
      // check_order_filled пересчитает при created → accepted.
      // 🔴 planned_duration_min обязателен, иначе триггер не пересчитает!
      'price': 0,
    };
