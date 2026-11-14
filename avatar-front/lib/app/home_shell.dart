/// APP-SHELL С РОЛЯМИ (скелет Коли → Артём после 20.09).
///
/// Нижняя навигация собирается из ролей профиля:
/// грузчик → «Лента», заказчик → «Мои заказы», диспетчер/админ → «Диспетчер».
/// Профиль приходит из [OrdersRepository.watchCurrentUser].
/// Роутинг здесь намеренно простой (MaterialApp.home + IndexedStack):
/// когда приедет полноценный роутер Коли, замены потребует только этот файл.
library;

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../../data/mock_orders_repository.dart';
import '../../data/orders_repository.dart';
import '../features/client_orders/presentation/client_cabinet_screen.dart';
import '../features/dispatcher/presentation/dispatcher_screen.dart';
import '../features/order_feed/presentation/order_feed_screen.dart';
import '../features/order_flow/domain/enums.dart';
import '../features/order_response/presentation/respond_dialog.dart';
import '../features/referrals/presentation/referrals_screen.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.repository});

  final OrdersRepository repository;

  @override
  Widget build(BuildContext context) => StreamBuilder<UserProfile?>(
        stream: repository.watchCurrentUser(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Scaffold(
              body: Center(
                  child: CircularProgressIndicator(key: Key('shell_loading'))),
            );
          }
          return _Shell(profile: snap.data!, repository: repository);
        },
      );
}

class _Tab {
  const _Tab(this.label, this.icon, this.activeIcon, this.child);
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final Widget child;
}

class _Shell extends StatefulWidget {
  const _Shell({required this.profile, required this.repository});

  final UserProfile profile;
  final OrdersRepository repository;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int _index = 0;

  List<_Tab> get _tabs {
    final roles = widget.profile.roles;
    return [
      if (roles.contains(UserRole.porter))
        _Tab(
          'Лента',
          Icons.view_agenda_outlined,
          Icons.view_agenda,
          OrderFeedScreen(
            key: const Key('shell_feed'),
            repository: widget.repository,
            showMockSwitch: widget.repository is MockOrdersRepository,
            onOpenOrder: (id) => _openOrder(context, id),
            onRespond: (order) => RespondDialog.show(
              context,
              repository: widget.repository,
              order: order,
            ),
          ),
        ),
      if (roles.contains(UserRole.client))
        _Tab(
          'Мои заказы',
          Icons.person_outline,
          Icons.person,
          ClientCabinetScreen(
            key: const Key('shell_client'),
            repository: widget.repository,
          ),
        ),
      if (roles.contains(UserRole.porter))
        _Tab(
          'Рефералы',
          Icons.card_giftcard_outlined,
          Icons.card_giftcard,
          ReferralsScreen(
            key: const Key('shell_referrals'),
            repository: widget.repository,
          ),
        ),
      if (roles.contains(UserRole.dispatcher) || roles.contains(UserRole.admin))
        _Tab(
          'Диспетчер',
          Icons.headset_mic_outlined,
          Icons.headset_mic,
          DispatcherScreen(
            key: const Key('shell_dispatcher'),
            repository: widget.repository,
          ),
        ),
    ];
  }

  void _openOrder(BuildContext context, String id) =>
      Navigator.of(context).pushNamed('/order/$id');

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    final index = _index.clamp(0, tabs.length - 1);
    return Scaffold(
      body: IndexedStack(
        index: index,
        children: [for (final t in tabs) t.child],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: NavigationBar(
          key: const Key('shell_nav'),
          selectedIndex: index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            for (final t in tabs)
              NavigationDestination(
                icon: Icon(t.icon),
                selectedIcon: Icon(t.activeIcon),
                label: t.label,
              ),
          ],
        ),
      ),
    );
  }
}
