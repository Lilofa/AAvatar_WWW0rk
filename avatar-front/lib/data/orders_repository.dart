/// ИНТЕРФЕЙС ДАННЫХ ПОТОКА ЗАКАЗА.
///
/// Зона: Артём пишет ИНТЕРФЕЙС (это ТЗ для Матвея),
///       Матвей пишет РЕАЛИЗАЦИЮ на Supabase.
///
/// 🔑 Главный принцип развязки:
///   Экраны → Riverpod-провайдер → `OrdersRepository` (этот интерфейс).
///   Ни один экран НЕ знает про Supabase. Подмена mock ↔ live = одна строка
///   в провайдере. Именно это позволяет мне делать неделю 1 на заглушках,
///   а на неделе 2 перейти на живые данные без переделки экранов.
///
/// Документ с вопросами по каждому блоку: `avatar/artem/CONTRACT_methods.md`.
library;

import 'dart:typed_data';

import '../features/order_flow/domain/enums.dart';
import '../features/order_flow/domain/models.dart';

/// Результат входа по SMS.
class AuthResult {
  const AuthResult({required this.userId, required this.roles, required this.profile});
  final String userId;
  final Set<UserRole> roles;
  final PorterProfile? profile;

  UserRole get primaryRole => roles.contains(UserRole.dispatcher)
      ? UserRole.dispatcher
      : roles.contains(UserRole.client)
          ? UserRole.client
          : UserRole.porter;
}

/// Почему лента пуста (Матвей, блок 2: meta.empty_reason) — разные тексты empty-состояния.
enum FeedEmptyReason {
  noOrders, // заказов нет вообще
  filteredOut, // есть, но под мой фильтр ничего не подошло
  allTaken, // были открытые, но все разобрали
}

/// Страница ленты: элементы + причина пустоты.
class FeedPage {
  const FeedPage({required this.items, required this.emptyReason});
  final List<Order> items;
  final FeedEmptyReason emptyReason;

  bool get isEmpty => items.isEmpty;
}

/// Фильтр ленты.
class FeedFilter {
  const FeedFilter({this.urgencies, this.dateFrom, this.dateTo, this.onlyMine = false});

  final Set<OrderUrgency>? urgencies;
  final DateTime? dateFrom;
  final DateTime? dateTo;

  /// Только заказы, где я в бригаде (для вкладки «Мои»).
  final bool onlyMine;

  static const all = FeedFilter();
}

/// Реферальная информация пользователя (v2, зеркало бота «Бонусная система»).
class ReferralEntry {
  const ReferralEntry({
    required this.name,
    required this.phoneMasked,
    required this.status,
    this.joinedAt,
  });
  final String name;
  final String phoneMasked;
  final ReferralStatus status;
  final DateTime? joinedAt;
}

class ReferralInfo {
  const ReferralInfo({
    required this.code,
    required this.invited,
  });
  final String? code;
  final List<ReferralEntry> invited;
  int get count => invited.length;
}

/// Один контракт на все методы потока. Ошибки — только [AppFailure].
abstract interface class OrdersRepository {
  // ── 1. АВТОРИЗАЦИЯ И ПРОФИЛЬ ──────────────────────────────
  Future<void> sendSmsCode({required String phone});

  /// [role] и [fullName] используются edge-функцией verify-sms только при
  /// ПЕРВОЙ регистрации пользователя (повторный вход их игнорирует).
  Future<AuthResult> verifySmsCode({
    required String phone,
    required String code,
    UserRole? role,
    String? fullName,
  });
  Stream<UserProfile?> watchCurrentUser();
  Future<PorterProfile> getPorterProfile({required String userId});
  Future<String?> getReferralCode({required String userId});

  // ── 2. ЛЕНТА И ОТКЛИК ─────────────────────────────────────
  Stream<FeedPage> watchFeed({FeedFilter filter = FeedFilter.all, int limit = 30, String? cursor});
  Future<Order> getOrder({required String orderId});
  Future<OrderResponse> respondToOrder({required String orderId, required int etaMinutes});
  Future<void> cancelResponse({required String responseId});
  Stream<OrderResponse?> watchMyResponse({required String orderId});

  // ── 3. ЭТАПЫ ──────────────────────────────────────────────
  Stream<List<OrderStage>> watchOrderStages({required String orderId});

  /// Зафиксировать этап. Бэкенд валидирует порядок, роль старшего и дедлайны.
  Future<StageResult> setStage({
    required String orderId,
    required OrderStageType stage,
    DateTime? clientTime,
    GeoPoint? location,
  });

  /// 🔴 Что доступно ПРЯМО СЕЙЧАС. Правила живёт на бэке, клиент только рисует.
  Future<StageAvailability> getStageAvailability({required String orderId});

  Future<void> submitDelayReason({required String orderId, required String reason});

  // ── 4. БРИГАДА И СТАРШИЙ ──────────────────────────────────
  Stream<PorterBrief?> watchLead({required String orderId});
  Stream<List<OrderTaker>> watchOrderTakers({required String orderId});

  // ── 5. ЗАКРЫТИЕ И ОБРАТНАЯ СВЯЗЬ ──────────────────────────
  Future<OrderCompletion> finishOrder({
    required String orderId,
    required bool wentWell,
    String? resultComment,
  });

  Stream<OrderStatus> watchOrderStatus({required String orderId});

  // ── 6. ОТЗЫВЫ И РЕЙТИНГ ───────────────────────────────────
  Future<void> submitClientReview({required String orderId, required int rating, String? text});
  Future<List<Review>> getPorterReviews({required String porterId, int limit = 20});
  Stream<int> watchPendingReviewCount();

  // ── 7. ЧАТ ПО ЗАКАЗУ ──────────────────────────────────────
  Stream<List<ChatMessage>> watchOrderChat({required String orderId, int limit = 50});

  /// [attachmentUrl] — публичная ссылка на фото из бакета 'orders'
  /// (uploadOrderPhoto). Бэк: колонка messages.attachment_url (миграция
  /// 20260930120000, предложил агент, применяет Матвей).
  Future<void> sendOrderChatMessage({
    required String orderId,
    required String text,
    String? attachmentUrl,
  });

  // ── 8. ЗАКАЗЧИК: СОЗДАНИЕ ЗАЯВКИ ──────────────────────────
  Future<Order> createOrder(CreateOrderRequest request);
  Future<List<AddressSuggestion>> searchAddress({required String query});
  Future<TariffQuote> quoteOrder({
    required int peopleCount,
    required int plannedDurationMin,
    required OrderUrgency urgency,
    TransportType transport = TransportType.none,
  });

  Stream<List<Order>> watchMyClientOrders();

  /// Заказы, где я в бригаде (моя работа грузчиком). Баг-репорт 25.09:
  /// «Мои заказы» не должны смешиваться с моей работой, и свои же
  /// выполненные заказы я оценивать не могу.
  Future<List<Order>> myWorkOrders();

  Future<void> cancelOrder({required String orderId, String? reason});

  // ── 9. ДИСПЕТЧЕР (экраны — зона Коли → Артём после 20.09) ──
  /// Живые заказы для пульта диспетчера (created/accepted/in_progress).
  Stream<List<Order>> watchDispatcherOrders();

  Future<List<OrderResponse>> getPendingResponses({required String orderId});
  Future<void> approveResponse({required String responseId});
  Future<void> declineResponse({required String responseId});
  Future<void> assignLead({required String orderId, required String porterId});
  Future<void> forceCloseOrder({required String orderId, required String comment});
  Future<void> findReplacement({required String orderId});
  Stream<List<PorterLocation>> watchPorterLocations({required String orderId});

  // ── 11. РЕФЕРАЛКА (v2; бэк: profiles.referral_code/invited_by) ──
  /// Мой код + кого привёл. Статусы засчёта (5 дней в чате) считает бэк;
  /// пока таблицы referrals нет — все входящие считаются fresh (пинг Матвею).
  Future<ReferralInfo> getMyReferralInfo();

  /// Сгенерировать код, если его нет (RPC profiles_gen_referral_code).
  Future<String> ensureReferralCode();

  // ── 10. ФОТО ЗАКАЗА (storage bucket 'orders', миграция 18.09) ──
  /// Загрузить фото к заказу; возвращает публичный URL для вставки в отзыв/чат.
  Future<String> uploadOrderPhoto({
    required String orderId,
    required Uint8List bytes,
    required String fileName,
  });
}

/// Минимальный профиль текущего пользователя (core-слой, не мой).
/// Прошу Колю/Матвея оставить его в `core`, я только потребляю.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.phone,
    required this.roles,
    required this.name,
    this.avatarUrl,
    this.isActive = true,
  });

  final String id;
  final String phone;
  final Set<UserRole> roles;
  final String name;
  final String? avatarUrl;
  final bool isActive;

  bool has(UserRole r) => roles.contains(r);
  bool get isPorter => has(UserRole.porter);
  bool get isDispatcher => has(UserRole.dispatcher) || has(UserRole.admin);
}
