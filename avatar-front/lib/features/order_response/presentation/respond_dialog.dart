/// ДИАЛОГ ОТКЛИКА С ETA (зона Артёма, MVP «отклик + одобрение»).
///
/// Грузчик указывает, за сколько минут доедет до адреса (ETA).
/// Диспетчер одобряет/отклоняет за 15 минут (BizRules.etaApprovalTimeout),
/// иначе автоотклонение (ResponseStatus.expired на клиенте).
///
/// Состояния: form / busy / error(валидация или AppFailure внутри диалога).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/orders_repository.dart';
import '../../order_flow/domain/models.dart';

class RespondDialog extends StatefulWidget {
  const RespondDialog({
    super.key,
    required this.repository,
    required this.order,
  });

  final OrdersRepository repository;
  final Order order;

  /// true — отклик отправлен, false/null — отмена.
  static Future<bool?> show(
    BuildContext context, {
    required OrdersRepository repository,
    required Order order,
  }) =>
      showDialog<bool>(
        context: context,
        builder: (_) => RespondDialog(repository: repository, order: order),
      );

  @override
  State<RespondDialog> createState() => _RespondDialogState();
}

class _RespondDialogState extends State<RespondDialog> {
  final _eta = TextEditingController(text: '15');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _eta.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final minutes = int.tryParse(_eta.text.trim());
    if (minutes == null || minutes < 1 || minutes > 240) {
      setState(
          () => _error = 'Укажите реальное время в пути: от 1 до 240 минут.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.respondToOrder(
        orderId: widget.order.id,
        etaMinutes: minutes,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on AppFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _quickEta = [10, 15, 20, 30, 45];

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Откликнуться на заказ'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.place_outlined,
                        size: 18, color: AppColors.brandBlue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.order.address,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'За сколько доедете?',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.muted),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final m in _quickEta)
                    ChoiceChip(
                      label: Text('$m'),
                      selected: _eta.text.trim() == '$m',
                      onSelected: _busy
                          ? null
                          : (_) => setState(() {
                                _eta.text = '$m';
                                _error = null;
                              }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('respond_eta'),
                controller: _eta,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                decoration: const InputDecoration(
                  labelText: 'Минут до адреса (ETA)',
                  suffixText: 'мин',
                  fillColor: AppColors.surfaceAlt,
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _error!,
                    key: const Key('respond_error'),
                    style: const TextStyle(
                        color: AppColors.error, fontWeight: FontWeight.w600),
                  ),
                ),
              const SizedBox(height: 10),
              const Text(
                'Диспетчер ответит в течение 15 минут.',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            key: const Key('respond_confirm'),
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    key: Key('respond_busy'),
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Отправиться'),
          ),
        ],
      );
}
