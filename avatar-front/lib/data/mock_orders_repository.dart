/// МОК-РЕПОЗИТОРИЙ ПОТОКА ЗАКАЗА.
///
/// Зона: Артём. Живёт до тех пор, пока Матвей не отдаст `SupabaseOrdersRepository`.
///
/// Зачем он такой «толстый»:
///  1. Реалистичные задержки (300–900 мс) → состояние loading видно по-настоящему.
///  2. Случайные ошибки (1 из N) → состояние error всплывает само, а не «в теории».
///  3. [MockControls] → принудительно переключаю любой поток в
///     loading / data / empty / error из debug-меню. Это и есть ревью Коли за 15 минут.
///  4. Память состояния → нажал этап, он реально зафиксировался, лента обновилась.
///
/// Подмена на прод: в провайдере Riverpod заменить одну строку
///   `OrdersRepository(...)` → `SupabaseOrdersRepository(...)`.
///   Экраны не трогать вообще.
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

// AppFailure/Failures приходят и через export orders_repository.dart,
// но импорт держим явным: если export уберут при переносе в скелет Коли,
// этот файл не должен молча сломаться.
import '../core/error/app_failure.dart';
import '../features/order_flow/domain/enums.dart';
import '../features/order_flow/domain/models.dart';
import '../features/order_flow/domain/order_state_machine.dart';
import '../features/order_flow/domain/pricing.dart';
import 'orders_repository.dart';

/// Какой режим сейчас форсирует debug-меню.
enum MockMode {
  normal, // обычные данные + случайные задержки/ошибки
  slow, // 3 секунды на ответ — проверять shimmer и таймауты
  empty, // все списки пустые — проверять EmptyState
  error; // все запросы падают — проверять ErrorState и «Повторить»
}

abstract final class MockControls {
  static MockMode mode = MockMode.normal;

  /// Вероятность случайной ошибки в normal-режиме (1 из N).
  /// 0 = выключено: в демо/прогоне случайные сбои бесит; error-состояния
  /// проверяются режимом MockMode.error и виджет-тестами.
  static int randomErrorEveryN = 0;

  /// Включить «гонку»: заказ уходит из-под носа при попытке откликнуться.
  static bool simulateRaceCondition = false;

  /// Включить офлайн: все запросы возвращают `Failures.offline()`.
  static bool simulateOffline = false;

  /// Отключить случайные задержки (для виджет-тестов: pump без таймеров).
  static bool instant = false;

  /// Авто-решение диспетчера по отклику через 6 секунд (Future.delayed).
  /// В виджет-тестах выключать: висящий Timer ломает инвариант testWidgets.
  static bool simulateDispatcher = true;

  /// Роли демо-пользователя. Меняются переключателем в демо-сборке
  /// («Роль: …» в красной полосе сверху), приложение перестраивает вкладки.
  static const Set<UserRole> allDemoRoles = {
    UserRole.porter,
    UserRole.dispatcher,
    UserRole.client,
  };
  static Set<UserRole> demoRoles = allDemoRoles;
  static final StreamController<Set<UserRole>> _roles =
      StreamController<Set<UserRole>>.broadcast();

  static Stream<Set<UserRole>> get demoRolesChanges => _roles.stream;

  /// Город демо-пользователя (null — ещё не выбран/не определён).
  static String? demoCity;

  static void setDemoRoles(Set<UserRole> roles) {
    demoRoles = roles;
    _roles.add(roles);
  }
}

class MockOrdersRepository implements OrdersRepository {
  MockOrdersRepository({Random? random, DateTime Function()? clock})
      : _rnd = random ?? Random(7),
        _now = clock ?? DateTime.now {
    _seed();
  }

  final Random _rnd;
  final DateTime Function() _now;

  final _feedCtrl = StreamController<List<Order>>.broadcast();
  final _stages = <String, StreamController<List<OrderStage>>>{};
  final _status = <String, StreamController<OrderStatus>>{};
  final _takers = <String, StreamController<List<OrderTaker>>>{};
  final _responses = <String, StreamController<OrderResponse?>>{};
  final _chat = <String, StreamController<List<ChatMessage>>>{};

  final Map<String, Order> _orders = {};
  final Map<String, List<OrderStage>> _orderStages = {};
  final Map<String, List<OrderTaker>> _orderTakers = {};
  final Map<String, OrderResponse> _myResponses = {};
  final Map<String, List<ChatMessage>> _chats = {};

  static const _me = 'porter-artem-374545233';
  static const _client = 'client-demo-1';

  // ───────────────────────────────────────────────────────────
  // СЛУЖЕБНОЕ
  // ───────────────────────────────────────────────────────────

  /// Имитация сетевой задержки и ошибок ДЛЯ СТРИМОВ
  /// (в _guard это делается для Future, здесь — для первого кадра stream).
  Future<void> _streamGate() async {
    if (MockControls.simulateOffline) throw Failures.offline();
    final delay = MockControls.instant
        ? Duration.zero
        : switch (MockControls.mode) {
            MockMode.slow => const Duration(seconds: 3),
            MockMode.empty => const Duration(milliseconds: 400),
            MockMode.error => const Duration(milliseconds: 500),
            MockMode.normal => Duration(milliseconds: 250 + _rnd.nextInt(400)),
          };
    if (delay != Duration.zero) await Future<void>.delayed(delay);
    if (MockControls.mode == MockMode.error) throw Failures.server('mock');
  }

  Future<T> _guard<T>(Future<T> Function() body, {int? errorEveryN}) async {
    if (MockControls.simulateOffline) throw Failures.offline();

    final delay = MockControls.instant
        ? Duration.zero
        : switch (MockControls.mode) {
            MockMode.slow => const Duration(seconds: 3),
            MockMode.empty => const Duration(milliseconds: 400),
            MockMode.error => const Duration(milliseconds: 500),
            MockMode.normal => Duration(milliseconds: 300 + _rnd.nextInt(600)),
          };
    if (delay != Duration.zero) await Future<void>.delayed(delay);

    if (MockControls.mode == MockMode.error) throw Failures.server('mock');

    final n = errorEveryN ?? MockControls.randomErrorEveryN;
    if (MockControls.mode == MockMode.normal && n > 0 && _rnd.nextInt(n) == 0) {
      throw Failures.server('random mock failure');
    }

    return body();
  }

  void _seed() {
    final base = _now();

    // 1. Срочный — дедлайн 1 час, красная плашка, сверху ленты.
    _addOrder(Order(
      id: 'ord-1001',
      clientId: _client,
      address: 'г. Новосибирск, ул. Ленина, 12',
      timeStart: base.add(const Duration(minutes: 50)),
      plannedDurationMin: 120,
      peopleCount: 2,
      status: OrderStatus.new_,
      urgency: OrderUrgency.urgent,
      taskTitle: 'Переезд офиса, 3 этаж',
      taskDescription: 'Спустить 40 коробок и 2 стола, погрузить в Газель.',
      clientTariffHint: 'Стандарт',
      porterTariffHint: '350 ₽/час',
      transport: TransportType.gazelle,
      clientPhone: '+7 913 000-00-00',
      extraComments: 'Лифта нет. Домофон сломан, звонить в 3-ю квартиру.',
      coords: const GeoPoint(lat: 55.0415, lng: 82.9346),
      createdAt: base.subtract(const Duration(minutes: 4)),
    ));

    // 2. Текущий — обычный.
    _addOrder(Order(
      id: 'ord-1002',
      clientId: _client,
      address: 'г. Новосибирск, ул. Кирова, 27/1',
      timeStart: base.add(const Duration(hours: 2, minutes: 20)),
      plannedDurationMin: 90,
      peopleCount: 3,
      status: OrderStatus.new_,
      urgency: OrderUrgency.current,
      taskTitle: 'Подъём стройматериалов',
      taskDescription: 'Поднять 25 мешков штукатурки на 5 этаж без лифта.',
      clientTariffHint: 'Стандарт',
      porterTariffHint: '350 ₽/час',
      coords: const GeoPoint(lat: 55.0257, lng: 82.9436),
      createdAt: base.subtract(const Duration(minutes: 40)),
    ));

    // 3. Замена — кто-то отказался, срочность immediate.
    _addOrder(Order(
      id: 'ord-1003',
      clientId: _client,
      address: 'г. Новосибирск, ул. Богдана Хмельницкого, 40',
      timeStart: base.add(const Duration(hours: 1, minutes: 10)),
      plannedDurationMin: 60,
      peopleCount: 2,
      status: OrderStatus.new_,
      urgency: OrderUrgency.replacement,
      taskTitle: 'Замена грузчика на вывоз мусора',
      taskDescription: 'Вынести строительный мусор после ремонта, 15 мешков.',
      isReplacement: true,
      coords: const GeoPoint(lat: 55.0921, lng: 82.9547),
      createdAt: base.subtract(const Duration(minutes: 2)),
    ));

    // 4. УТРЕННИЙ заказ на завтра — здесь живёт этап «Проснулся» и штрафы.
    // Через Duration, а не `base.day + 1`: иначе 31-го числа мок уедет
    // в несуществующую дату и «утренний» заказ перестанет быть утренним.
    final tomorrow = base.add(const Duration(days: 1));
    final tomorrowMorning = DateTime(
      tomorrow.year,
      tomorrow.month,
      tomorrow.day,
      7, // 07:00 → утренний (4:00–12:00)
    );
    _addOrder(Order(
      id: 'ord-1004',
      clientId: _client,
      address: 'г. Новосибирск, ул. Станционная, 60',
      timeStart: tomorrowMorning,
      plannedDurationMin: 180,
      peopleCount: 4,
      status: OrderStatus.new_,
      urgency: OrderUrgency.advance,
      taskTitle: 'Погрузка фуры утром',
      taskDescription: 'Загрузить паллеты в фуру, работа на складе, есть рохля.',
      clientTariffHint: 'Ночной/утренний',
      porterTariffHint: '400 ₽/час',
      coords: const GeoPoint(lat: 54.9893, lng: 82.8476),
      createdAt: base.subtract(const Duration(hours: 5)),
    ));

    // 5. Предварительный — вечерняя рассылка, в будущем.
    _addOrder(Order(
      id: 'ord-1005',
      clientId: _client,
      address: 'г. Новосибирск, ул. Советская, 5',
      timeStart: base.add(const Duration(days: 2, hours: 6)),
      plannedDurationMin: 60,
      peopleCount: 2,
      status: OrderStatus.new_,
      urgency: OrderUrgency.preliminary,
      taskTitle: 'Перенос мебели в квартире',
      taskDescription: 'Переставить диван и шкаф между комнатами.',
      coords: const GeoPoint(lat: 55.0306, lng: 82.9157),
      createdAt: base.subtract(const Duration(hours: 8)),
    ));

    // 5b. Утренний одобренный заказ, где я в бригаде: предупреждения о дедлайне.
    final morningApproved = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 7, 0);
    _addOrder(Order(
      id: 'ord-1006',
      clientId: _client,
      address: 'г. Новосибирск, ул. Тайгинская, 8',
      timeStart: morningApproved,
      plannedDurationMin: 120,
      peopleCount: 2,
      status: OrderStatus.approved,
      urgency: OrderUrgency.advance,
      taskTitle: 'Утренняя погрузка (тест предупреждений)',
      taskDescription: 'Проверка предупреждения о дедлайне «Проснулся».',
      coords: const GeoPoint(lat: 55.0644, lng: 83.0029),
      createdAt: base.subtract(const Duration(hours: 2)),
    ));
    _orderTakers['ord-1006'] = [
      const OrderTaker(
        orderId: 'ord-1006',
        porter: PorterBrief(id: _me, name: 'Артём', rating: 212, completedCount: 131, isLead: true),
        isLead: true,
        etaMinutes: 20,
      ),
    ];

    // 6. Мой активный заказ — на нём тестируем этапы, старшего и овертайм.
    final activeStart = base.subtract(const Duration(minutes: 25));
    _addOrder(Order(
      id: 'ord-2001',
      clientId: _client,
      address: 'г. Новосибирск, пр-т Карла Маркса, 30',
      timeStart: activeStart,
      plannedDurationMin: 60,
      peopleCount: 2,
      status: OrderStatus.inProgress,
      urgency: OrderUrgency.current,
      taskTitle: 'Квартирный переезд',
      taskDescription: 'Вынести вещи из квартиры, погрузить, поднять на новом адресе.',
      entrance: '2-й подъезд, код 45К6, этаж 4, лифт работает',
      clientPhone: '+7 913 111-22-33',
      resultComment: null,
      coords: const GeoPoint(lat: 54.9862, lng: 82.893),
      createdAt: base.subtract(const Duration(hours: 3)),
    ));

    _orderStages['ord-2001'] = [
      OrderStage(
        orderId: 'ord-2001',
        porterId: 'porter-ivan-1',
        stage: OrderStageType.departed,
        at: activeStart.subtract(const Duration(minutes: 32)),
        porterName: 'Иван П.',
      ),
      OrderStage(
        orderId: 'ord-2001',
        porterId: 'porter-ivan-1',
        stage: OrderStageType.arrived,
        at: activeStart.subtract(const Duration(minutes: 6)),
        porterName: 'Иван П.',
      ),
    ];

    _orderTakers['ord-2001'] = [
      const OrderTaker(
        orderId: 'ord-2001',
        porter: PorterBrief(
          id: 'porter-ivan-1',
          name: 'Иван П.',
          rating: 148,
          completedCount: 96,
          isLead: true,
        ),
        isLead: true,
        etaMinutes: 12,
      ),
      const OrderTaker(
        orderId: 'ord-2001',
        porter: PorterBrief(
          id: _me,
          name: 'Артём',
          rating: 212,
          completedCount: 131,
        ),
        isLead: false,
        etaMinutes: 18,
      ),
    ];

    _chats['ord-2001'] = [
      ChatMessage(
        id: 'm1',
        orderId: 'ord-2001',
        authorId: 'dispatcher-90182825',
        authorName: 'Диспетчер',
        authorRole: UserRole.dispatcher,
        text: 'Бригада на месте, начинайте. Клиент ждёт у подъезда.',
        sentAt: activeStart.subtract(const Duration(minutes: 5)),
      ),
    ];

    // 7. Завершённый заказ без отзыва заказчика — для цикла отзыва.
    _addOrder(Order(
      id: 'ord-3001',
      clientId: _client,
      address: 'г. Новосибирск, ул. Гоголя, 15',
      timeStart: base.subtract(const Duration(days: 1, hours: 3)),
      plannedDurationMin: 90,
      peopleCount: 2,
      status: OrderStatus.completed,
      urgency: OrderUrgency.current,
      taskTitle: 'Переезд 1-комнатной квартиры',
      taskDescription: 'Полный переезд, упаковка была готова.',
      resultComment: 'Всё прошло хорошо, клиент доволен, лифт работал.',
      coords: const GeoPoint(lat: 55.0388, lng: 82.9287),
      createdAt: base.subtract(const Duration(days: 1, hours: 6)),
    ));
  }

  void _addOrder(Order o) => _orders[o.id] = o;

  Order _require(String id) {
    final o = _orders[id];
    if (o == null) {
      throw const AppFailure(
        code: FailureCode.orderNotFound,
        message: 'Заказ не найден. Возможно, он отменён.',
      );
    }
    return o;
  }

  List<Order> _visibleFeed(FeedFilter f) {
    // 🔴 Лента «Доступные заказы» = только открытые для отклика (status == new).
    // Иначе заказ, который УЖЕ идёт (in_progress), светится как доступный —
    // этот баг пойман глазами на первом же скрине (Карла Маркса, 30).
    // onlyMine — вкладка «Мои»: там нужны все мои живые заказы, включая активные.
    var list = _orders.values
        .where((o) => f.onlyMine ? o.status.isLive : o.status == OrderStatus.new_)
        .toList();
    if (f.urgencies != null && f.urgencies!.isNotEmpty) {
      list = list.where((o) => f.urgencies!.contains(o.urgency)).toList();
    }
    if (f.onlyMine) {
      final mine = _orderTakers.entries
          .where((e) => e.value.any((t) => t.porter.id == _me))
          .map((e) => e.key)
          .toSet();
      list = list.where((o) => mine.contains(o.id)).toList();
    }
    if (f.dateFrom != null) list = list.where((o) => !o.timeStart.isBefore(f.dateFrom!)).toList();
    if (f.dateTo != null) list = list.where((o) => !o.timeStart.isAfter(f.dateTo!)).toList();

    // Срочные сверху, затем по времени начала.
    list.sort((a, b) {
      final byUrgency = (b.urgency.isImmediate ? 1 : 0).compareTo(a.urgency.isImmediate ? 1 : 0);
      if (byUrgency != 0) return byUrgency;
      return a.timeStart.compareTo(b.timeStart);
    });

    if (MockControls.mode == MockMode.empty) return const [];
    return list.map(_withMyResponseStatus).toList();
  }

  /// Матвей, блок 2: в каждом Order из фида приходит мой статус отклика.
  Order _withMyResponseStatus(Order o) {
    final r = _myResponses[o.id];
    if (r == null && o.clientId != _me) return o;
    return Order(
      id: o.id,
      clientIsMe: o.clientId == _me,
      clientId: o.clientId,
      address: o.address,
      timeStart: o.timeStart,
      plannedDurationMin: o.plannedDurationMin,
      peopleCount: o.peopleCount,
      status: o.status,
      urgency: o.urgency,
      taskTitle: o.taskTitle,
      taskDescription: o.taskDescription,
      entrance: o.entrance,
      transport: o.transport,
      clientPhone: o.clientPhone,
      extraComments: o.extraComments,
      clientTariffHint: o.clientTariffHint,
      porterTariffHint: o.porterTariffHint,
      resultComment: o.resultComment,
      coords: o.coords,
      createdAt: o.createdAt,
      myResponseStatus: r?.status,
      feedbackMissed: o.feedbackMissed,
      forceClosed: o.forceClosed,
      isReplacement: o.isReplacement,
    );
  }

  FeedEmptyReason _reasonFor(FeedFilter f) {
    if (MockControls.mode == MockMode.empty) return FeedEmptyReason.noOrders;
    final filterActive = (f.urgencies != null && f.urgencies!.isNotEmpty) ||
        f.onlyMine ||
        f.dateFrom != null ||
        f.dateTo != null;
    if (filterActive) return FeedEmptyReason.filteredOut;
    final anyOpen = _orders.values.any((o) => o.status == OrderStatus.new_);
    return anyOpen ? FeedEmptyReason.allTaken : FeedEmptyReason.noOrders;
  }

  FeedPage _page(FeedFilter f, int limit) => FeedPage(
        items: _visibleFeed(f).take(limit).toList(),
        emptyReason: _reasonFor(f),
      );

  void _emitFeed() {
    if (!_feedCtrl.isClosed) _feedCtrl.add(_visibleFeed(FeedFilter.all));
  }

  StreamController<List<OrderStage>> _stageCtrl(String id) =>
      _stages.putIfAbsent(id, () => StreamController<List<OrderStage>>.broadcast());

  StreamController<OrderStatus> _statusCtrl(String id) =>
      _status.putIfAbsent(id, () => StreamController<OrderStatus>.broadcast());

  StreamController<List<OrderTaker>> _takerCtrl(String id) =>
      _takers.putIfAbsent(id, () => StreamController<List<OrderTaker>>.broadcast());

  StreamController<OrderResponse?> _responseCtrl(String id) =>
      _responses.putIfAbsent(id, () => StreamController<OrderResponse?>.broadcast());

  StreamController<List<ChatMessage>> _chatCtrl(String id) =>
      _chat.putIfAbsent(id, () => StreamController<List<ChatMessage>>.broadcast());

  void _emitStages(String id) {
    final c = _stages[id];
    if (c != null && !c.isClosed) c.add(List.of(_orderStages[id] ?? const []));
  }

  void _emitStatus(String id) {
    final c = _status[id];
    if (c != null && !c.isClosed && _orders[id] != null) c.add(_orders[id]!.status);
  }

  // ───────────────────────────────────────────────────────────
  // 1. АВТОРИЗАЦИЯ И ПРОФИЛЬ
  // ───────────────────────────────────────────────────────────

  @override
  Future<void> sendSmsCode({required String phone}) => _guard(() async {});

  @override
  Future<void> signOut() async {}

  @override
  Future<AuthResult> verifySmsCode({
    required String phone,
    required String code,
    String? fullName,
    String? consentVersion,
  }) =>
      _guard(() async {
        if (code.trim() == '0000') {
          throw const AppFailure(
            code: FailureCode.unauthorized,
            message: 'Неверный код. Запросите новый.',
          );
        }
        return const AuthResult(
          userId: _me,
          roles: {UserRole.porter, UserRole.dispatcher},
          profile: PorterProfile(
            userId: _me,
            name: 'Артём',
            rating: 212,
            completedCount: 131,
            failCount: 2,
            balance: 18400,
            referralsCount: 7,
          ),
        );
      });

  @override
  // Демо-профиль со ВСЕМИ ролями: в mock-режиме хотим видеть все три
  // вкладки shell'а (Лента / Мои заказы / Диспетчер). В live роли приходят
  // из profiles.roles после входа.
  Stream<UserProfile?> watchCurrentUser() async* {
    yield _profile(MockControls.demoRoles);
    yield* MockControls.demoRolesChanges.map(_profile);
  }

  static UserProfile _profile(Set<UserRole> roles) => UserProfile(
        id: _me,
        phone: '+7 913 000-00-00',
        roles: roles,
        name: 'Артём',
        city: MockControls.demoCity,
      );

  @override
  Future<PorterProfile> getPorterProfile({required String userId}) => _guard(() async {
        if (MockControls.mode == MockMode.empty) {
          return PorterProfile(userId: userId, name: 'Артём', rating: 0, completedCount: 0, failCount: 0);
        }
        return const PorterProfile(
          userId: _me,
          name: 'Артём',
          rating: 212,
          completedCount: 131,
          failCount: 2,
          balance: 18400,
          referralCode: 'ARTEM7',
          referralsCount: 7,
        );
      });

  @override
  Future<String?> getReferralCode({required String userId}) => _guard(() async => 'ARTEM7');

  // ───────────────────────────────────────────────────────────
  // 2. ЛЕНТА И ОТКЛИК
  // ───────────────────────────────────────────────────────────

  @override
  Stream<FeedPage> watchFeed({FeedFilter filter = FeedFilter.all, int limit = 30, String? cursor}) async* {
    // Первый кадр — текущее состояние (иначе broadcast-событие уйдёт в никуда).
    await _streamGate();
    yield _page(filter, limit);
    // Дальше — по изменениям (новый заказ, заказ занят, возврат в ленту).
    yield* _feedCtrl.stream.map((_) => _page(filter, limit));
  }

  @override
  Future<Order> getOrder({required String orderId}) => _guard(() async => _require(orderId));

  @override
  Future<OrderResponse> respondToOrder({required String orderId, required int etaMinutes}) =>
      _guard(() async {
        final order = _require(orderId);

        if (!order.isOpenForResponse) {
          throw Failures.orderAlreadyTaken();
        }
        if (etaMinutes < 1 || etaMinutes > 240) {
          throw Failures.validation('etaMinutes', 'Укажите реальное время в пути, от 1 до 240 минут.');
        }
        if (MockControls.simulateRaceCondition) {
          // Гонка: пока грузчик вводил ETA, заказ одобрили другому.
          throw Failures.orderAlreadyTaken();
        }
        if (_myResponses.containsKey(orderId) &&
            _myResponses[orderId]!.status == ResponseStatus.pending) {
          throw const AppFailure(
            code: FailureCode.responseAlreadyExists,
            message: 'Вы уже откликнулись на этот заказ. Ждите решения диспетчера.',
          );
        }

        final r = OrderResponse(
          id: 'resp-${orderId.hashCode.abs()}',
          orderId: orderId,
          porterId: _me,
          etaMinutes: etaMinutes,
          status: ResponseStatus.pending,
          createdAt: _now(),
        );
        _myResponses[orderId] = r;
        _emitFeed(); // чип «отклик отправлен» на карточке без pull-to-refresh

        // Имитируем диспетчера: решение через 6 секунд (или автоотклонение по таймауту).
        if (!MockControls.simulateDispatcher) return r;
        Future.delayed(const Duration(seconds: 6), () {
          final cur = _myResponses[orderId];
          if (cur == null || cur.status != ResponseStatus.pending) return;
          final approved = _rnd.nextBool();
          _myResponses[orderId] = OrderResponse(
            id: cur.id,
            orderId: orderId,
            porterId: _me,
            etaMinutes: cur.etaMinutes,
            status: approved ? ResponseStatus.approved : ResponseStatus.declined,
            createdAt: cur.createdAt,
            decidedAt: _now(),
            decidedBy: 'dispatcher-90182825',
            declineReason: approved ? null : 'Бригада уже собрана',
          );
          _responseCtrl(orderId).add(_myResponses[orderId]);
          _emitFeed(); // решение диспетчера тоже меняет карточку в ленте
        });

        _responseCtrl(orderId).add(r);
        return r;
      });

  @override
  Future<void> cancelResponse({required String responseId}) => _guard(() async {
        _myResponses.removeWhere((_, r) => r.id == responseId);
      });

  @override
  Stream<OrderResponse?> watchMyResponse({required String orderId}) async* {
    await _streamGate();
    yield _myResponses[orderId];
    yield* _responseCtrl(orderId).stream;
  }

  // ───────────────────────────────────────────────────────────
  // 3. ЭТАПЫ
  // ───────────────────────────────────────────────────────────

  @override
  Stream<List<OrderStage>> watchOrderStages({required String orderId}) async* {
    await _streamGate();
    yield List.of(_orderStages[orderId] ?? const []);
    yield* _stageCtrl(orderId).stream;
  }

  @override
  Future<StageResult> setStage({
    required String orderId,
    required OrderStageType stage,
    DateTime? clientTime,
    GeoPoint? location,
  }) =>
      _guard(() async {
        final order = _require(orderId);
        if (!order.status.isLive) throw Failures.orderClosed();

        // 🔴 Этапы в БД хранятся ПО ГРУЗЧИКАМ — считаем только свои,
        // иначе чужой «Выехал» разблокирует мне «На месте».
        final done = (_orderStages[orderId] ?? const [])
            .where((s) => s.porterId == _me)
            .map((s) => s.stage)
            .toList();
        final takers = _orderTakers[orderId] ?? const [];
        final meTaker = takers.where((t) => t.porter.id == _me).toList();
        final isLead = meTaker.isNotEmpty && meTaker.first.isLead;
        final inBrigade = takers.isEmpty || meTaker.isNotEmpty;

        // Полная валидация — та же, что и на бэке. См. order_state_machine.dart.
        final decision = OrderFlowMachine.decide(
          stage: stage,
          order: order,
          done: done,
          isLead: isLead,
          inBrigade: inBrigade,
          now: _now(),
          finishedAt: _finishedAt(orderId),
        );

        if (!decision.allowed) {
          throw AppFailure(
            code: _mapBlock(decision.blockReason),
            message: decision.blockedText,
          );
        }

        final at = _now();
        final list = _orderStages.putIfAbsent(orderId, () => []);
        list.add(OrderStage(
          orderId: orderId,
          porterId: _me,
          stage: stage,
          at: at,
          porterName: 'Артём',
          late: decision.late,
        ));
        _emitStages(orderId);

        // 🔴 Пропуск утреннего дедлайна: −5 рейтинг, +1 fail, заказ в ленту.
        if (decision.late && stage == OrderStageType.woke) {
          final o = _orders[orderId]!;
          _orders[orderId] = Order(
            id: o.id,
            clientId: o.clientId,
            address: o.address,
            timeStart: o.timeStart,
            plannedDurationMin: o.plannedDurationMin,
            peopleCount: o.peopleCount,
            status: OrderStatus.new_,
            urgency: o.urgency,
            taskTitle: o.taskTitle,
            taskDescription: o.taskDescription,
            entrance: o.entrance,
            createdAt: o.createdAt,
          );
          _orderStages.remove(orderId);
          _orderTakers.remove(orderId);
          _emitStatus(orderId);
          _emitFeed();
          return StageResult(
            stage: stage,
            at: at,
            ratingDelta: -BizRules.morningLatePenalty,
            late: true,
            orderReturnedToFeed: true,
            message: 'Дедлайн пропущен: −5 к рейтингу, заказ возвращён в ленту.',
          );
        }

        // 🔒 Ориентир («Номер подъ-да») открывается старшему ТОЛЬКО после `started`.
        if (stage == OrderStageType.started && order.status == OrderStatus.approved) {
          _orders[orderId] = _copyStatus(order, OrderStatus.inProgress);
          _emitStatus(orderId);
        }

        return StageResult(
          stage: stage,
          at: at,
          ratingDelta: 0,
          late: decision.late,
        );
      }, errorEveryN: 0); // этапы не роняем случайно — иначе QA этапов невозможен

  FailureCode _mapBlock(StageBlockReason? r) => switch (r) {
        StageBlockReason.leadOnly => FailureCode.leadOnly,
        StageBlockReason.wrongStageOrder => FailureCode.wrongStageOrder,
        StageBlockReason.alreadyDone => FailureCode.stageAlreadySet,
        StageBlockReason.orderNotApproved => FailureCode.orderNotApproved,
        StageBlockReason.orderNotLive => FailureCode.orderClosed,
        StageBlockReason.notMorningOrder => FailureCode.notMorningOrder,
        StageBlockReason.feedbackTimeoutExpired => FailureCode.feedbackWindowClosed,
        _ => FailureCode.forbidden,
      };

  DateTime? _stageAt(String orderId, OrderStageType stage) {
    for (final s in _orderStages[orderId] ?? const <OrderStage>[]) {
      if (s.stage == stage) return s.at;
    }
    return null;
  }

  DateTime? _finishedAt(String orderId) {
    final list = _orderStages[orderId] ?? const [];
    for (final s in list) {
      if (s.stage == OrderStageType.finished) return s.at;
    }
    return null;
  }

  @override
  Future<StageAvailability> getStageAvailability({required String orderId}) => _guard(() async {
        final order = _require(orderId);
        final done = (_orderStages[orderId] ?? const [])
            .where((st) => st.porterId == _me)
            .map((st) => st.stage)
            .toList();
        final takers = _orderTakers[orderId] ?? const [];
        final me = takers.where((t) => t.porter.id == _me).toList();
        final now = _now();

        final available = <OrderStageType>[];
        for (final s in OrderStageType.values) {
          final d = OrderFlowMachine.decide(
            stage: s,
            order: order,
            done: done,
            isLead: me.isNotEmpty && me.first.isLead,
            inBrigade: takers.isEmpty || me.isNotEmpty,
            now: now,
            finishedAt: _finishedAt(orderId),
          );
          if (d.allowed) available.add(s);
        }

        final next = OrderFlowMachine.nextExpected(done, morning: order.isMorning);
        final penalty = next == null ? 0 : OrderFlowMachine.penaltyFor(next, order, now);

        // Причина блока — из домена (та же, что в live отдаёт RPC Матвея):
        // до одобрения диспетчером этапы заблокированы с человекочитаемым текстом.
        String? blocked;
        if (next == null) {
          blocked = 'Все этапы завершены';
        } else if (!available.contains(next)) {
          final d = OrderFlowMachine.decide(
            stage: next,
            order: order,
            done: done,
            isLead: me.isNotEmpty && me.first.isLead,
            inBrigade: takers.isEmpty || me.isNotEmpty,
            now: now,
            finishedAt: _finishedAt(orderId),
          );
          blocked = d.blockReason?.describe();
        }

        return StageAvailability(
          available: available,
          isLead: me.isNotEmpty && me.first.isLead,
          nextRequired: next,
          wokeDeadline: order.wokeDeadline,
          departedDeadline: order.departedDeadline,
          isLate: penalty > 0,
          penaltyIfPressedNow: penalty,
          blockedReason: blocked,
          feedbackDeadline: done.contains(OrderStageType.finished) &&
                  !done.contains(OrderStageType.feedback)
              ? _finishedAt(orderId)?.add(BizRules.feedbackTimeout)
              : null,
        );
      });

  @override
  Future<void> submitDelayReason({required String orderId, required String reason}) =>
      _guard(() async {
        if (reason.trim().length < 5) {
          throw Failures.validation('reason', 'Опишите причину задержки подробнее.');
        }
        _appendChat(orderId, 'Диспетчеру отправлена причина задержки: $reason',
            role: UserRole.porter);
      });

  // ───────────────────────────────────────────────────────────
  // 4. БРИГАДА И СТАРШИЙ
  // ───────────────────────────────────────────────────────────

  @override
  Stream<PorterBrief?> watchLead({required String orderId}) {
    return _takerCtrl(orderId).stream.map((list) {
      for (final t in list) {
        if (t.isLead) return t.porter;
      }
      return null;
    });
  }

  @override
  Stream<List<OrderTaker>> watchOrderTakers({required String orderId}) async* {
    await _streamGate();
    yield List.of(_orderTakers[orderId] ?? const []);
    yield* _takerCtrl(orderId).stream;
  }

  // ───────────────────────────────────────────────────────────
  // 5. ЗАКРЫТИЕ
  // ───────────────────────────────────────────────────────────

  @override
  Future<OrderCompletion> finishOrder({
    required String orderId,
    required bool wentWell,
    String? resultComment,
  }) =>
      _guard(() async {
        final order = _require(orderId);
        final finishedAt = _finishedAt(orderId);
        if (finishedAt == null) {
          throw const AppFailure(
            code: FailureCode.wrongStageOrder,
            message: 'Сначала отметьте этап «Закончили».',
          );
        }
        final now = _now();
        if (now.isAfter(finishedAt.add(BizRules.feedbackTimeout))) {
          throw Failures.feedbackWindowClosed();
        }

        // 🔴 Матвей 12.09: minutesWorked = finished − started (НЕ от arrived и не от timeStart).
      final startedAt = _stageAt(orderId, OrderStageType.started);
      if (startedAt == null) {
        throw Failures.wrongStageOrder();
      }
      final minutes = now.difference(startedAt).inMinutes;
        final hours = BizRules.hoursFromMinutes(minutes);
        final total = BizRules.totalHours(minutes, order.peopleCount);
        final takers = _orderTakers[orderId] ?? const [];
        final me = takers.where((t) => t.porter.id == _me).toList();
        final isLead = me.isNotEmpty && me.first.isLead;

        final o = _orders[orderId]!;
        _orders[orderId] = Order(
          id: o.id,
          clientId: o.clientId,
          address: o.address,
          timeStart: o.timeStart,
          plannedDurationMin: o.plannedDurationMin,
          peopleCount: o.peopleCount,
          status: OrderStatus.completed,
          urgency: o.urgency,
          taskTitle: o.taskTitle,
          taskDescription: o.taskDescription,
          entrance: o.entrance,
          transport: o.transport,
          clientPhone: o.clientPhone,
          extraComments: o.extraComments,
          clientTariffHint: o.clientTariffHint,
          porterTariffHint: o.porterTariffHint,
          resultComment: resultComment,
          coords: o.coords,
          createdAt: o.createdAt,
        );

        _emitStatus(orderId);
        _emitFeed();

        return OrderCompletion(
          orderId: orderId,
          minutesWorked: minutes,
          hours: hours,
          totalHours: total,
          ratingDelta: isLead ? BizRules.ratingOnCompleteLead : BizRules.ratingOnComplete,
          finishedAt: now,
          moneyDelta: null, // 🔴 Матвей 12.09: денег в MVP нет, всегда null.
        );
      }, errorEveryN: 0);

  @override
  Stream<OrderStatus> watchOrderStatus({required String orderId}) async* {
    await _streamGate();
    yield _require(orderId).status;
    yield* _statusCtrl(orderId).stream;
  }

  // ───────────────────────────────────────────────────────────
  // 6. ОТЗЫВЫ
  // ───────────────────────────────────────────────────────────

  @override
  Future<void> submitClientReview({required String orderId, required int rating, String? text}) =>
      _guard(() async {
        if (rating < 1 || rating > 5) {
          throw Failures.validation('rating', 'Оценка — от 1 до 5.');
        }
        final o = _require(orderId);
        if (o.status != OrderStatus.completed) {
          throw const AppFailure(
            code: FailureCode.reviewNotAllowed,
            message: 'Оставить отзыв можно только после завершения заказа.',
          );
        }
      });

  @override
  Future<List<Review>> getPorterReviews({required String porterId, int limit = 20}) =>
      _guard(() async {
        if (MockControls.mode == MockMode.empty) return const [];
        final base = _now();
        return List.generate(min(5, limit), (i) {
          final r = 5 - (i % 3);
          return Review(
            id: 'rev-$i',
            orderId: 'ord-300${i + 1}',
            clientId: _client,
            porterId: porterId,
            rating: r,
            text: switch (r) {
              5 => 'Приехали вовремя, работали быстро и аккуратно. Всё целое.',
              4 => 'Хорошо отработали, немного задержались на погрузке.',
              _ => 'Опоздали на 20 минут, но работу доделали.',
            },
            createdAt: base.subtract(Duration(days: i + 1)),
          );
        });
      });

  @override
  Stream<int> watchPendingReviewCount() => Stream.value(
        MockControls.mode == MockMode.empty ? 0 : 1,
      );

  // ───────────────────────────────────────────────────────────
  // 7. ЧАТ
  // ───────────────────────────────────────────────────────────

  void _appendChat(
    String orderId,
    String text, {
    UserRole role = UserRole.dispatcher,
    String? attachmentUrl,
  }) {
    final list = _chats.putIfAbsent(orderId, () => []);
    list.add(ChatMessage(
      id: 'm-${list.length + 1}',
      orderId: orderId,
      authorId: role == UserRole.porter ? _me : 'dispatcher-90182825',
      authorName: role == UserRole.porter ? 'Артём' : 'Диспетчер',
      authorRole: role,
      text: text,
      sentAt: _now(),
      isMine: role == UserRole.porter,
      attachmentUrl: attachmentUrl,
    ));
    final c = _chat[orderId];
    if (c != null && !c.isClosed) c.add(List.of(list));
  }

  @override
  Stream<List<ChatMessage>> watchOrderChat({required String orderId, int limit = 50}) async* {
    await _streamGate();
    yield List.of(_chats[orderId] ?? const []);
    yield* _chatCtrl(orderId).stream;
  }

  @override
  Future<void> sendOrderChatMessage({
    required String orderId,
    required String text,
    String? attachmentUrl,
  }) =>
      _guard(() async {
        if (text.trim().isEmpty && attachmentUrl == null) {
          throw Failures.validation('text', 'Пустое сообщение.');
        }
        _appendChat(orderId, text.trim(), role: UserRole.porter,
            attachmentUrl: attachmentUrl);
      }, errorEveryN: 0);

  // ───────────────────────────────────────────────────────────
  // 8. ЗАКАЗЧИК
  // ───────────────────────────────────────────────────────────

  @override
  Future<Order> createOrder(CreateOrderRequest req) => _guard(() async {
        if (req.peopleCount < 1 || req.peopleCount > 20) {
          throw Failures.validation('peopleCount', 'Количество грузчиков — от 1 до 20.');
        }
        if (req.plannedDurationMin < 30) {
          throw Failures.validation('plannedDurationMin', 'Минимальная длительность — 30 минут.');
        }
        if (req.timeStart.isBefore(_now())) {
          throw Failures.validation('timeStart', 'Время начала уже прошло.');
        }

        final id = 'ord-${4000 + _orders.length}';
        final o = Order(
          id: id,
          // Баг-репорт 25.09: грузчик может создать заявку как заказчик —
          // clientId = текущий демо-пользователь, чтобы работали правила
          // «не откликаться на свою» и «не оценивать свою работу».
          clientId: _me,
          address: req.address,
          timeStart: req.timeStart,
          plannedDurationMin: req.plannedDurationMin,
          peopleCount: req.peopleCount,
          status: OrderStatus.new_,
          urgency: req.urgency,
          taskTitle: req.taskTitle,
          taskDescription: req.taskDescription,
          entrance: req.entrance,
          transport: req.transport,
          clientPhone: req.phone,
          extraComments: req.extraComments,
          clientTariffHint: req.tariff,
          coords: req.coords,
          createdAt: _now(),
        );
        _addOrder(o);
        _emitFeed();
        return o;
      });

  @override
  Future<List<AddressSuggestion>> searchAddress({required String query}) => _guard(() async {
        if (query.trim().length < 3) return const [];
        if (MockControls.mode == MockMode.empty) return const [];
        const streets = ['Ленина', 'Кирова', 'Советская', 'Гоголя', 'Станционная', 'Красный проспект'];
        return streets
            .where((s) => s.toLowerCase().contains(query.trim().toLowerCase()) || query.trim().length > 2)
            .take(6)
            .map((s) => AddressSuggestion(
                  title: 'ул. $s',
                  fullAddress: 'г. Новосибирск, ул. $s',
                  coords: GeoPoint(lat: 55.02 + _rnd.nextDouble() * 0.08, lng: 82.90 + _rnd.nextDouble() * 0.08),
                ))
            .toList();
      });

  @override
  Future<TariffQuote> quoteOrder({
    required int peopleCount,
    required int plannedDurationMin,
    required OrderUrgency urgency,
    TransportType transport = TransportType.none,
  }) =>
      _guard(() async {
        // Формула — коп RPC quote_order (Матвей, 12.09): см. domain/pricing.dart.
        final t = computeTariff(
          peopleCount: peopleCount,
          plannedDurationMin: plannedDurationMin,
          urgency: urgency,
          transport: transport,
        );
        return TariffQuote(
          price: t.total,
          currency: 'RUB',
          hours: (t.plannedHours * peopleCount).toDouble(),
          breakdown: t.lines.map((l) => QuoteLine(label: l.$1, amount: l.$2)).toList(),
        );
      });

  @override
  Future<void> cancelOrder({required String orderId, String? reason}) => _guard(() async {
        final o = _require(orderId);
        if (o.status.isTerminal) throw Failures.orderClosed();
        _orders[orderId] = _copyStatus(o, OrderStatus.cancelled);
        _emitStatus(orderId);
        _emitFeed();
      });

  @override
  Stream<List<Order>> watchMyClientOrders() async* {
    List<Order> mine() {
      final list = _orders.values
          .where((o) => o.clientId == _client || o.clientId == _me)
          .toList()
        ..sort((a, b) => b.timeStart.compareTo(a.timeStart));
      return MockControls.mode == MockMode.empty ? const <Order>[] : list;
    }

    await _streamGate();
    yield mine();
    yield* _feedCtrl.stream.map((_) => mine());
  }

  // ───────────────────────────────────────────────────────────
  // 9. ДИСПЕТЧЕР (для сквозного QA)
  // ───────────────────────────────────────────────────────────

  @override
  Future<List<Order>> myWorkOrders() async {
    final ids = _orderTakers.entries
        .where((e) => e.value.any((t) => t.porter.id == _me))
        .map((e) => e.key)
        .toSet();
    return _orders.values.where((o) => ids.contains(o.id)).toList();
  }

  @override
  Future<List<OrderResponse>> getPendingResponses({required String orderId}) => _guard(() async {
        final r = _myResponses[orderId];
        if (r == null || r.status != ResponseStatus.pending) return const <OrderResponse>[];
        return [
          OrderResponse(
            id: r.id,
            orderId: r.orderId,
            porterId: r.porterId,
            etaMinutes: r.etaMinutes,
            status: r.status,
            createdAt: r.createdAt,
            decidedAt: r.decidedAt,
            decidedBy: r.decidedBy,
            declineReason: r.declineReason,
            porterName: 'Артём',
          ),
        ];
      });

  @override
  Stream<List<Order>> watchDispatcherOrders() async* {
    List<Order> live() {
      final list = _orders.values
          .where((o) => const [
                OrderStatus.new_,
                OrderStatus.approved,
                OrderStatus.inProgress,
              ].contains(o.status))
          .toList()
        ..sort((a, b) => b.createdAt!.compareTo(a.createdAt!));
      return MockControls.mode == MockMode.empty ? const <Order>[] : list;
    }

    await _streamGate();
    yield live();
    yield* _feedCtrl.stream.map((_) => live());
  }

  @override
  Future<void> approveResponse({required String responseId}) => _guard(() async {
        for (final e in _myResponses.entries) {
          if (e.value.id != responseId) continue;
          final cur = e.value;
          _myResponses[e.key] = OrderResponse(
            id: cur.id,
            orderId: cur.orderId,
            porterId: cur.porterId,
            etaMinutes: cur.etaMinutes,
            status: ResponseStatus.approved,
            createdAt: cur.createdAt,
            decidedAt: _now(),
            decidedBy: 'dispatcher-90182825',
          );
          _responseCtrl(e.key).add(_myResponses[e.key]);

          // Заказ переходит в approved, я — в бригаде.
          final o = _orders[e.key];
          if (o != null) {
            _orders[e.key] = _copyStatus(o, OrderStatus.approved);
            final takers = _orderTakers.putIfAbsent(e.key, () => []);
            if (!takers.any((t) => t.porter.id == _me)) {
              takers.add(OrderTaker(
                orderId: e.key,
                porter: const PorterBrief(id: _me, name: 'Артём', rating: 212, completedCount: 131),
                isLead: takers.isEmpty,
                etaMinutes: cur.etaMinutes,
              ));
              _takerCtrl(e.key).add(List.of(takers));
            }
            _emitStatus(e.key);
            _emitFeed();
          }
          return;
        }
        throw Failures.responseExpired();
      }, errorEveryN: 0);

  @override
  Future<void> declineResponse({required String responseId}) => _guard(() async {
        for (final e in _myResponses.entries) {
          if (e.value.id != responseId) continue;
          final cur = e.value;
          _myResponses[e.key] = OrderResponse(
            id: cur.id,
            orderId: cur.orderId,
            porterId: cur.porterId,
            etaMinutes: cur.etaMinutes,
            status: ResponseStatus.declined,
            createdAt: cur.createdAt,
            decidedAt: _now(),
            declineReason: 'Бригада уже собрана',
          );
          _responseCtrl(e.key).add(_myResponses[e.key]);
          return;
        }
        throw Failures.responseExpired();
      }, errorEveryN: 0);

  @override
  Future<void> assignLead({required String orderId, required String porterId}) => _guard(() async {
        final takers = _orderTakers.putIfAbsent(orderId, () => []);
        final updated = takers
            .map((t) => OrderTaker(
                  orderId: t.orderId,
                  porter: t.porter.copyWith(isLead: t.porter.id == porterId),
                  isLead: t.porter.id == porterId,
                  etaMinutes: t.etaMinutes,
                  joinedAt: t.joinedAt,
                ))
            .toList();
        _orderTakers[orderId] = updated;
        _takerCtrl(orderId).add(updated);
      }, errorEveryN: 0);

  @override
  Future<void> forceCloseOrder({required String orderId, required String comment}) =>
      _guard(() async {
        final o = _require(orderId);
        final closed = Order(
          id: o.id,
          clientId: o.clientId,
          address: o.address,
          timeStart: o.timeStart,
          plannedDurationMin: o.plannedDurationMin,
          peopleCount: o.peopleCount,
          status: OrderStatus.completed,
          urgency: o.urgency,
          taskTitle: o.taskTitle,
          taskDescription: o.taskDescription,
          entrance: o.entrance,
          resultComment: comment,
          createdAt: o.createdAt,
          forceClosed: true,
        );
        _orders[orderId] = closed;
        _emitStatus(orderId); // 🔴 экран active у бригады должен закрыться сам
        _emitFeed();
      }, errorEveryN: 0);

  @override
  Future<void> findReplacement({required String orderId}) => _guard(() async {
        final o = _require(orderId);
        _orders[orderId] = Order(
          id: o.id,
          clientId: o.clientId,
          address: o.address,
          timeStart: o.timeStart,
          plannedDurationMin: o.plannedDurationMin,
          peopleCount: o.peopleCount,
          status: OrderStatus.new_,
          urgency: OrderUrgency.replacement,
          taskTitle: o.taskTitle,
          taskDescription: o.taskDescription,
          createdAt: _now(),
          isReplacement: true,
        );
        _emitFeed();
      }, errorEveryN: 0);

  @override
  Stream<List<PorterLocation>> watchPorterLocations({required String orderId}) {
    return Stream.periodic(const Duration(seconds: 10), (i) {
      final takers = _orderTakers[orderId] ?? const [];
      return takers
          .map((t) => PorterLocation(
                porterId: t.porter.id,
                porterName: t.porter.name,
                point: GeoPoint(
                  lat: 55.03 + (i % 5) * 0.001,
                  lng: 82.92 + (i % 3) * 0.001,
                ),
                at: _now(),
              ))
          .toList();
    });
  }

  // ───────────────────────────────────────────────────────────

  Order _copyStatus(Order o, OrderStatus s) => Order(
        id: o.id,
        clientId: o.clientId,
        address: o.address,
        timeStart: o.timeStart,
        plannedDurationMin: o.plannedDurationMin,
        peopleCount: o.peopleCount,
        status: s,
        urgency: o.urgency,
        taskTitle: o.taskTitle,
        taskDescription: o.taskDescription,
        entrance: o.entrance,
        transport: o.transport,
        clientPhone: o.clientPhone,
        extraComments: o.extraComments,
        clientTariffHint: o.clientTariffHint,
        porterTariffHint: o.porterTariffHint,
        resultComment: o.resultComment,
        coords: o.coords,
        createdAt: o.createdAt,
        forceClosed: o.forceClosed,
        isReplacement: o.isReplacement,
      );

  @override
  Future<ReferralInfo> getMyReferralInfo() => _guard(() async {
        if (MockControls.mode == MockMode.empty) {
          return const ReferralInfo(code: null, invited: []);
        }
        return const ReferralInfo(
          code: 'ARTEM26',
          invited: [
            ReferralEntry(
              name: 'Сергей П.',
              phoneMasked: '+7 ••• •••-••-14',
              status: ReferralStatus.counted,
            ),
            ReferralEntry(
              name: 'Марат К.',
              phoneMasked: '+7 ••• •••-••-02',
              status: ReferralStatus.fresh,
            ),
          ],
        );
      }, errorEveryN: 0);

  @override
  Future<String> ensureReferralCode() => _guard(() async => 'ARTEM26',
      errorEveryN: 0);

  @override
  Future<String> uploadOrderPhoto({
    required String orderId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    return 'mock://orders/$orderId/$fileName';
  }

  @override
  Future<String?> resolveAttachmentUrl(String attachmentUrl) async =>
      attachmentUrl;

  // ── 12. ЗАЯВКА НА РАБОТУ ГРУЗЧИКОМ ─────────────────────────
  // Одна чужая заявка уже ждёт диспетчера, чтобы в демо было что одобрять.
  final List<WorkerApplication> _workerApps = [
    WorkerApplication(
      id: 'wa-demo-1',
      userId: 'client-sergey',
      fullName: 'Сергей Ковалёв',
      city: 'Новосибирск',
      experience: 'Два года грузчиком на складе, есть опыт квартирных переездов.',
      status: WorkerApplicationStatus.pending,
      phone: '+7 913 555-12-34',
      createdAt: DateTime.now().subtract(const Duration(hours: 3)),
    ),
  ];

  @override
  Future<WorkerApplication?> myWorkerApplication() => _guard(() async {
        final mine = _workerApps.where((a) => a.userId == _me).toList();
        return mine.isEmpty ? null : mine.last;
      });

  @override
  Future<void> submitWorkerApplication({
    required String fullName,
    required String city,
    String? experience,
  }) =>
      _guard(() async {
        if (MockControls.demoRoles.contains(UserRole.porter)) {
          throw Failures.validation('server', 'Вы уже работаете грузчиком.');
        }
        if (_workerApps.any((a) =>
            a.userId == _me && a.status == WorkerApplicationStatus.pending)) {
          throw Failures.validation('server', 'Заявка уже на рассмотрении.');
        }
        if (fullName.trim().length < 2) {
          throw Failures.validation('fullName', 'Укажите имя и фамилию.');
        }
        if (city.trim().length < 2) {
          throw Failures.validation('city', 'Укажите город.');
        }
        _workerApps.add(WorkerApplication(
          id: 'wa-${_workerApps.length + 1}',
          userId: _me,
          fullName: fullName.trim(),
          city: city.trim(),
          experience: (experience?.trim().isEmpty ?? true) ? null : experience!.trim(),
          status: WorkerApplicationStatus.pending,
          phone: '+7 913 000-00-00',
          createdAt: DateTime.now(),
        ));
      });

  @override
  Future<List<WorkerApplication>> pendingWorkerApplications() =>
      _guard(() async => _workerApps
          .where((a) => a.status == WorkerApplicationStatus.pending)
          .toList());

  @override
  Future<void> reviewWorkerApplication({
    required String id,
    required bool approve,
    String? reason,
  }) =>
      _guard(() async {
        final i = _workerApps.indexWhere((a) => a.id == id);
        if (i < 0 || _workerApps[i].status != WorkerApplicationStatus.pending) {
          throw Failures.validation('server', 'Заявка уже рассмотрена.');
        }
        final a = _workerApps[i];
        _workerApps[i] = WorkerApplication(
          id: a.id,
          userId: a.userId,
          fullName: a.fullName,
          city: a.city,
          experience: a.experience,
          phone: a.phone,
          createdAt: a.createdAt,
          status: approve
              ? WorkerApplicationStatus.approved
              : WorkerApplicationStatus.rejected,
          rejectReason: approve ? null : reason,
        );
        if (approve && a.userId == _me) {
          MockControls.setDemoRoles({...MockControls.demoRoles, UserRole.porter});
        }
      });

  @override
  Future<void> updateMyCity(String city) => _guard(() async {
        MockControls.demoCity = city;
        // Перевыпустить профиль подписчикам watchCurrentUser.
        MockControls.setDemoRoles(MockControls.demoRoles);
      });

  @override
  Future<void> refreshCurrentUser() async {}

  Future<void> dispose() async {
    await _feedCtrl.close();
    for (final c in _stages.values) {
      await c.close();
    }
    for (final c in _status.values) {
      await c.close();
    }
    for (final c in _takers.values) {
      await c.close();
    }
    for (final c in _responses.values) {
      await c.close();
    }
    for (final c in _chat.values) {
      await c.close();
    }
  }
}
