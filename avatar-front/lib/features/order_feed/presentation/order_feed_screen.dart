/// ЭКРАН ЛЕНТЫ ЗАКАЗОВ (зона Артёма).
///
/// Виджеты ленты собраны на UI-ките (core/ui/app_widgets.dart). Имена
/// `Tmp*` сохранены ради совместимости с тестами и вызывающим кодом.
/// Логика экрана (подписка, 4 состояния, retry) от вёрстки не зависит.
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
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
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
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: widget.showMockSwitch
          ? FloatingActionButton.small(
              // IndexedStack держит все вкладки живыми: hero-теги FAB'ов
              // обязаны быть уникальными, иначе падение на переходе роута.
              heroTag: 'feed_debug_fab',
              tooltip: 'Состояния (debug)',
              backgroundColor: AppColors.ink,
              foregroundColor: AppColors.brandYellow,
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
              FeedEmptyReason.noOrders =>
                'Новые заявки появятся здесь. Загляните позже.',
              FeedEmptyReason.filteredOut =>
                'Попробуйте сбросить фильтры или подождать новые заявки.',
              FeedEmptyReason.allTaken =>
                'Открытые заявки закончились — обновите через минуту.',
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
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              itemCount: _orders.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                if (index == 0) return _FeedSummary(orders: _orders);
                final o = _orders[index - 1];
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
                leading: Icon(switch (mode) {
                  MockMode.normal => Icons.list_alt,
                  MockMode.slow => Icons.hourglass_bottom,
                  MockMode.empty => Icons.inbox_outlined,
                  MockMode.error => Icons.error_outline,
                }),
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
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Строка-сводка над лентой: сколько заказов и сколько из них срочных.
class _FeedSummary extends StatelessWidget {
  const _FeedSummary({required this.orders});
  final List<Order> orders;

  @override
  Widget build(BuildContext context) {
    final hot = orders.where((o) => o.urgency.isHot).length;
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 2),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
                color: AppColors.success, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            'В ленте: ${orders.length}',
            style: const TextStyle(
                color: AppColors.muted, fontWeight: FontWeight.w600),
          ),
          if (hot > 0) ...[
            const SizedBox(width: 10),
            AppPill(
              label: 'горящих: $hot',
              color: AppColors.error,
              icon: Icons.bolt,
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ВИДЖЕТЫ ЛЕНТЫ
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
  const TmpOrderCard(
      {super.key, required this.order, this.onTap, this.onRespond});

  final Order order;
  final VoidCallback? onTap;

  /// Кнопка «Откликнуться» (рисует только лента, если передан колбэк).
  final VoidCallback? onRespond;

  /// Дедлайн взятия заказа: immediate — час от создания, текущий — три часа.
  /// 🔴 Баг-репорт 25.09 («баг с временем»): дедлайн не может быть позже
  /// начала работ — ограничиваем сверху timeStart и не рисуем просроченный.
  DateTime? get _takeDeadline {
    final base =
        order.createdAt ?? order.timeStart.subtract(const Duration(hours: 1));
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
    final sameDay = DateTime(d.year, d.month, d.day) ==
        DateTime(now.year, now.month, now.day);
    if (!sameDay) return AppFormat.relativeDay(d);
    return AppFormat.hhmm(d);
  }

  bool get _canRespond =>
      onRespond != null &&
      order.isOpenForResponse &&
      !order.clientIsMe &&
      (order.myResponseStatus == null ||
          order.myResponseStatus == ResponseStatus.declined ||
          order.myResponseStatus == ResponseStatus.expired);

  @override
  Widget build(BuildContext context) {
    final takeDeadline = _takeDeadline;
    return AppCard(
      onTap: onTap,
      accent: order.urgency.isHot ? AppColors.error : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TmpUrgencyBadge(urgency: order.urgency),
              const Spacer(),
              const Icon(Icons.schedule, size: 16, color: AppColors.muted),
              const SizedBox(width: 5),
              Text(
                AppFormat.relativeDay(order.timeStart),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            order.address,
            style: const TextStyle(
              fontSize: 17,
              height: 1.25,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            order.taskTitle,
            style: const TextStyle(
                fontSize: 14, height: 1.35, color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          // Wrap, а не Row: на узком экране (376–390 px) строка не должна
          // вылезать в горизонтальную прокрутку — бага поймана на скрине.
          Wrap(
            spacing: 12,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              MetaItem(
                icon: Icons.groups_2_outlined,
                text: '${order.peopleCount} чел.',
              ),
              MetaItem(
                icon: Icons.timelapse,
                text: AppFormat.duration(order.plannedDurationMin),
              ),
              if (order.porterTariffHint != null)
                MetaItem(
                  icon: Icons.payments_outlined,
                  text: order.porterTariffHint!,
                  color: AppColors.success,
                  bold: true,
                ),
              if (takeDeadline != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.errorSoft,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer_outlined,
                          size: 15, color: AppColors.error),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          'Успеть взять до ${_takeDeadlineLabel(takeDeadline)}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          // Матвей, блок 2: кнопка/статус зависят от my_response_status.
          if (order.myResponseStatus != null) ...[
            const SizedBox(height: 12),
            _responseNote(order.myResponseStatus!),
          ],
          // MVP «отклик + одобрение»: откликнуться можно, пока заказ открыт
          // и моего живого отклика нет (null / отклонён / истёк).
          if (_canRespond) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('feed_respond_btn'),
                onPressed: onRespond,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(64, 44),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                child: const Text('Откликнуться · указать ETA'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _responseNote(ResponseStatus status) {
    final (text, color, bg, icon) = switch (status) {
      ResponseStatus.pending => (
          'Отклик отправлен, ждём одобрения диспетчера',
          AppColors.warning,
          AppColors.warningSoft,
          Icons.hourglass_top,
        ),
      ResponseStatus.declined => (
          'Отклик отклонён — можно откликнуться снова',
          AppColors.error,
          AppColors.errorSoft,
          Icons.cancel_outlined,
        ),
      ResponseStatus.approved => (
          'Вы в бригаде, заказ в «Моих»',
          AppColors.success,
          AppColors.successSoft,
          Icons.check_circle_outline,
        ),
      ResponseStatus.expired => (
          'Отклик истёк — можно откликнуться снова',
          AppColors.error,
          AppColors.errorSoft,
          Icons.history_toggle_off,
        ),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              key: const Key('feed_my_response_chip'),
              style: TextStyle(
                fontSize: 13,
                height: 1.3,
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TmpUrgencyBadge extends StatelessWidget {
  const TmpUrgencyBadge({super.key, required this.urgency});
  final OrderUrgency urgency;

  @override
  Widget build(BuildContext context) => UrgencyBadge(urgency: urgency);
}

/// Скелетон ленты: повторяет форму карточки заказа.
class TmpShimmerList extends StatelessWidget {
  const TmpShimmerList({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => const AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Skeleton(width: 78, height: 22, radius: 11),
                Spacer(),
                Skeleton(width: 96),
              ],
            ),
            SizedBox(height: 14),
            Skeleton(width: 220, height: 18),
            SizedBox(height: 8),
            Skeleton(width: 160),
            SizedBox(height: 14),
            Row(
              children: [
                Skeleton(width: 60),
                SizedBox(width: 14),
                Skeleton(width: 60),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class TmpEmpty extends StatelessWidget {
  const TmpEmpty(
      {super.key, required this.title, required this.body, this.onRetry});
  final String title;
  final String body;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => StateView(
        icon: Icons.inbox_outlined,
        title: Text(title),
        body: Text(body),
        action: onRetry == null
            ? null
            : FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 20),
                label: const Text('Обновить'),
              ),
      );
}

class TmpError extends StatelessWidget {
  const TmpError({super.key, required this.failure, this.onRetry});
  final AppFailure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => StateView(
        icon: Icons.cloud_off_outlined,
        color: AppColors.error,
        title: const Text('Не получилось загрузить'),
        // Текст ошибки приходит готовым из AppFailure — не сочиняем здесь.
        body: Text(failure.message),
        action: onRetry == null
            ? null
            : FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 20),
                label: const Text('Повторить'),
              ),
      );
}
