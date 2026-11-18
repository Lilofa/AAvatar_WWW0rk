/// ЭКРАН АКТИВНОГО ЗАКАЗА (зона Артёма).
///
/// Источник истины по доступным кнопкам — БЭКЕНД (RPC get_stage_availability,
/// Матвей 12.09): экран только рисует то, что пришло, и предупреждает ДО нажатия.
/// Локальные правила (домен) используются исключительно как fallback на офлайн
/// и для виджет-тестов; расхождение с бэком поймает приёмка живым прогоном.
///
/// Что здесь есть по решениям команды:
///  - таймлайн этапов woke → departed → arrived → started → finished → feedback;
///  - «Старший назначается…» до события lead_assigned (стрим бригады);
///  - предупреждение о штрафе ДО нажатия (penalty_if_pressed_now / warning);
///  - ориентир «Номер подъ-да» ТОЛЬКО после started;
///  - таймер окна обратной связи 5 минут (feedback_timeout);
///  - баннер овертайма план+15 и причина задержки для старшего;
///  - офлайн: неудачный этап запоминается и досылается кнопкой (очередь MVP).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../data/orders_repository.dart';
import '../../order_chat/presentation/order_chat_screen.dart';
import '../../order_flow/domain/enums.dart';
import '../../order_flow/domain/models.dart';
import '../../order_flow/domain/order_state_machine.dart';
import '../../order_review/presentation/order_review_screen.dart';

class OrderActiveScreen extends StatefulWidget {
  const OrderActiveScreen({
    super.key,
    required this.orderId,
    required this.repository,
    this.nowProvider = _defaultNow,
    this.onClosed,
  });

  final String orderId;
  final OrdersRepository repository;

  /// Инжектируемые часы: виджет-тестам нужна детерминированность.
  final DateTime Function() nowProvider;

  /// Вызывается, когда заказ закрыт (force_closed / completed) — чтобы увести экран.
  final VoidCallback? onClosed;

  static DateTime _defaultNow() => DateTime.now();

  @override
  State<OrderActiveScreen> createState() => _OrderActiveScreenState();
}

class _OrderActiveScreenState extends State<OrderActiveScreen> {
  final _subs = <StreamSubscription<dynamic>>[];
  Timer? _tick;

  Order? _order;
  String? _myId;
  Set<UserRole> _myRoles = const {};
  List<OrderStage> _stages = const [];
  StageAvailability _avail = const StageAvailability(
    available: [],
    isLead: false,
    isLate: false,
    penaltyIfPressedNow: 0,
  );
  PorterBrief? _lead;
  List<OrderTaker> _takers = const [];
  AppFailure? _loadError;
  StageResult? _lastResult;
  OrderCompletion? _completion;
  bool _busy = false;

  // MVP-очередь офлайна: один.pending-экшн с досылом.
  OrderStageType? _offlinePending;

  // feedback form
  bool? _wentWell;
  final _commentCtrl = TextEditingController();

  DateTime get _now => widget.nowProvider();

  @override
  void initState() {
    super.initState();
    _subscribe();
    _tick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
      _refreshAvailability();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _commentCtrl.dispose();
    super.dispose();
  }

  void _subscribe() {
    _subs.add(
      widget.repository.watchCurrentUser().listen((u) {
        if (mounted) {
          setState(() {
            _myId = u?.id;
            _myRoles = u?.roles ?? const {};
          });
        }
      }),
    );
    _subs.add(
      widget.repository.watchOrderStatus(orderId: widget.orderId).listen(
        (status) {
          if (!mounted) return;
          setState(() {});
          if (status == OrderStatus.completed ||
              status == OrderStatus.cancelled) {
            widget.onClosed?.call();
          }
          _refreshAvailability();
        },
        onError: (Object e) => _fail(e),
      ),
    );
    _subs.add(
      widget.repository.watchOrderStages(orderId: widget.orderId).listen(
        (stages) {
          if (!mounted) return;
          setState(() => _stages = stages);
          _refreshAvailability();
        },
        onError: (Object e) => _fail(e),
      ),
    );
    _subs.add(
      widget.repository.watchOrderTakers(orderId: widget.orderId).listen(
        (takers) {
          if (!mounted) return;
          setState(() => _takers = takers);
          PorterBrief? lead;
          for (final t in takers) {
            if (t.isLead) lead = t.porter;
          }
          setState(() => _lead = lead);
        },
        onError: (Object e) => _fail(e),
      ),
    );
    _subs.add(
      widget.repository.watchCurrentUser().listen(
            (u) => mounted ? setState(() => _myPorterId = u?.id) : null,
          ),
    );
    widget.repository.getOrder(orderId: widget.orderId).then(
          (o) => mounted ? setState(() => _order = o) : null,
          onError: (Object e) => _fail(e),
        );
    _refreshAvailability();
  }

  void _fail(Object e) {
    if (!mounted) return;
    setState(() => _loadError = e is AppFailure ? e : Failures.unknown(e));
  }

  Future<void> _refreshAvailability() async {
    try {
      final a =
          await widget.repository.getStageAvailability(orderId: widget.orderId);
      if (mounted) setState(() => _avail = a);
    } catch (e) {
      _fail(e);
    }
  }

  bool get _isLead => _avail.isLead;

  List<OrderStageType> get _myDone => _stages
      .where((s) => s.porterId == _meId)
      .map((s) => s.stage)
      .toList(growable: false);

  // Мок и бэк отдают мой id через профиль; для экрана достаточно совпадения
  // с портретом в takers. Здесь — заглушка до входа Supabase-сессии.
  String get _meId => _myPorterId ?? '';
  String? _myPorterId;

  bool get _startedDone =>
      _stages.any((s) => s.stage == OrderStageType.started);
  bool get _finishedDone =>
      _stages.any((s) => s.stage == OrderStageType.finished);

  @override
  Widget build(BuildContext context) {
    if (_loadError != null && _order == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Заказ')),
        body: StateView(
          icon: Icons.cloud_off_outlined,
          color: AppColors.error,
          body: Text(_loadError!.message),
          action: _loadError!.showRetry
              ? FilledButton(
                  onPressed: _subscribe, child: const Text('Повторить'))
              : null,
        ),
      );
    }

    final order = _order;
    if (order == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(order.taskTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton.filledTonal(
              key: const Key('active_chat_btn'),
              tooltip: 'Чат по заказу',
              icon: const Icon(Icons.chat_bubble_outline),
              onPressed: () => _openChat(order),
            ),
          ),
        ],
      ),
      // Column, а не ListView: блоков мало, а ленивый список не строит
      // нижние (кнопка этапа, обратная связь), пока до них не доскроллили.
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _summaryCard(order),
            if (order.status == OrderStatus.completed &&
                _myId != null &&
                _myId == order.clientId &&
                // баг-репорт 25.09: грузчик не оценивает заказ, в котором работал
                !_takers.any((t) => t.porter.id == _myId))
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: FilledButton.icon(
                  key: const Key('active_review_btn'),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => OrderReviewScreen(
                      repository: widget.repository,
                      orderId: widget.orderId,
                    ),
                  )),
                  icon: const Icon(Icons.star_rounded, size: 20),
                  label: const Text('Оценить заказ'),
                ),
              ),
            const SizedBox(height: 12),
            if (order.isOverdueAt(_now)) _overtimeBanner(order),
            _leadBlock(),
            const SizedBox(height: 12),
            _timeline(order),
            const SizedBox(height: 12),
            _entranceBlock(order),
            const SizedBox(height: 16),
            if (_offlinePending != null) _offlineBanner(),
            if (_finishedDone) _feedbackBlock(order) else _actionButton(order),
            if (_lastResult != null) _resultNote(order),
          ],
        ),
      ),
    );
  }

  /// Синяя «шапка» заказа: статус, адрес, время, состав.
  /// Чат — только участникам заказа: заказчику, бригаде, диспетчеру/админу.
  /// Так же решает сервер (RLS messages); здесь — понятное объяснение
  /// вместо «Недостаточно прав», пока отклик ещё не одобрен.
  bool _canChat(Order order) =>
      (_myId != null && order.clientId == _myId) ||
      _takers.any((t) => t.porter.id == _myId) ||
      _myRoles.contains(UserRole.dispatcher) ||
      _myRoles.contains(UserRole.admin);

  void _openChat(Order order) {
    if (!_canChat(order)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        key: Key('active_chat_locked'),
        content: Text(
          'Чат откроется, когда диспетчер одобрит ваш отклик и вы попадёте '
          'в бригаду. Сейчас он доступен заказчику, бригаде и диспетчеру.',
        ),
      ));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OrderChatScreen(
        repository: widget.repository,
        orderId: widget.orderId,
      ),
    ));
  }

  Widget _summaryCard(Order order) => BrandSurface(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _heroPill(order.status.icon, order.status.label, bright: true),
                _heroPill(order.urgency.icon, order.urgency.label),
                if (order.isReplacement) _heroPill(Icons.swap_horiz, 'Замена'),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              order.address,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                height: 1.25,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            if (order.taskDescription.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                order.taskDescription,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                MetaItem(
                  icon: Icons.schedule,
                  text: AppFormat.relativeDay(order.timeStart, now: _now),
                  color: Colors.white,
                  bold: true,
                ),
                MetaItem(
                  icon: Icons.groups_2_outlined,
                  text: '${order.peopleCount} чел.',
                  color: Colors.white,
                ),
                MetaItem(
                  icon: Icons.timelapse,
                  text: AppFormat.duration(order.plannedDurationMin),
                  color: Colors.white,
                ),
              ],
            ),
          ],
        ),
      );

  Widget _heroPill(IconData icon, String label, {bool bright = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bright
              ? AppColors.brandYellow
              : Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: bright ? AppColors.ink : Colors.white),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: bright ? AppColors.ink : Colors.white,
              ),
            ),
          ],
        ),
      );

  Widget _overtimeBanner(Order order) => AppBanner(
        margin: const EdgeInsets.only(bottom: 12),
        icon: Icons.timer_off_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Заказ идёт дольше плана (план + 15 минут)',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: AppColors.error)),
            if (_isLead) ...[
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _busy ? null : _askDelayReason,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  minimumSize: const Size(64, 42),
                  side:
                      BorderSide(color: AppColors.error.withValues(alpha: 0.4)),
                ),
                child: const Text('Объяснить причину задержки'),
              ),
            ],
          ],
        ),
      );

  Widget _leadBlock() {
    final lead = _lead;
    if (lead == null) {
      return const AppCard(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: Padding(
                padding: EdgeInsets.all(10),
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Старший назначается…',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  SizedBox(height: 2),
                  Text(
                    'Диспетчер выберет за 5 минут, иначе — максимальный рейтинг',
                    style: TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final meIsLead = _takers.any((t) => t.isLead && t.porter.id == _meId);
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          InitialAvatar(
            name: lead.name,
            background: AppColors.brandYellow,
            foreground: AppColors.ink,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Старший: ${lead.name}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                if (meIsLead) ...[
                  const SizedBox(height: 2),
                  const Text('Это вы — вам нажимать «Начали» и «Закончили»',
                      style: TextStyle(color: AppColors.muted, fontSize: 13)),
                ],
              ],
            ),
          ),
          if (_takers.length > 1)
            AppPill(
              label: '${_takers.length}',
              icon: Icons.groups_2_outlined,
              color: AppColors.muted,
            ),
        ],
      ),
    );
  }

  Widget _timeline(Order order) {
    final morning = order.isMorning;
    final stages = [
      for (final stage in OrderStageType.values)
        if (morning || stage != OrderStageType.woke) stage,
    ];
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Этапы',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2)),
          const SizedBox(height: 12),
          for (var i = 0; i < stages.length; i++)
            _timelineRow(stages[i], isLast: i == stages.length - 1),
        ],
      ),
    );
  }

  Widget _timelineRow(OrderStageType stage, {required bool isLast}) {
    final mine = _stages.where((s) => s.stage == stage && s.porterId == _meId);
    final done = mine.isNotEmpty;
    final at = done ? mine.first.at : null;
    final isNext = _avail.nextRequired == stage;
    final hhmm = at == null ? '' : AppFormat.hhmm(at);
    final dotColor = done
        ? AppColors.success
        : (isNext ? AppColors.brandBlue : AppColors.border);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: done
                        ? AppColors.success
                        : (isNext
                            ? AppColors.brandBlueSoft
                            : AppColors.surface),
                    shape: BoxShape.circle,
                    border: Border.all(color: dotColor, width: 2),
                  ),
                  child: done
                      ? const Icon(Icons.check, size: 15, color: Colors.white)
                      : (isNext
                          ? const Center(
                              child: SizedBox(
                                width: 8,
                                height: 8,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: AppColors.brandBlue,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            )
                          : null),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      color: done ? AppColors.success : AppColors.border,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 2, bottom: isLast ? 10 : 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _stageLabel(stage),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight:
                          isNext || done ? FontWeight.w700 : FontWeight.w500,
                      color: done || isNext ? AppColors.ink : AppColors.muted,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    hhmm,
                    style: const TextStyle(
                      color: AppColors.success,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _stageLabel(OrderStageType s) => switch (s) {
        OrderStageType.woke => 'Проснулся',
        OrderStageType.departed => 'Выехал',
        OrderStageType.arrived => 'На месте',
        OrderStageType.started => 'Начали',
        OrderStageType.finished => 'Закончили',
        OrderStageType.feedback => 'Обратная связь',
      };

  Widget _entranceBlock(Order order) {
    if (!_startedDone) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border),
        ),
        child: const Row(
          children: [
            Icon(Icons.lock_outline, size: 20, color: AppColors.muted),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Ориентир (подъезд, код, этаж) откроется после этапа «Начали»',
                style: TextStyle(color: AppColors.muted, height: 1.35),
              ),
            ),
          ],
        ),
      );
    }
    return AppBanner(
      tone: BannerTone.info,
      icon: Icons.place_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Ориентир',
              style: TextStyle(
                  fontWeight: FontWeight.w800, color: AppColors.brandBlueDeep)),
          const SizedBox(height: 2),
          Text(order.entrance ?? 'Ориентир не указан',
              style: const TextStyle(fontSize: 15, height: 1.35)),
        ],
      ),
    );
  }

  Widget _offlineBanner() => AppBanner(
        tone: BannerTone.warning,
        icon: Icons.wifi_off,
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Нет сети: этап «$_offlinePendingText» не отправлен. '
                'Досылаем автоматически, либо:'),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                  onPressed: _retryOffline,
                  child: const Text('Отправить ещё раз')),
            ),
          ],
        ),
      );

  String get _offlinePendingText =>
      _offlinePending == null ? '' : _stageLabel(_offlinePending!);

  Widget _actionButton(Order order) {
    final next = _avail.nextRequired;
    if (next == null || next == OrderStageType.feedback) {
      return const SizedBox.shrink();
    }
    final canPress = _avail.available.contains(next);
    final decision = OrderFlowMachine.decide(
      stage: next,
      order: order,
      done: _myDone,
      isLead: _isLead,
      inBrigade: _takers.isEmpty || _takers.any((t) => t.porter.id == _meId),
      now: _now,
      finishedAt: _finishedAt,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          onPressed: canPress && !_busy ? () => _press(next, order) : null,
          style: FilledButton.styleFrom(
            minimumSize: const Size(64, 60),
            textStyle:
                const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg)),
          ),
          child: _busy
              ? const ButtonSpinner(color: AppColors.muted)
              : Text(_stageLabel(next)),
        ),
        if (!canPress && _avail.blockedReason != null) ...[
          const SizedBox(height: 10),
          Text(_avail.blockedReason!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted)),
        ],
        if (canPress && decision.allowed && decision.warning != null) ...[
          const SizedBox(height: 10),
          AppBanner(
            tone: BannerTone.warning,
            child: Text(decision.warning!,
                style: const TextStyle(
                    color: AppColors.warning, fontWeight: FontWeight.w600)),
          ),
        ],
      ],
    );
  }

  DateTime? get _finishedAt {
    for (final s in _stages) {
      if (s.stage == OrderStageType.finished) return s.at;
    }
    return null;
  }

  Future<void> _press(OrderStageType stage, Order order) async {
    final decision = OrderFlowMachine.decide(
      stage: stage,
      order: order,
      done: _myDone,
      isLead: _isLead,
      inBrigade: true,
      now: _now,
      finishedAt: _finishedAt,
    );

    // 🔴 Предупреждение ДО нажатия: штраф или пропущенный дедлайна.
    if (decision.allowed && decision.warning != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Точно отметить этап?'),
          content: Text(decision.warning!),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Отмена')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Отметить')),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _busy = true);
    try {
      final res = await widget.repository
          .setStage(orderId: widget.orderId, stage: stage);
      if (mounted) setState(() => _lastResult = res);
      await _refreshAvailability();
    } on AppFailure catch (f) {
      if (f.code == FailureCode.offline) {
        if (mounted) setState(() => _offlinePending = stage);
      } else if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(f.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(Failures.unknown(e).message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retryOffline() async {
    final stage = _offlinePending;
    if (stage == null || _order == null) return;
    setState(() {
      _offlinePending = null;
    });
    await _press(stage, _order!);
  }

  Widget _feedbackBlock(Order order) {
    final deadline = _avail.feedbackDeadline;
    final expired = deadline != null && _now.isAfter(deadline);
    if (expired) {
      return const AppBanner(
        icon: Icons.timelapse_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Обратная связь не сдана в срок',
                style: TextStyle(fontWeight: FontWeight.w700)),
            SizedBox(height: 2),
            Text('Заказ закрыт автоматически (feedback_missed)',
                style: TextStyle(color: AppColors.muted, fontSize: 13)),
          ],
        ),
      );
    }
    final remaining = deadline?.difference(_now);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Обратная связь старшего',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2)),
              ),
              if (remaining != null)
                AppPill(
                  icon: Icons.timer_outlined,
                  color: AppColors.warning,
                  label:
                      '${remaining.inMinutes.toString().padLeft(2, '0')}:${(remaining.inSeconds % 60).toString().padLeft(2, '0')}',
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                avatar: Icon(Icons.thumb_up_alt_outlined,
                    size: 16,
                    color:
                        _wentWell == true ? Colors.white : AppColors.success),
                label: const Text('Да, всё хорошо'),
                selected: _wentWell == true,
                selectedColor: AppColors.success,
                onSelected: (_) => setState(() => _wentWell = true),
              ),
              ChoiceChip(
                avatar: Icon(Icons.thumb_down_alt_outlined,
                    size: 16,
                    color: _wentWell == false ? Colors.white : AppColors.error),
                label: const Text('Нет, проблемы'),
                selected: _wentWell == false,
                selectedColor: AppColors.error,
                onSelected: (_) => setState(() => _wentWell = false),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _commentCtrl,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Комментарий в «Результат заявки»…',
              fillColor: AppColors.surfaceAlt,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _wentWell == null || _busy ? null : _submitFeedback,
            child: const Text('Закрыть заказ'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitFeedback() async {
    setState(() => _busy = true);
    try {
      final res = await widget.repository.finishOrder(
        orderId: widget.orderId,
        wentWell: _wentWell!,
        resultComment:
            _commentCtrl.text.trim().isEmpty ? null : _commentCtrl.text.trim(),
      );
      if (mounted) {
        setState(() => _completion = res);
        final people = _order?.peopleCount ?? 1;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Заказ закрыт: ${res.hours} ч × $people = ${res.totalHours} ч, '
              'рейтинг ${res.ratingDelta >= 0 ? '+' : ''}${res.ratingDelta}',
            ),
          ),
        );
      }
    } on AppFailure catch (f) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(f.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _resultNote(Order order) {
    final c = _completion;
    if (c != null) {
      return AppBanner(
        tone: BannerTone.success,
        margin: const EdgeInsets.only(top: 12),
        message: 'Закрыт: ${c.hours} ч на человека, всего ${c.totalHours} ч, '
            'рейтинг ${c.ratingDelta >= 0 ? '+' : ''}${c.ratingDelta}.',
      );
    }
    final r = _lastResult;
    if (r == null) return const SizedBox.shrink();
    return AppBanner(
      tone: r.orderReturnedToFeed || r.late
          ? BannerTone.warning
          : BannerTone.success,
      margin: const EdgeInsets.only(top: 12),
      message: r.orderReturnedToFeed
          ? 'Дедлайн пропущен: заказ возвращён в ленту, штраф −5.'
          : 'Этап «${_stageLabel(r.stage)}» отмечен в '
              '${AppFormat.hhmm(r.at)}'
              '${r.late ? ' (позже дедлайна)' : ''}.',
    );
  }

  Future<void> _askDelayReason() async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Причина задержки'),
        content: TextField(
          controller: ctrl,
          minLines: 2,
          maxLines: 4,
          decoration:
              const InputDecoration(hintText: 'Что помешало закончить в срок?'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Отправить'),
          ),
        ],
      ),
    );
    if (reason == null || reason.length < 5) return;
    try {
      await widget.repository
          .submitDelayReason(orderId: widget.orderId, reason: reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Причина отправлена диспетчеру')));
      }
    } on AppFailure catch (f) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(f.message)));
      }
    }
  }
}
