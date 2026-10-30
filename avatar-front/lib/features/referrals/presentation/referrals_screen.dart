/// ЭКРАН РЕФЕРАЛКИ (v2, зона Артёма; зеркало бота «Бонусная система»).
///
/// Мой код приглашения + список кого привёл со статусами.
/// Состояния: loading / data / empty / error (+ генерация кода, если нет).
/// 🔴 OPEN QUESTION Матвею: таблица referrals со статусами new/counted/left
///    и кроном засчёта (5 дней в чате, как в боте) — пока все входящие fresh.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/orders_repository.dart';
import '../../order_flow/domain/enums.dart';

class ReferralsScreen extends StatefulWidget {
  const ReferralsScreen({super.key, required this.repository});

  final OrdersRepository repository;

  @override
  State<ReferralsScreen> createState() => _ReferralsScreenState();
}

class _ReferralsScreenState extends State<ReferralsScreen> {
  ReferralInfo? _info;
  AppFailure? _error;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await widget.repository.getMyReferralInfo();
      if (mounted) setState(() => _info = info);
    } on AppFailure catch (f) {
      if (mounted) setState(() => _error = f);
    }
  }

  Future<void> _generate() async {
    setState(() => _generating = true);
    try {
      final code = await widget.repository.ensureReferralCode();
      if (mounted) {
        setState(() {
          _info = ReferralInfo(
            code: code,
            invited: _info?.invited ?? const [],
          );
        });
      }
    } on AppFailure catch (f) {
      if (mounted) setState(() => _error = f);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _copy() async {
    final code = _info?.code;
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Код скопирован')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Рефералы')),
        body: _body(),
      );

  Widget _body() {
    if (_error != null) {
      return Center(
        child: Column(
          key: const Key('ref_error'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!.message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('ref_retry'),
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
    final info = _info;
    if (info == null) {
      return const Center(
        child: CircularProgressIndicator(key: Key('ref_loading')),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: info.code == null
                ? Column(
                    children: [
                      const Text('У тебя ещё нет кода приглашения.'),
                      const SizedBox(height: 12),
                      FilledButton(
                        key: const Key('ref_gen'),
                        onPressed: _generating ? null : _generate,
                        child: const Text('Получить код'),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Твой код приглашения'),
                            const SizedBox(height: 4),
                            SelectableText(
                              info.code!,
                              key: const Key('ref_code'),
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: AppColors.brandBlue,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton.filled(
                        key: const Key('ref_copy'),
                        tooltip: 'Скопировать',
                        onPressed: _copy,
                        icon: const Icon(Icons.copy),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Новичок вводит твой код при регистрации — и попадает в твой '
          'список. Правила засчёта бонусов объявим вместе с кроном засчёта '
          '(как в боте: 5 дней в чате).',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 16),
        Text('Приглашено: ${info.count}',
            key: const Key('ref_count'),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (info.invited.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              key: Key('ref_empty'),
              'Пока никого. Поделись кодом в чате бригады — '
              'новенькие грузчики пригодятся всегда.',
              textAlign: TextAlign.center,
            ),
          )
        else
          for (final e in info.invited)
            Card(
              key: const Key('ref_entry'),
              child: ListTile(
                leading: const Icon(Icons.person_add_alt_1,
                    color: AppColors.brandBlue),
                title: Text(e.name),
                subtitle: Text(e.phoneMasked),
                trailing: _statusChip(e.status),
              ),
            ),
      ],
    );
  }

  Widget _statusChip(ReferralStatus s) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: switch (s) {
            ReferralStatus.counted => AppColors.success.withValues(alpha: 0.15),
            ReferralStatus.left => Colors.grey.withValues(alpha: 0.2),
            ReferralStatus.fresh => AppColors.brandYellow.withValues(alpha: 0.3),
          },
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          switch (s) {
            ReferralStatus.counted => 'засчитан',
            ReferralStatus.left => 'ушёл',
            ReferralStatus.fresh => 'новый',
          },
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      );
}
