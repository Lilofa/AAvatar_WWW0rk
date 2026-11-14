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
import '../../../core/ui/app_widgets.dart';
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
      return StateView(
        key: const Key('ref_error'),
        icon: Icons.cloud_off_outlined,
        color: AppColors.error,
        body: Text(_error!.message),
        action: FilledButton(
          key: const Key('ref_retry'),
          onPressed: () {
            setState(() => _error = null);
            _load();
          },
          child: const Text('Повторить'),
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
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        BrandSurface(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          padding: const EdgeInsets.all(20),
          child: info.code == null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.card_giftcard,
                        size: 36, color: AppColors.brandYellow),
                    const SizedBox(height: 10),
                    const Text(
                      'У тебя ещё нет кода приглашения.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      key: const Key('ref_gen'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.brandYellow,
                        foregroundColor: AppColors.ink,
                      ),
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
                          Text('Твой код приглашения',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8))),
                          const SizedBox(height: 6),
                          SelectableText(
                            info.code!,
                            key: const Key('ref_code'),
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 3,
                              color: AppColors.brandYellow,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filled(
                      key: const Key('ref_copy'),
                      tooltip: 'Скопировать',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.16),
                        foregroundColor: Colors.white,
                        fixedSize: const Size(52, 52),
                      ),
                      onPressed: _copy,
                      icon: const Icon(Icons.copy_rounded),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        const AppBanner(
          tone: BannerTone.info,
          child: Text(
            'Новичок вводит твой код при регистрации — и попадает в твой '
            'список. Правила засчёта бонусов объявим вместе с кроном засчёта '
            '(как в боте: 5 дней в чате).',
            style:
                TextStyle(fontSize: 13, height: 1.4, color: AppColors.inkSoft),
          ),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text('Приглашено: ${info.count}',
              key: const Key('ref_count'),
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2)),
        ),
        if (info.invited.isEmpty)
          const AppCard(
            color: AppColors.surfaceAlt,
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 28),
            child: Column(
              children: [
                Icon(Icons.group_add_outlined,
                    size: 36, color: AppColors.faint),
                SizedBox(height: 10),
                Text(
                  key: Key('ref_empty'),
                  'Пока никого. Поделись кодом в чате бригады — '
                  'новенькие грузчики пригодятся всегда.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, height: 1.4),
                ),
              ],
            ),
          )
        else
          for (final e in info.invited)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                key: const Key('ref_entry'),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    InitialAvatar(name: e.name),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.name,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(e.phoneMasked,
                              style: const TextStyle(
                                  color: AppColors.muted, fontSize: 13)),
                        ],
                      ),
                    ),
                    _statusChip(e.status),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  Widget _statusChip(ReferralStatus s) => AppPill(
        label: switch (s) {
          ReferralStatus.counted => 'засчитан',
          ReferralStatus.left => 'ушёл',
          ReferralStatus.fresh => 'новый',
        },
        color: switch (s) {
          ReferralStatus.counted => AppColors.success,
          ReferralStatus.left => AppColors.muted,
          ReferralStatus.fresh => AppColors.warning,
        },
      );
}
