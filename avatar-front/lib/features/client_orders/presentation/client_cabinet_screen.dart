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
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/sign_out.dart';
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
        porter = await widget.repository.getPorterProfile(userId: profile.id);
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
            setState(() => _error = e is AppFailure ? e : Failures.unknown(e));
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
        appBar: AppBar(
          title: const Text('Кабинет'),
          actions: const [SignOutButton(), SizedBox(width: 8)],
        ),
        body: _body(),
        floatingActionButton: FloatingActionButton.extended(
          key: const Key('client_create_fab'),
          heroTag: 'client_create_fab',
          tooltip: 'Создать заявку',
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => CreateOrderScreen(repository: widget.repository),
          )),
          icon: const Icon(Icons.add),
          label: const Text('Новая заявка'),
        ),
      );

  Widget _body() {
    if (_error != null) {
      return StateView(
        key: const Key('cab_error'),
        icon: Icons.cloud_off_outlined,
        color: AppColors.error,
        body: Text(_error!.message),
        action: FilledButton(
          key: const Key('cab_retry'),
          onPressed: () {
            setState(() => _error = null);
            _load();
          },
          child: const Text('Повторить'),
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
      return const StateView(
        icon: Icons.inventory_2_outlined,
        title: Text('Заказов ещё не было'),
        body: Text(
          key: Key('cab_empty'),
          'Пока пусто.\nСоздайте первую заявку кнопкой «+».',
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView(
      key: const Key('client_orders_list'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 104),
      children: [
        _header(profile),
        const SizedBox(height: 24),
        SectionTitle(
          'Мои заказы (как заказчик)',
          key: const Key('cab_client_section'),
          trailing: AppPill(label: '${orders.length}', color: AppColors.muted),
        ),
        if (orders.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text('Заявок пока нет — создайте первую.',
                style: TextStyle(color: AppColors.muted)),
          ),
        for (final o in orders) _clientCard(o),
        if (_work.isNotEmpty) ...[
          const SizedBox(height: 12),
          SectionTitle(
            'Моя работа (как грузчик)',
            key: const Key('cab_work_section'),
            trailing: AppPill(label: '${_work.length}', color: AppColors.muted),
          ),
          for (final o in _work) _workCard(o),
        ],
      ],
    );
  }

  Widget _header(UserProfile p) {
    final porter = _porter;
    return BrandSurface(
      key: const Key('cab_profile'),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InitialAvatar(
                name: p.name,
                size: 56,
                background: AppColors.brandYellow,
                foreground: AppColors.ink,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3)),
                    const SizedBox(height: 2),
                    Text(maskPhone(p.phone),
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.78))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final r in p.roles) _roleChip(r)],
          ),
          if (porter != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                _stat('${porter.rating}', 'рейтинг', Icons.star_rounded),
                const SizedBox(width: 8),
                _stat('${porter.completedCount}', 'выполнено',
                    Icons.check_circle_outline),
                const SizedBox(width: 8),
                _stat('${porter.failCount}', 'срывов', Icons.report_outlined),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(String value, String label, IconData icon) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: AppColors.brandYellow),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.75))),
            ],
          ),
        ),
      );

  Widget _roleChip(UserRole r) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          switch (r) {
            UserRole.porter => 'грузчик',
            UserRole.client => 'заказчик',
            UserRole.dispatcher => 'диспетчер',
            UserRole.admin => 'админ',
          },
          style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
        ),
      );

  void _open(Order o) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => OrderActiveScreen(
          repository: widget.repository,
          orderId: o.id,
        ),
      ));

  Widget _orderInfo(Order o, {required Widget status}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wrap, а не Row: на узких телефонах статус + рейтинг + дата
          // не помещаются в строку и переносятся, а не вылезают за край.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              status,
              MetaItem(
                icon: Icons.schedule,
                text: _dt(o.timeStart),
                color: AppColors.muted,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(o.taskTitle,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2)),
          const SizedBox(height: 3),
          Text(o.address,
              style: const TextStyle(color: AppColors.muted, height: 1.3)),
        ],
      );

  Widget _clientCard(Order o) {
    final worked = _workIds.contains(o.id);
    final completed = o.status == OrderStatus.completed;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        onTap: completed ? null : () => _open(o),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _orderInfo(
              o,
              status: AppPill(
                label: o.status.label,
                color: o.status.color,
                icon: o.status.icon,
              ),
            ),
            const SizedBox(height: 12),
            if (completed)
              worked
                  ? const Tooltip(
                      message: 'Вы работали в этом заказе — оценка недоступна',
                      child: Row(
                        children: [
                          Icon(Icons.block, size: 16, color: AppColors.faint),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Вы работали в этом заказе — оценка недоступна',
                              style: TextStyle(
                                  fontSize: 13, color: AppColors.muted),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        key: const Key('client_order_review_btn'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.brandYellow,
                          foregroundColor: AppColors.ink,
                          minimumSize: const Size(64, 42),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                        ),
                        onPressed: () =>
                            Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => OrderReviewScreen(
                            repository: widget.repository,
                            orderId: o.id,
                          ),
                        )),
                        icon: const Icon(Icons.star_rounded, size: 18),
                        label: const Text('Оценить'),
                      ),
                    )
            else
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('client_order_open_btn'),
                  onPressed: () => _open(o),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Открыть'),
                      SizedBox(width: 2),
                      Icon(Icons.chevron_right, size: 20),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _workCard(Order o) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: AppCard(
          key: const Key('client_work_card'),
          onTap: () => _open(o),
          child: _orderInfo(
            o,
            status: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppPill(
                  label: 'Выполнен',
                  color: AppColors.success,
                  icon: Icons.handyman_outlined,
                ),
                if (_porter != null) ...[
                  const SizedBox(width: 8),
                  Text('★ ${_porter!.rating}',
                      key: const Key('cab_rating'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.warning)),
                ],
              ],
            ),
          ),
        ),
      );

  String _dt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
