/// ПУЛЬТ ДИСПЕТЧЕРА (зона Коли → Артём после 20.09; MVP-прогон).
///
/// Список живых заказов (created/accepted/in_progress) → карточка заказа:
/// отклики с ETA (одобрить/отклонить), бригада, найти замену, закрыть
/// принудительно с комментарием. Источник истины — RPC Матвея.
/// Состояния списка: loading / empty / error / data.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../data/orders_repository.dart';
import '../../order_flow/domain/enums.dart';
import '../../order_flow/domain/models.dart';

class DispatcherScreen extends StatefulWidget {
  const DispatcherScreen({super.key, required this.repository});

  final OrdersRepository repository;

  @override
  State<DispatcherScreen> createState() => _DispatcherScreenState();
}

class _DispatcherScreenState extends State<DispatcherScreen> {
  StreamSubscription<List<Order>>? _sub;
  List<Order>? _orders;
  AppFailure? _error;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _listen() {
    _sub?.cancel();
    _sub = widget.repository.watchDispatcherOrders().listen(
      (list) {
        if (mounted) setState(() => _orders = list);
      },
      onError: (Object e) {
        if (mounted) {
          setState(() => _error = e is AppFailure ? e : Failures.unknown(e));
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Пульт диспетчера')),
        body: _body(),
      );

  Widget _body() {
    if (_error != null) {
      return StateView(
        key: const Key('disp_error'),
        icon: Icons.cloud_off_outlined,
        color: AppColors.error,
        body: Text(_error!.message),
        action: FilledButton(
          key: const Key('disp_retry'),
          onPressed: () {
            setState(() => _error = null);
            _listen();
          },
          child: const Text('Повторить'),
        ),
      );
    }
    final orders = _orders;
    if (orders == null) {
      return const Center(
        child: CircularProgressIndicator(key: Key('disp_loading')),
      );
    }
    if (orders.isEmpty) {
      return const StateView(
        icon: Icons.task_alt,
        color: AppColors.success,
        title: Text('Всё спокойно'),
        body: Text(
          key: Key('disp_empty'),
          'Живых заказов нет.\nНовые заявки появятся здесь.',
          textAlign: TextAlign.center,
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () async => _listen(),
      child: ListView.separated(
        key: const Key('disp_list'),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: orders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final o = orders[i];
          final statusText = o.status == OrderStatus.new_
              ? 'ждёт бригаду'
              : o.status == OrderStatus.approved
                  ? 'бригада собрана'
                  : 'в работе';
          return AppCard(
            key: const Key('disp_order_card'),
            accent: o.urgency.isHot ? AppColors.error : null,
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => DispatcherOrderScreen(
                repository: widget.repository,
                orderId: o.id,
              ),
            )),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(o.taskTitle,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2)),
                      const SizedBox(height: 3),
                      Text(o.address,
                          style: const TextStyle(
                              color: AppColors.muted, height: 1.3)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          AppPill(
                            label: statusText,
                            color: o.status.color,
                            icon: o.status.icon,
                          ),
                          if (o.urgency.isHot) UrgencyBadge(urgency: o.urgency),
                          MetaItem(
                            icon: Icons.groups_2_outlined,
                            text: '${o.peopleCount}',
                            color: AppColors.muted,
                          ),
                          MetaItem(
                            icon: Icons.schedule,
                            text: AppFormat.relativeDay(o.timeStart),
                            color: AppColors.muted,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.faint),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Карточка заказа у диспетчера: отклики, бригада, аварийные кнопки.
class DispatcherOrderScreen extends StatefulWidget {
  const DispatcherOrderScreen({
    super.key,
    required this.repository,
    required this.orderId,
  });

  final OrdersRepository repository;
  final String orderId;

  @override
  State<DispatcherOrderScreen> createState() => _DispatcherOrderScreenState();
}

class _DispatcherOrderScreenState extends State<DispatcherOrderScreen> {
  List<OrderResponse>? _responses;
  List<OrderTaker> _takers = const [];
  AppFailure? _error;
  bool _busy = false;
  StreamSubscription<List<OrderTaker>>? _takersSub;

  @override
  void initState() {
    super.initState();
    _refreshResponses();
    _takersSub =
        widget.repository.watchOrderTakers(orderId: widget.orderId).listen((t) {
      if (mounted) setState(() => _takers = t);
    });
  }

  @override
  void dispose() {
    _takersSub?.cancel();
    super.dispose();
  }

  Future<void> _refreshResponses() async {
    try {
      final list =
          await widget.repository.getPendingResponses(orderId: widget.orderId);
      if (mounted) setState(() => _responses = list);
    } on AppFailure catch (f) {
      if (mounted) setState(() => _error = f);
    }
  }

  Future<void> _act(Future<void> Function() action,
      {bool refresh = true}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (refresh) await _refreshResponses();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Готово')));
      }
    } on AppFailure catch (f) {
      if (mounted) {
        setState(() => _error = f);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forceClose() async {
    final ctrl = TextEditingController();
    final comment = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Закрыть принудительно'),
        content: TextField(
          key: const Key('disp_force_comment'),
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'Причина закрытия'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            key: const Key('disp_force_confirm'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(
                ctx,
                ctrl.text.trim().isEmpty
                    ? 'Закрыт диспетчером'
                    : ctrl.text.trim()),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
    // ctrl не диспожим вручную: TextField диалога живёт до конца pop-анимации.
    if (comment == null) return;
    await _act(() => widget.repository
        .forceCloseOrder(orderId: widget.orderId, comment: comment));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Заказ')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            if (_error != null)
              AppBanner(
                key: const Key('disp_order_error'),
                margin: const EdgeInsets.only(bottom: 12),
                message: _error!.message,
              ),
            SectionTitle(
              'Отклики, ожидающие решения',
              trailing: _responses == null || _responses!.isEmpty
                  ? null
                  : AppPill(
                      label: '${_responses!.length}',
                      color: AppColors.warning,
                    ),
            ),
            if (_responses == null)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_responses!.isEmpty)
              const AppCard(
                color: AppColors.surfaceAlt,
                child: Row(
                  children: [
                    Icon(Icons.inbox_outlined, color: AppColors.faint),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text('Нет откликов, ожидающих решения.',
                          style: TextStyle(color: AppColors.muted)),
                    ),
                  ],
                ),
              )
            else
              for (var i = 0; i < _responses!.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    key: const Key('disp_response_card'),
                    padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                    child: Row(
                      children: [
                        InitialAvatar(
                            name: _responses![i].porterName ?? 'Грузчик'),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_responses![i].porterName ?? 'Грузчик',
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              MetaItem(
                                icon: Icons.near_me_outlined,
                                text: 'ETA: ${_responses![i].etaMinutes} мин',
                                color: AppColors.muted,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          key: Key('disp_decline_$i'),
                          tooltip: 'Отклонить',
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.errorSoft,
                          ),
                          onPressed: _busy
                              ? null
                              : () => _act(() => widget.repository
                                  .declineResponse(
                                      responseId: _responses![i].id)),
                          icon: const Icon(Icons.close, color: AppColors.error),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          key: Key('disp_approve_$i'),
                          tooltip: 'Одобрить',
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.success,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _busy
                              ? null
                              : () => _act(() => widget.repository
                                  .approveResponse(
                                      responseId: _responses![i].id)),
                          icon: const Icon(Icons.check),
                        ),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: 20),
            SectionTitle(
              'Бригада',
              trailing: _takers.isEmpty
                  ? null
                  : AppPill(label: '${_takers.length}', color: AppColors.muted),
            ),
            if (_takers.isEmpty)
              const AppCard(
                color: AppColors.surfaceAlt,
                child: Row(
                  children: [
                    Icon(Icons.groups_2_outlined, color: AppColors.faint),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text('Бригада ещё не собрана.',
                          style: TextStyle(color: AppColors.muted)),
                    ),
                  ],
                ),
              )
            else
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    for (var i = 0; i < _takers.length; i++) ...[
                      if (i > 0) const Divider(height: 1, indent: 68),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        child: Row(
                          children: [
                            InitialAvatar(
                              name: _takers[i].porter.name,
                              size: 40,
                              background: _takers[i].isLead
                                  ? AppColors.brandYellow
                                  : AppColors.brandBlueSoft,
                              foreground: _takers[i].isLead
                                  ? AppColors.ink
                                  : AppColors.brandBlue,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(_takers[i].porter.name,
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600)),
                            ),
                            if (_takers[i].isLead)
                              const AppPill(
                                label: 'старший',
                                color: AppColors.warning,
                                icon: Icons.stars,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 28),
            OutlinedButton.icon(
              key: const Key('disp_replace_btn'),
              style:
                  OutlinedButton.styleFrom(backgroundColor: AppColors.surface),
              onPressed: _busy
                  ? null
                  : () => _act(() => widget.repository
                      .findReplacement(orderId: widget.orderId)),
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Найти замену'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('disp_force_btn'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                backgroundColor: AppColors.errorSoft,
                side: BorderSide(color: AppColors.error.withValues(alpha: 0.3)),
              ),
              onPressed: _busy ? null : _forceClose,
              icon: const Icon(Icons.block),
              label: const Text('Закрыть принудительно'),
            ),
          ],
        ),
      );
}
