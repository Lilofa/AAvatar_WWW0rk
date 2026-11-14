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
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../data/orders_repository.dart';

class OrderReviewScreen extends StatefulWidget {
  const OrderReviewScreen({
    super.key,
    required this.repository,
    required this.orderId,
  });

  final OrdersRepository repository;
  final String orderId;

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

  static const _ratingWords = [
    'Нажмите на звезду',
    'Очень плохо',
    'Плохо',
    'Нормально',
    'Хорошо',
    'Отлично!',
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Оценка заказа')),
        body: _done ? _doneView() : _formView(),
      );

  Widget _doneView() => const StateView(
        key: Key('review_done'),
        icon: Icons.check_rounded,
        color: AppColors.success,
        body: Text(
          'Спасибо! Отзыв получен.\nРейтинг грузчика пересчитан.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: AppColors.ink),
        ),
      );

  Widget _formView() => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppCard(
              padding: const EdgeInsets.fromLTRB(12, 24, 12, 20),
              child: Column(
                children: [
                  const Text(
                    'Как прошёл заказ?',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4),
                  ),
                  const SizedBox(height: 16),
                  FittedBox(
                    child: Row(
                      key: const Key('review_stars'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 1; i <= 5; i++)
                          IconButton(
                            key: Key('review_star_$i'),
                            iconSize: 46,
                            icon: AnimatedScale(
                              scale: i <= _rating ? 1.08 : 1,
                              duration: const Duration(milliseconds: 160),
                              child: Icon(
                                i <= _rating
                                    ? Icons.star_rounded
                                    : Icons.star_outline_rounded,
                                color: i <= _rating
                                    ? const Color(0xFFF5B400)
                                    : AppColors.faint,
                              ),
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
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _ratingWords[_rating.clamp(0, 5)],
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _rating == 0 ? AppColors.muted : AppColors.ink,
                    ),
                  ),
                  if (_validation != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        _validation!,
                        key: const Key('review_validation'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: AppColors.error,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('review_text'),
              controller: _text,
              minLines: 3,
              maxLines: 6,
              maxLength: 2000,
              decoration: const InputDecoration(
                hintText:
                    'Комментарий (необязательно): что понравилось, что нет',
                alignLabelWithHint: true,
              ),
            ),
            if (_error != null)
              AppBanner(
                key: const Key('review_error'),
                margin: const EdgeInsets.only(bottom: 12),
                message: _error!.message,
              ),
            FilledButton(
              key: const Key('review_submit'),
              style: FilledButton.styleFrom(minimumSize: const Size(64, 56)),
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
