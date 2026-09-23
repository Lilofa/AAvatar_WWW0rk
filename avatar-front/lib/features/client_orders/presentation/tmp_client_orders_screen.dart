/// ВРЕМЕННЫЙ ЭКРАН «МОИ ЗАКАЗЫ» ЗАКАЗЧИКА (зона Артёма, до роутинга Коли).
///
/// 🔴 ПОМЕТКА «ВРЕМЕННО»: неделя 3 по плану — ядро заказчика и кабинет;
/// тогда этот экран заменяется нормальным «Мои заявки» с мастером создания.
/// Сейчас нужен, чтобы закрыть живой прогон MVP: заказчик видит свои заказы,
/// открывает активный и оставляет отзыв после выполнения.
///
/// Состояния: loading / empty / error / data (четыре, как требует чек-лист).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/error/app_failure.dart';
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

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Мои заказы'),
          backgroundColor: const Color(0xFF1D5BA6),
          foregroundColor: Colors.white,
        ),
        body: _body(),
        // ВРЕМЕННО (неделя 3): FAB создания заявки живёт здесь,
        // затем переедет в кабинет заказчика Коли.
        floatingActionButton: FloatingActionButton(
          key: const Key('client_create_fab'),
          backgroundColor: const Color(0xFF1D5BA6),
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
    if (orders.isEmpty) {
      return const Center(
        child: Text(
          key: Key('client_orders_empty'),
          'У вас пока нет заказов.\nСоздайте первый — и он появится здесь.',
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView.builder(
      key: const Key('client_orders_list'),
      padding: const EdgeInsets.all(16),
      itemCount: orders.length,
      itemBuilder: (context, i) => _card(orders[i]),
    );
  }

  Widget _card(Order o) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: ListTile(
          title: Text(o.taskTitle),
          subtitle: Text(
            '${o.address}\n${o.timeStart.day.toString().padLeft(2, '0')}.'
            '${o.timeStart.month.toString().padLeft(2, '0')} '
            '${o.timeStart.hour.toString().padLeft(2, '0')}:${o.timeStart.minute.toString().padLeft(2, '0')}'
            ' · ${o.status == OrderStatus.new_ ? 'черновик' : o.status.name}',
          ),
          isThreeLine: true,
          trailing: o.status == OrderStatus.completed
              ? FilledButton(
                  key: const Key('client_order_review_btn'),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => OrderReviewScreen(
                      repository: widget.repository,
                      orderId: o.id,
                    ),
                  )),
                  child: const Text('Оценить'),
                )
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
