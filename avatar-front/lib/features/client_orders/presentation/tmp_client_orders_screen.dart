/// ВРЕМЕННЫЙ ЭКРАН «МОИ ЗАКАЗЫ» ЗАКАЗЧИКА (зона Артёма, до кабинета Коли).
///
/// 🔴 Баг-репорт начальника 25.09: интерфейс должен понимать, кто в системе,
/// и не смешивать роли. Поэтому экран разделён:
///   1. «Мои заявки (как заказчик)» — где я client_id; завершённые можно
///      оценить, ЕСЛИ я не работал в этом заказе грузчиком;
///   2. «Моя работа (как грузчик)» — завершённые заказы, где я в бригаде
///      и заказчик — не я; оценки там нет по определению.
/// Состояния: loading / empty / error / data.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/orders_repository.dart';
import '../../create_order/presentation/create_order_screen.dart';
import '../../order_active/presentation/order_active_screen.dart';
import '../../order_flow/domain/enums.dart';
import '../../order_flow/domain/models.dart';
import '../../order_review/presentation/order_review_screen.dart';

class TmpClientOrdersScreen extends StatefulWidget {
  const TmpClientOrdersScreen({super.key, required this.repository});

  final OrdersRepository repository;

  @override
  State<TmpClientOrdersScreen> createState() => _TmpClientOrdersScreenState();
}

class _TmpClientOrdersScreenState extends State<TmpClientOrdersScreen> {
  StreamSubscription<List<Order>>? _sub;
  List<Order>? _orders;
  List<Order> _work = const [];
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

  Future<void> _loadWork() async {
    try {
      final list = await widget.repository.myWorkOrders();
      if (mounted) {
        setState(() => _work = list
            .where((o) => !o.clientIsMe && o.status == OrderStatus.completed)
            .toList());
      }
    } on AppFailure {
      // секция работы не критична: молча остаётся пустой
    }
  }

  void _listen() {
    _sub?.cancel();
    _loadWork();
    _sub = widget.repository.watchMyClientOrders().listen(
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

  Set<String> get _workIds => _work.map((o) => o.id).toSet();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Мои заказы'),
          backgroundColor: AppColors.brandBlue,
          foregroundColor: Colors.white,
        ),
        body: _body(),
        // ВРЕМЕННО (неделя 3): FAB создания заявки живёт здесь,
        // затем переедет в кабинет заказчика Коли.
        floatingActionButton: FloatingActionButton(
          key: const Key('client_create_fab'),
          heroTag: 'client_create_fab',
          backgroundColor: AppColors.brandBlue,
          foregroundColor: Colors.white,
          tooltip: 'Создать заявку',
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => CreateOrderScreen(repository: widget.repository),
          )),
          child: const Icon(Icons.add),
        ),
      );

  Widget _body() {
    if (_error != null) {
      return Center(
        child: Column(
          key: const Key('client_orders_error'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!.message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('client_orders_retry'),
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
        child: CircularProgressIndicator(key: Key('client_orders_loading')),
      );
    }
    if (orders.isEmpty && _work.isEmpty) {
      return const Center(
        child: Text(
          key: Key('client_orders_empty'),
          'У вас пока нет заказов.\nСоздайте первый — и он появится здесь.',
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView(
      key: const Key('client_orders_list'),
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Мои заявки (как заказчик)',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (orders.isEmpty)
          const Text('Заявок пока нет.')
        else
          for (final o in orders) _clientCard(o),
        if (_work.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text('Моя работа (как грузчик)',
              key: Key('client_work_section'),
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final o in _work) _workCard(o),
        ],
      ],
    );
  }

  Widget _clientCard(Order o) {
    final worked = _workIds.contains(o.id);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(o.taskTitle),
        subtitle: Text(
          '${o.address}\n${_dt(o.timeStart)} · ${_statusLabel(o.status)}',
        ),
        isThreeLine: true,
        trailing: o.status == OrderStatus.completed
            ? (worked
                ? const Tooltip(
                    message: 'Вы работали в этом заказе — оценка недоступна',
                    child: Icon(Icons.block, color: Colors.grey),
                  )
                : FilledButton(
                    key: const Key('client_order_review_btn'),
                    onPressed: () =>
                        Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => OrderReviewScreen(
                        repository: widget.repository,
                        orderId: o.id,
                      ),
                    )),
                    child: const Text('Оценить'),
                  ))
            : TextButton(
                key: const Key('client_order_open_btn'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => OrderActiveScreen(
                    repository: widget.repository,
                    orderId: o.id,
                  ),
                )),
                child: const Text('Открыть'),
              ),
      ),
    );
  }

  Widget _workCard(Order o) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: ListTile(
          key: const Key('client_work_card'),
          leading: const Icon(Icons.handyman_outlined, color: AppColors.warning),
          title: Text(o.taskTitle),
          subtitle: Text('${o.address}\n${_dt(o.timeStart)} · выполнен'),
          isThreeLine: true,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => OrderActiveScreen(
              repository: widget.repository,
              orderId: o.id,
            ),
          )),
        ),
      );

  /// 24-часовой формат, баг-репорт 25.09.
  String _dt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _statusLabel(OrderStatus s) => switch (s) {
        OrderStatus.new_ => 'черновик',
        OrderStatus.approved => 'бригада собрана',
        OrderStatus.inProgress => 'в работе',
        OrderStatus.completed => 'выполнен',
        OrderStatus.cancelled => 'отменён',
      };
}
