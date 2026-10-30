/// КАБИНЕТ ПОЛЬЗОВАТЕЛЯ (замена tmp-экрана «Мои заказы», зона Артёма, v2).
///
/// Шапка профиля (имя, телефон маской, роли, рейтинг грузчика) + две секции:
/// «Мои заказы (как заказчик)» и «Моя работа (как грузчик)» с правилами:
/// завершённый заказ клиента можно оценить, ТОЛЬКО если я не работал
/// в его бригаде (баг-репорт 25.09). FAB создания заявки остаётся.
/// Состояния: loading / data / empty / error (+ retry).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/orders_repository.dart';
import '../../../data/supabase/mappers.dart';
import '../../create_order/presentation/create_order_screen.dart';
import '../../order_active/presentation/order_active_screen.dart';
import '../../order_flow/domain/enums.dart';
import '../../order_flow/domain/models.dart';
import '../../order_review/presentation/order_review_screen.dart';

class ClientCabinetScreen extends StatefulWidget {
  const ClientCabinetScreen({super.key, required this.repository});

  final OrdersRepository repository;

  @override
  State<ClientCabinetScreen> createState() => _ClientCabinetScreenState();
}

class _ClientCabinetScreenState extends State<ClientCabinetScreen> {
  UserProfile? _profile;
  PorterProfile? _porter;
  List<Order>? _orders;
  List<Order> _work = const [];
  AppFailure? _error;
  StreamSubscription<List<Order>>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final profile = await widget.repository.watchCurrentUser().first;
      if (!mounted) return;
      PorterProfile? porter;
      if (profile != null && profile.isPorter) {
        porter = await widget.repository
            .getPorterProfile(userId: profile.id);
      }
      final work = await widget.repository.myWorkOrders();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _porter = porter;
        _work = work
            .where((o) => !o.clientIsMe && o.status == OrderStatus.completed)
            .toList();
      });
      _sub?.cancel();
      _sub = widget.repository.watchMyClientOrders().listen(
        (list) {
          if (mounted) setState(() => _orders = list);
        },
        onError: (Object e) {
          if (mounted) {
            setState(
                () => _error = e is AppFailure ? e : Failures.unknown(e));
          }
        },
      );
    } on AppFailure catch (f) {
      if (mounted) setState(() => _error = f);
    }
  }

  Set<String> get _workIds => _work.map((o) => o.id).toSet();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Кабинет')),
        body: _body(),
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
          key: const Key('cab_error'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!.message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('cab_retry'),
              onPressed: () {
                setState(() => _error = null);
                _load();
              },
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }
    final profile = _profile;
    final orders = _orders;
    if (profile == null || orders == null) {
      return const Center(
        child: CircularProgressIndicator(key: Key('cab_loading')),
      );
    }
    if (orders.isEmpty && _work.isEmpty) {
      return const Center(
        child: Text(
          key: Key('cab_empty'),
          'Пока пусто.\nСоздайте первую заявку кнопкой «+».',
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView(
      key: const Key('client_orders_list'),
      padding: const EdgeInsets.all(16),
      children: [
        _header(profile),
        const SizedBox(height: 20),
        const Text('Мои заказы (как заказчик)',
            key: Key('cab_client_section'),
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        for (final o in orders) _clientCard(o),
        if (_work.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text('Моя работа (как грузчик)',
              key: Key('cab_work_section'),
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final o in _work) _workCard(o),
        ],
      ],
    );
  }

  Widget _header(UserProfile p) {
    final initials = p.name.trim().isEmpty
        ? 'А'
        : p.name.trim()[0].toUpperCase();
    return Card(
      key: const Key('cab_profile'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: AppColors.brandBlue,
              child: Text(initials,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700)),
                  Text(maskPhone(p.phone),
                      style: TextStyle(color: Colors.grey.shade600)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final r in p.roles) _roleChip(r),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    }

  Widget _roleChip(UserRole r) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.brandYellow.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          switch (r) {
            UserRole.porter => 'грузчик',
            UserRole.client => 'заказчик',
            UserRole.dispatcher => 'диспетчер',
            UserRole.admin => 'админ',
          },
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      );

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
          leading:
              const Icon(Icons.handyman_outlined, color: AppColors.warning),
          title: Text(o.taskTitle),
          subtitle: Text('${o.address}\n${_dt(o.timeStart)} · выполнен'),
          isThreeLine: true,
          trailing: _porter == null
              ? null
              : Text('★ ${_porter!.rating}',
                  key: const Key('cab_rating'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => OrderActiveScreen(
              repository: widget.repository,
              orderId: o.id,
            ),
          )),
        ),
      );

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
