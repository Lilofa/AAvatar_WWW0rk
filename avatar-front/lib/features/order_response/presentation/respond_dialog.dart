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
      setState(() =>
          _error = 'Укажите реальное время в пути: от 1 до 240 минут.');
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

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Откликнуться на заказ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.order.address,
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('respond_eta'),
              controller: _eta,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Минут до адреса (ETA)',
                suffixText: 'мин',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  key: const Key('respond_error'),
                  style: const TextStyle(color: Colors.red),
                ),
              ),
          ],
        ),
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
