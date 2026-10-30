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
        if (mounted) setState(() => _myId = u?.id);
      }),
    );
    _subs.add(
      widget.repository.watchOrderStatus(orderId: widget.orderId).listen(
        (status) {
          if (!mounted) return;
          setState(() {});
          if (status == OrderStatus.completed || status == OrderStatus.cancelled) {
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
      final a = await widget.repository.getStageAvailability(orderId: widget.orderId);
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

  bool get _startedDone => _stages.any((s) => s.stage == OrderStageType.started);
  bool get _finishedDone => _stages.any((s) => s.stage == OrderStageType.finished);

  @override
  Widget build(BuildContext context) {
    if (_loadError != null && _order == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Заказ')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_loadError!.message, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                if (_loadError!.showRetry)
                  FilledButton(onPressed: _subscribe, child: const Text('Повторить')),
              ],
            ),
          ),
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
          IconButton(
            key: const Key('active_chat_btn'),
            tooltip: 'Чат по заказу',
            icon: const Icon(Icons.chat_bubble_outline),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => OrderChatScreen(
                repository: widget.repository,
                orderId: widget.orderId,
              ),
            )),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _statusChip(order),
          if (order.status == OrderStatus.completed &&
              _myId != null &&
              _myId == order.clientId &&
              // баг-репорт 25.09: грузчик не оценивает заказ, в котором работал
              !_takers.any((t) => t.porter.id == _myId))
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: FilledButton(
                key: const Key('active_review_btn'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => OrderReviewScreen(
                    repository: widget.repository,
                    orderId: widget.orderId,
                  ),
                )),
                child: const Text('Оценить заказ'),
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
    );
  }

  Widget _statusChip(Order order) => Wrap(
        spacing: 8,
        children: [
          Chip(label: Text('Статус: ${order.status.wire}')),
          Chip(label: Text('Срочность: ${order.urgency.wire}')),
          if (order.isReplacement) const Chip(label: Text('Замена')),
        ],
      );

  Widget _overtimeBanner(Order order) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFC62828).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(' Заказ идёт дольше плана (план + 15 минут)',
                style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFC62828))),
            if (_isLead) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy ? null : _askDelayReason,
                child: const Text('Объяснить причину задержки'),
              ),
            ],
          ],
        ),
      );

  Widget _leadBlock() {
    final lead = _lead;
    if (lead == null) {
      return const ListTile(
        leading: SizedBox(
          width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2),
        ),
        title: Text('Старший назначается…'),
        subtitle: Text('Диспетчер выберет за 5 минут, иначе — максимальный рейтинг'),
      );
    }
    final meIsLead = _takers.any((t) => t.isLead && t.porter.id == _meId);
    return ListTile(
      leading: const Icon(Icons.badge_outlined),
      title: Text('Старший: ${lead.name}'),
      subtitle: meIsLead ? const Text('Это вы — вам нажимать «Начали» и «Закончили»') : null,
    );
  }

  Widget _timeline(Order order) {
    final morning = order.isMorning;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Этапы', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final stage in OrderStageType.values)
              if (morning || stage != OrderStageType.woke) _timelineRow(stage),
          ],
        ),
      ),
    );
  }

  Widget _timelineRow(OrderStageType stage) {
    final mine = _stages.where((s) => s.stage == stage && s.porterId == _meId);
    final done = mine.isNotEmpty;
    final at = done ? mine.first.at : null;
    final isNext = _avail.nextRequired == stage;
    final hhmm = at == null
        ? ''
        : '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle : (isNext ? Icons.radio_button_checked : Icons.radio_button_off),
            size: 18,
            color: done ? const Color(0xFF2E7D32) : (isNext ? const Color(0xFF1D5BA6) : Colors.grey),
          ),
          const SizedBox(width: 8),
          Text(_stageLabel(stage), style: TextStyle(fontWeight: isNext ? FontWeight.w700 : null)),
          const Spacer(),
          Text(hhmm, style: TextStyle(color: Colors.grey.shade600)),
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
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text('🔒 Ориентир (подъезд, код, этаж) откроется после этапа «Начали»'),
      );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1D5BA6).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📍 Ориентир', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(order.entrance ?? 'Ориентир не указан'),
        ],
      ),
    );
  }

  Widget _offlineBanner() => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFB26A00).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text('Нет сети: этап «$_offlinePendingText» не отправлен. '
                  'Досылаем автоматически, либо:'),
            ),
            TextButton(onPressed: _retryOffline, child: const Text('Отправить ещё раз')),
          ],
        ),
      );

  String get _offlinePendingText => _offlinePending == null ? '' : _stageLabel(_offlinePending!);

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
          child: Text(_stageLabel(next)),
        ),
        if (!canPress && _avail.blockedReason != null) ...[
          const SizedBox(height: 6),
          Text(_avail.blockedReason!,
              textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
        ],
        if (canPress && decision.allowed && decision.warning != null) ...[
          const SizedBox(height: 6),
          Text(decision.warning!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFB26A00), fontWeight: FontWeight.w600)),
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
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Отметить')),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _busy = true);
    try {
      final res = await widget.repository.setStage(orderId: widget.orderId, stage: stage);
      if (mounted) setState(() => _lastResult = res);
      await _refreshAvailability();
    } on AppFailure catch (f) {
      if (f.code == FailureCode.offline) {
        if (mounted) setState(() => _offlinePending = stage);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(f.message)));
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
      return const Card(
        child: ListTile(
          leading: Icon(Icons.timelapse_outlined, color: Color(0xFFC62828)),
          title: Text('Обратная связь не сдана в срок'),
          subtitle: Text('Заказ закрыт автоматически (feedback_missed)'),
        ),
      );
    }
    final remaining = deadline?.difference(_now);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text('Обратная связь старшего',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                if (remaining != null)
                  Text(
                    '${remaining.inMinutes.toString().padLeft(2, '0')}:${(remaining.inSeconds % 60).toString().padLeft(2, '0')}',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFB26A00)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ChoiceChip(
                  label: const Text('Да, всё хорошо'),
                  selected: _wentWell == true,
                  onSelected: (_) => setState(() => _wentWell = true),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Нет, проблемы'),
                  selected: _wentWell == false,
                  onSelected: (_) => setState(() => _wentWell = false),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _commentCtrl,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Комментарий в «Результат заявки»…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _wentWell == null || _busy ? null : _submitFeedback,
              child: const Text('Закрыть заказ'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitFeedback() async {
    setState(() => _busy = true);
    try {
      final res = await widget.repository.finishOrder(
        orderId: widget.orderId,
        wentWell: _wentWell!,
        resultComment: _commentCtrl.text.trim().isEmpty ? null : _commentCtrl.text.trim(),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(f.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _resultNote(Order order) {
    final c = _completion;
    if (c != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          'Закрыт: ${c.hours} ч на человека, всего ${c.totalHours} ч, '
          'рейтинг ${c.ratingDelta >= 0 ? '+' : ''}${c.ratingDelta}.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade700),
        ),
      );
    }
    final r = _lastResult;
    if (r == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        r.orderReturnedToFeed
            ? 'Дедлайн пропущен: заказ возвращён в ленту, штраф −5.'
            : 'Этап «${_stageLabel(r.stage)}» отмечен в '
                '${r.at.hour.toString().padLeft(2, '0')}:${r.at.minute.toString().padLeft(2, '0')}'
                '${r.late ? ' (позже дедлайна)' : ''}.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey.shade700),
      ),
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
          decoration: const InputDecoration(hintText: 'Что помешало закончить в срок?'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Отправить'),
          ),
        ],
      ),
    );
    if (reason == null || reason.length < 5) return;
    try {
      await widget.repository.submitDelayReason(orderId: widget.orderId, reason: reason);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Причина отправлена диспетчеру')));
      }
    } on AppFailure catch (f) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(f.message)));
      }
    }
  }
}
