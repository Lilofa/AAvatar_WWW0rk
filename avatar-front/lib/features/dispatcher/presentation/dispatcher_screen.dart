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
      return Center(
        child: Column(
          key: const Key('disp_error'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!.message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('disp_retry'),
              onPressed: () {
                setState(() => _error = null);
                _listen();
              },
              child: const Text('Повторить'),
            ),
          ],
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
      return const Center(
        child: Text(
          key: Key('disp_empty'),
          'Живых заказов нет.\nНовые заявки появятся здесь.',
          textAlign: TextAlign.center,
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () async => _listen(),
      child: ListView.builder(
        key: const Key('disp_list'),
        padding: const EdgeInsets.all(16),
        itemCount: orders.length,
        itemBuilder: (context, i) => Card(
          child: ListTile(
            key: const Key('disp_order_card'),
            title: Text(orders[i].taskTitle),
            subtitle: Text(
              '${orders[i].address}\n'
              '${orders[i].status == OrderStatus.new_ ? 'ждёт бригаду' : orders[i].status == OrderStatus.approved ? 'бригада собрана' : 'в работе'} · 👥 ${orders[i].peopleCount}',
            ),
            isThreeLine: true,
            trailing: orders[i].urgency == OrderUrgency.urgent ||
                    orders[i].urgency == OrderUrgency.replacement
                ? const Icon(Icons.priority_high, color: AppColors.error)
                : null,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => DispatcherOrderScreen(
                repository: widget.repository,
                orderId: orders[i].id,
              ),
            )),
          ),
        ),
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
    _takersSub = widget.repository
        .watchOrderTakers(orderId: widget.orderId)
        .listen((t) {
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
      final list = await widget.repository
          .getPendingResponses(orderId: widget.orderId);
      if (mounted) setState(() => _responses = list);
    } on AppFailure catch (f) {
      if (mounted) setState(() => _error = f);
    }
  }

  Future<void> _act(Future<void> Function() action, {bool refresh = true}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (refresh) await _refreshResponses();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Готово')));
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            key: const Key('disp_force_confirm'),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim().isEmpty ? 'Закрыт диспетчером' : ctrl.text.trim()),
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
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null)
              Container(
                key: const Key('disp_order_error'),
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppColors.error),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!.message)),
                  ],
                ),
              ),
            const Text('Отклики, ожидающие решения',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (_responses == null)
              const Center(child: CircularProgressIndicator())
            else if (_responses!.isEmpty)
              const Text('Нет откликов, ожидающих решения.')
            else
              for (var i = 0; i < _responses!.length; i++)
                Card(
                  child: ListTile(
                    key: const Key('disp_response_card'),
                    title: Text(_responses![i].porterName ?? 'Грузчик'),
                    subtitle: Text('ETA: ${_responses![i].etaMinutes} мин'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton.filled(
                          key: Key('disp_approve_$i'),
                          onPressed: _busy
                              ? null
                              : () => _act(() => widget.repository
                                  .approveResponse(
                                      responseId: _responses![i].id)),
                          icon: const Icon(Icons.check),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          key: Key('disp_decline_$i'),
                          onPressed: _busy
                              ? null
                              : () => _act(() => widget.repository
                                  .declineResponse(
                                      responseId: _responses![i].id)),
                          icon: const Icon(Icons.close,
                              color: AppColors.error),
                        ),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: 16),
            const Text('Бригада', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (_takers.isEmpty)
              const Text('Бригада ещё не собрана.')
            else
              for (final t in _takers)
                ListTile(
                  dense: true,
                  leading: Icon(
                      t.isLead ? Icons.stars : Icons.person_outline,
                      color: t.isLead ? AppColors.warning : Colors.grey),
                  title: Text(t.porter.name),
                  subtitle: t.isLead ? const Text('старший') : null,
                ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              key: const Key('disp_replace_btn'),
              onPressed: _busy
                  ? null
                  : () => _act(() => widget.repository
                      .findReplacement(orderId: widget.orderId)),
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Найти замену'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('disp_force_btn'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: _busy ? null : _forceClose,
              child: const Text('Закрыть принудительно'),
            ),
          ],
        ),
      );
}
