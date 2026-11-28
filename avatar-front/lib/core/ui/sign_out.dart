/// ВЫХОД ИЗ АККАУНТА: кнопка для шапок корневых вкладок.
///
/// Колбэк выхода кладёт сверху [SignOutProvider] (его создаёт AuthGate), поэтому
/// кнопка есть у ЛЮБОЙ роли — у грузчика, заказчика и диспетчера — и экраны
/// не обязаны знать, как устроен вход (mock или Supabase).
library;

import 'package:flutter/material.dart';

import '../../data/orders_repository.dart';
import '../error/app_failure.dart';
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

/// «Удалить аккаунт» (App Store 5.1.1(v), Google Play, 152-ФЗ — отзыв согласия).
/// Подтверждение с объяснением, что удаляется и что остаётся, затем
/// [OrdersRepository.deleteMyAccount] и выход.
class DeleteAccountButton extends StatefulWidget {
  const DeleteAccountButton({super.key, required this.repository});

  final OrdersRepository repository;

  @override
  State<DeleteAccountButton> createState() => _DeleteAccountButtonState();
}

class _DeleteAccountButtonState extends State<DeleteAccountButton> {
  bool _busy = false;

  Future<void> _confirmAndDelete() async {
    final scope = SignOutProvider.maybeOf(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить аккаунт?'),
        content: const Text(
          'Мы удалим ваше имя, номер телефона, переписку и фото. '
          'Выполненные заказы останутся без ваших данных — их требует '
          'бухгалтерский учёт. Отменить удаление нельзя; войти с этим номером '
          'можно будет заново, как новый пользователь.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            key: const Key('delete_account_confirm'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.repository.deleteMyAccount();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        key: Key('delete_account_done'),
        content: Text('Аккаунт удалён.'),
      ));
      await scope?.onSignOut();
    } on AppFailure catch (f) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(f.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => TextButton.icon(
        key: const Key('cab_delete_account'),
        style: TextButton.styleFrom(foregroundColor: AppColors.error),
        onPressed: _busy ? null : _confirmAndDelete,
        icon: _busy
            ? const SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.delete_outline),
        label: const Text('Удалить аккаунт'),
      );
}
