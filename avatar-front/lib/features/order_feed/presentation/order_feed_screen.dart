/// ЭКРАН ЛЕНТЫ ЗАКАЗОВ (зона Артёма) — скелет на ВРЕМЕННЫХ виджетах.
///
/// ⚠️ ВРЕМЕННО: все `Tmp*`-виджеты внизу файла — заглушки до UI-кита Коли.
/// Список на замену: TmpOrderCard → AppCard заказа, TmpShimmerCard → OrderCardShimmer,
/// TmpEmpty → EmptyState, TmpError → ErrorState, TmpUrgencyBadge → StatusChip/UrgencyTheme.
/// Логика экрана (подписка, 4 состояния, retry) НЕ меняется при замене виджетов.
///
/// Данные приходят ТОЛЬКО через [OrdersRepository] (интерфейс), поэтому подмена
/// MockOrdersRepository → SupabaseOrdersRepository = одна строка в провайдере.
///
/// Провайдер/StateManagement: намеренно без Riverpod — стиль обвязки фиксирует Коля
/// (день 2, контракт). Сейчас — constructor injection + StatefulWidget.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/error/app_failure.dart';
import '../../../data/mock_orders_repository.dart';
import '../../../data/orders_repository.dart';
import '../../order_flow/domain/enums.dart';
import '../../order_flow/domain/models.dart';

/// Четыре обязательных состояния каждого экрана (ревью Коли по чек-листу).
enum FeedView { loading, data, empty, error }

class OrderFeedScreen extends StatefulWidget {
  const OrderFeedScreen({
    super.key,
    required this.repository,
    this.onOpenOrder,
    this.onOpenMyClientOrders,
    this.onRespond,
    this.showMockSwitch = false,
  });

  final OrdersRepository repository;
  final void Function(String orderId)? onOpenOrder;

  /// ВРЕМЕННО (до роутинга Коли, неделя 3): вход в «Мои заказы» для заказчика.
  final VoidCallback? onOpenMyClientOrders;

  /// Отклик с ETA (MVP): диалог открывает вызывающая сторона (main).
  final void Function(Order order)? onRespond;

  /// Debug-меню переключения 4 состояний (для ревью Коли и QA).
  final bool showMockSwitch;

  @override
  State<OrderFeedScreen> createState() => _OrderFeedScreenState();
}

class _OrderFeedScreenState extends State<OrderFeedScreen> {
  StreamSubscription<FeedPage>? _sub;
  FeedView _view = FeedView.loading;
  List<Order> _orders = const [];
  FeedEmptyReason _emptyReason = FeedEmptyReason.noOrders;
  AppFailure? _failure;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _subscribe() {
    _sub?.cancel();
    setState(() {
      _view = FeedView.loading;
      _failure = null;
    });

    // watchFeed отдаёт первый кадр сам; ошибки прихода ловим здесь.
    _sub = widget.repository.watchFeed().subscribeSafe(
          onData: (page) {
            if (!mounted) return;
            setState(() {
              _orders = page.items;
              _emptyReason = page.emptyReason;
              _view = page.isEmpty ? FeedView.empty : FeedView.data;
            });
          },
          onError: (Object e) {
            if (!mounted) return;
            setState(() {
              _failure = e is AppFailure ? e : Failures.unknown(e);
              _view = FeedView.error;
            });
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA), // ← ВРЕМЕННО: токен Коли придёт с темой
      appBar: AppBar(
        title: const Text('Доступные заказы'),
        // Debug-переключатель сознательно НЕ в appBar: в web-дебаге правый верхний
        // угол занимает красная лента DEBUG и перехватывает тапы.
        actions: [
          if (widget.onOpenMyClientOrders != null)
            IconButton(
              key: const Key('feed_my_client_orders'),
              tooltip: 'Мои заказы',
              icon: const Icon(Icons.receipt_long),
              onPressed: widget.onOpenMyClientOrders,
            ),
        ],
      ),
      floatingActionButton: widget.showMockSwitch
          ? FloatingActionButton(
              // IndexedStack держит все вкладки живыми: hero-теги FAB'ов
              // обязаны быть уникальными, иначе падение на переходе роута.
              heroTag: 'feed_debug_fab',
              tooltip: 'Состояния (debug)',
              backgroundColor: const Color(0xFF1D5BA6), // бренд-синий из брендбука
              foregroundColor: Colors.white,
              onPressed: _showMockMenu,
              child: const Icon(Icons.bug_report_outlined),
            )
          : null,
      body: switch (_view) {
        FeedView.loading => const TmpShimmerList(),
        FeedView.empty => TmpEmpty(
            // Матвей, блок 2: три разные причины пустоты → три разных текста.
            title: switch (_emptyReason) {
              FeedEmptyReason.noOrders => 'Заказов сейчас нет',
              FeedEmptyReason.filteredOut => 'Под фильтр ничего не подошло',
              FeedEmptyReason.allTaken => 'Все заказы разобраны',
            },
            body: switch (_emptyReason) {
              FeedEmptyReason.noOrders => 'Новые заявки появятся здесь. Загляните позже.',
              FeedEmptyReason.filteredOut => 'Попробуйте сбросить фильтры или подождать новые заявки.',
              FeedEmptyReason.allTaken => 'Открытые заявки закончились — обновите через минуту.',
            },
            onRetry: _subscribe,
          ),
        FeedView.error => TmpError(
            failure: _failure!,
            onRetry: _failure!.showRetry ? _subscribe : null,
          ),
        FeedView.data => RefreshIndicator(
            onRefresh: () async => _subscribe(),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: _orders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final o = _orders[i];
                return TmpOrderCard(
                  key: Key('feed_card_${o.id}'),
                  order: o,
                  onTap: () => widget.onOpenOrder?.call(o.id),
                  onRespond: widget.onRespond == null
                      ? null
                      : () => widget.onRespond!(o),
                );
              },
            ),
          ),
      },
    );
  }

  void _showMockMenu() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mode in MockMode.values)
              ListTile(
                title: Text(switch (mode) {
                  MockMode.normal => 'data (+ случайные ошибки)',
                  MockMode.slow => 'loading (3 c)',
                  MockMode.empty => 'empty',
                  MockMode.error => 'error',
                }),
                onTap: () {
                  MockControls.mode = mode;
                  Navigator.of(context).pop();
                  _subscribe();
                },
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ВРЕМЕННЫЕ ВИДЖЕТЫ — НА ЗАМЕНУ UI-КИТОМ КОЛИ
// ─────────────────────────────────────────────────────────────

/// Подписка на Stream с раздельными колбэками, чтобы ошибки стрима
/// попадали в состояние error, а не роняли экран.
extension _SafeSubscribe<T> on Stream<T> {
  StreamSubscription<T> subscribeSafe({
    required void Function(T) onData,
    required void Function(Object) onError,
  }) =>
      listen(onData, onError: onError, cancelOnError: false);
}

class TmpOrderCard extends StatelessWidget {
  const TmpOrderCard({super.key, required this.order, this.onTap, this.onRespond});

  final Order order;
  final VoidCallback? onTap;

  /// Кнопка «Откликнуться» (рисует только лента, если передан колбэк).
  final VoidCallback? onRespond;

  /// Дедлайн взятия заказа: immediate — час от создания, текущий — три часа.
  /// 🔴 Баг-репорт 25.09 («баг с временем»): дедлайн не может быть позже
  /// начала работ — ограничиваем сверху timeStart и не рисуем просроченный.
  DateTime? get _takeDeadline {
    final base = order.createdAt ?? order.timeStart.subtract(const Duration(hours: 1));
    final DateTime window;
    switch (order.urgency) {
      case OrderUrgency.urgent:
      case OrderUrgency.replacement:
        window = base.add(const Duration(hours: 1));
      case OrderUrgency.current:
        window = base.add(const Duration(hours: 3));
      case OrderUrgency.preliminary:
      case OrderUrgency.advance:
        return null;
    }
    final capped = window.isAfter(order.timeStart) ? order.timeStart : window;
    return capped.isAfter(DateTime.now()) ? capped : null;
  }

  /// «19:37», если сегодня; иначе полная метка. Без слова «дедлайн»:
  /// грузчику важен глагол и время, а не офисный термин.
  static String _takeDeadlineLabel(DateTime d) {
    final now = DateTime.now();
    final sameDay = DateTime(d.year, d.month, d.day) == DateTime(now.year, now.month, now.day);
    if (!sameDay) return _timeLabel(d);
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final takeDeadline = _takeDeadline;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      order.address,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                  TmpUrgencyBadge(urgency: order.urgency),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                order.taskTitle,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 10),
              // Wrap, а не Row: на узком экране (376–390 px) строка не должна
              // вылезать в горизонтальную прокрутку — бага поймана на скрине.
              Wrap(
                spacing: 12,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('🕐 ${_timeLabel(order.timeStart)}', style: _meta),
                  Text('👥 ${order.peopleCount}', style: _meta),
                  if (takeDeadline != null)
                    Text(
                      'Успеть взять до ${_takeDeadlineLabel(takeDeadline)}',
                      style: _meta.copyWith(
                        color: const Color(0xFFC62828),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              if (order.porterTariffHint != null) ...[
                const SizedBox(height: 6),
                Text(order.porterTariffHint!, style: _meta),
              ],
              // Матвей, блок 2: кнопка/статус зависят от my_response_status.
              if (order.myResponseStatus != null) ...[
                const SizedBox(height: 8),
                Text(
                  key: const Key('feed_my_response_chip'),
                  switch (order.myResponseStatus!) {
                    ResponseStatus.pending => '⏳ Отклик отправлен, ждём одобрения диспетчера',
                    ResponseStatus.declined => '❌ Отклик отклонён — можно откликнуться снова',
                    ResponseStatus.approved => '✅ Вы в бригаде, заказ в «Моих»',
                    ResponseStatus.expired => '⌛ Отклик истёк — можно откликнуться снова',
                  },
                  style: _meta.copyWith(
                    color: order.myResponseStatus == ResponseStatus.pending
                        ? const Color(0xFFB26A00)
                        : order.myResponseStatus == ResponseStatus.declined ||
                                order.myResponseStatus == ResponseStatus.expired
                            ? const Color(0xFFC62828)
                            : const Color(0xFF2E7D32),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              // MVP «отклик + одобрение»: откликнуться можно, пока заказ открыт
              // и моего живого отклика нет (null / отклонён / истёк).
              if (onRespond != null &&
                  order.isOpenForResponse &&
                  !order.clientIsMe &&
                  (order.myResponseStatus == null ||
                      order.myResponseStatus == ResponseStatus.declined ||
                      order.myResponseStatus == ResponseStatus.expired)) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const Key('feed_respond_btn'),
                    onPressed: onRespond,
                    child: const Text('Откликнуться · указать ETA'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static final TextStyle _meta =
      TextStyle(fontSize: 12, color: Colors.grey.shade600);

  /// «Сегодня, 15:00» / «Завтра, 09:00» — без intl, до хелпера Коли.
  static String _timeLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final hhmm =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (day == today) return 'Сегодня, $hhmm';
    if (day == today.add(const Duration(days: 1))) return 'Завтра, $hhmm';
    return '${d.day}.${d.month.toString().padLeft(2, '0')}, $hhmm';
  }
}

class TmpUrgencyBadge extends StatelessWidget {
  const TmpUrgencyBadge({super.key, required this.urgency});
  final OrderUrgency urgency;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (urgency) {
      OrderUrgency.urgent => ('Срочно', const Color(0xFFC62828)),
      OrderUrgency.replacement => ('Замена', const Color(0xFFC62828)),
      OrderUrgency.current => ('Текущий', const Color(0xFF1D5BA6)),
      OrderUrgency.preliminary => ('Предвар.', Colors.grey.shade600),
      OrderUrgency.advance => ('Заранее', const Color(0xFF2E7D32)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class TmpShimmerList extends StatelessWidget {
  const TmpShimmerList({super.key});

  @override
  Widget build(BuildContext context) {
    // ВРЕМЕННО: простой пульс. OrderCardShimmer Коли повторит форму карточки.
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (_, __) => Container(
        height: 96,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.grey.shade300.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

class TmpEmpty extends StatelessWidget {
  const TmpEmpty({super.key, required this.title, required this.body, this.onRetry});
  final String title;
  final String body;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📭', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(body,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600)),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Обновить')),
            ],
          ],
        ),
      ),
    );
  }
}

class TmpError extends StatelessWidget {
  const TmpError({super.key, required this.failure, this.onRetry});
  final AppFailure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('⚠️', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            // Текст ошибки приходит готовым из AppFailure — не сочиняем здесь.
            Text(failure.message,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700)),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Повторить')),
            ],
          ],
        ),
      ),
    );
  }
}
