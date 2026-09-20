/// ЭКРАН ОТЗЫВА ЗАКАЗЧИКА (зона Артёма).
///
/// Цикл отзыва из ТЗ: после выполнения заказчик ставит 1–5 звёзд + текст.
/// Состояния: form (data) / sending (loading) / error (баннер + повтор) /
/// done (успех). Валидация «оценка не выбрана» — отдельная плашка.
/// Метод: [OrdersRepository.submitClientReview] (RPC submit_review,
/// target_id = null — отзыв о заказе, сигнатура Матвея от 18.09).
library;

import 'package:flutter/material.dart';

import '../../../core/error/app_failure.dart';
import '../../../data/orders_repository.dart';

class OrderReviewScreen extends StatefulWidget {
  const OrderReviewScreen({
    super.key,
    required this.repository,
    required this.orderId,
  });

  final OrdersRepository repository;
  final String orderId;

  static const Color brandBlue = Color(0xFF1D5BA6);
  static const Color brandYellow = Color(0xFFF5E326);

  @override
  State<OrderReviewScreen> createState() => _OrderReviewScreenState();
}

class _OrderReviewScreenState extends State<OrderReviewScreen> {
  int _rating = 0;
  bool _sending = false;
  bool _done = false;
  AppFailure? _error;
  String? _validation;
  final _text = TextEditingController();

  Future<void> _submit() async {
    if (_sending) return;
    if (_rating < 1 || _rating > 5) {
      setState(() => _validation = 'Поставьте оценку — от 1 до 5 звёзд.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
      _validation = null;
    });
    try {
      await widget.repository.submitClientReview(
        orderId: widget.orderId,
        rating: _rating,
        text: _text.text.trim().isEmpty ? null : _text.text.trim(),
      );
      if (mounted) setState(() => _done = true);
    } on AppFailure catch (f) {
      if (mounted) setState(() => _error = f);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Оценка заказа'),
          backgroundColor: OrderReviewScreen.brandBlue,
          foregroundColor: Colors.white,
        ),
        body: _done ? _doneView() : _formView(),
      );

  Widget _doneView() => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            key: Key('review_done'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle,
                  size: 64, color: OrderReviewScreen.brandBlue),
              SizedBox(height: 16),
              Text(
                'Спасибо! Отзыв получен.\nРейтинг грузчика пересчитан.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      );

  Widget _formView() => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Как прошёл заказ?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Row(
              key: const Key('review_stars'),
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    key: Key('review_star_$i'),
                    iconSize: 40,
                    icon: Icon(
                      i <= _rating ? Icons.star : Icons.star_border,
                      color: OrderReviewScreen.brandYellow
                          .withValues(alpha: i <= _rating ? 1 : 0.6),
                    ),
                    onPressed: _sending
                        ? null
                        : () => setState(() {
                              _rating = i;
                              _validation = null;
                            }),
                  ),
              ],
            ),
            if (_validation != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _validation!,
                  key: const Key('review_validation'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            const SizedBox(height: 20),
            TextField(
              key: const Key('review_text'),
              controller: _text,
              minLines: 3,
              maxLines: 6,
              maxLength: 2000,
              decoration: const InputDecoration(
                hintText: 'Комментарий (необязательно): что понравилось, что нет',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null)
              Container(
                key: const Key('review_error'),
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!.message)),
                  ],
                ),
              ),
            FilledButton(
              key: const Key('review_submit'),
              style: FilledButton.styleFrom(
                backgroundColor: OrderReviewScreen.brandBlue,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: _sending ? null : _submit,
              child: _sending
                  ? const SizedBox(
                      key: Key('review_sending'),
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Отправить отзыв'),
            ),
          ],
        ),
      );
}
