/// ВЫХОД ИЗ АККАУНТА: кнопка для шапок корневых вкладок.
///
/// Колбэк выхода кладёт сверху [SignOutProvider] (его создаёт AuthGate), поэтому
/// кнопка есть у ЛЮБОЙ роли — у грузчика, заказчика и диспетчера — и экраны
/// не обязаны знать, как устроен вход (mock или Supabase).
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class SignOutProvider extends InheritedWidget {
  const SignOutProvider(
      {super.key, required this.onSignOut, required super.child});

  final Future<void> Function() onSignOut;

  static SignOutProvider? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SignOutProvider>();

  @override
  bool updateShouldNotify(SignOutProvider old) => old.onSignOut != onSignOut;
}

/// Иконка «Выйти» с подтверждением. Без [SignOutProvider] сверху не рисуется
/// (изолированные экраны в тестах).
class SignOutButton extends StatelessWidget {
  const SignOutButton({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = SignOutProvider.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();
    return IconButton(
      key: const Key('sign_out_btn'),
      tooltip: 'Выйти',
      icon: const Icon(Icons.logout_rounded),
      onPressed: () async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Выйти из аккаунта?'),
            content: const Text('Чтобы снова войти, понадобится код из СМС.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                key: const Key('sign_out_confirm'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Выйти'),
              ),
            ],
          ),
        );
        if (ok == true) await scope.onSignOut();
      },
    );
  }
}
