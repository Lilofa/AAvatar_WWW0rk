/// UI-КИТ «АВАТАР»: общие кирпичи экранов.
///
/// Карточка, плашки статусов, баннеры, состояния empty/error, скелетоны,
/// бренд-знак и градиентная «шапка». Все цвета — из [AppColors].
library;

import 'package:flutter/material.dart';

import '../../features/order_flow/domain/enums.dart';
import '../theme/app_theme.dart';

/// Белая карточка с мягкой тенью. С [onTap] — кликабельная (чернила внутри).
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.color = AppColors.surface,
    this.accent,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color color;

  /// Цветная полоса слева (срочность, статус).
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.lg);
    Widget content = Padding(padding: padding, child: child);
    if (accent != null) {
      content = Stack(
        children: [
          content,
          Positioned(
            left: 0,
            top: 14,
            bottom: 14,
            child: Container(
              width: 4,
              decoration: BoxDecoration(
                color: accent,
                borderRadius:
                    const BorderRadius.horizontal(right: Radius.circular(4)),
              ),
            ),
          ),
        ],
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: AppShadows.card,
      ),
      child: Material(
        color: color,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

/// Маленькая плашка-статус: тонированный фон + цветной текст.
class AppPill extends StatelessWidget {
  const AppPill({
    super.key,
    required this.label,
    this.color = AppColors.brandBlue,
    this.icon,
    this.solid = false,
  });

  final String label;
  final Color color;
  final IconData? icon;

  /// true — сплошная заливка (для срочных).
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final fg = solid ? Colors.white : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: solid ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              height: 1.2,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// Цвет и подпись срочности — единый источник для ленты, пульта и заказа.
extension OrderUrgencyUi on OrderUrgency {
  String get label => switch (this) {
        OrderUrgency.urgent => 'Срочно',
        OrderUrgency.replacement => 'Замена',
        OrderUrgency.current => 'Текущий',
        OrderUrgency.preliminary => 'Предвар.',
        OrderUrgency.advance => 'Заранее',
      };

  Color get color => switch (this) {
        OrderUrgency.urgent || OrderUrgency.replacement => AppColors.error,
        OrderUrgency.current => AppColors.brandBlue,
        OrderUrgency.preliminary => AppColors.muted,
        OrderUrgency.advance => AppColors.success,
      };

  bool get isHot =>
      this == OrderUrgency.urgent || this == OrderUrgency.replacement;

  IconData get icon => switch (this) {
        OrderUrgency.urgent => Icons.bolt,
        OrderUrgency.replacement => Icons.swap_horiz,
        OrderUrgency.current => Icons.schedule,
        OrderUrgency.preliminary => Icons.event_note,
        OrderUrgency.advance => Icons.event_available,
      };
}

/// Человеческая подпись статуса заказа (вместо wire-значений бэка).
extension OrderStatusUi on OrderStatus {
  String get label => switch (this) {
        OrderStatus.new_ => 'Ждёт бригаду',
        OrderStatus.approved => 'Бригада собрана',
        OrderStatus.inProgress => 'В работе',
        OrderStatus.completed => 'Выполнен',
        OrderStatus.cancelled => 'Отменён',
      };

  Color get color => switch (this) {
        OrderStatus.new_ => AppColors.warning,
        OrderStatus.approved => AppColors.brandBlue,
        OrderStatus.inProgress => AppColors.brandBlue,
        OrderStatus.completed => AppColors.success,
        OrderStatus.cancelled => AppColors.muted,
      };

  IconData get icon => switch (this) {
        OrderStatus.new_ => Icons.hourglass_top,
        OrderStatus.approved => Icons.groups_2_outlined,
        OrderStatus.inProgress => Icons.local_shipping_outlined,
        OrderStatus.completed => Icons.check_circle_outline,
        OrderStatus.cancelled => Icons.cancel_outlined,
      };
}

class UrgencyBadge extends StatelessWidget {
  const UrgencyBadge({super.key, required this.urgency});
  final OrderUrgency urgency;

  @override
  Widget build(BuildContext context) => AppPill(
        label: urgency.label,
        color: urgency.color,
        icon: urgency.icon,
        solid: urgency.isHot,
      );
}

/// Иконка + подпись в одну строку (время, люди, тариф).
class MetaItem extends StatelessWidget {
  const MetaItem({
    super.key,
    required this.icon,
    required this.text,
    this.color = AppColors.inkSoft,
    this.bold = false,
  });

  final IconData icon;
  final String text;
  final Color color;
  final bool bold;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color.withValues(alpha: 0.85)),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.25,
                color: color,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      );
}

/// Заголовок секции списка.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, right: 4, bottom: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  color: AppColors.ink,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

enum BannerTone { error, warning, info, success }

/// Плашка-сообщение внутри экрана (ошибка формы, офлайн, подсказка).
class AppBanner extends StatelessWidget {
  const AppBanner({
    super.key,
    this.message,
    this.child,
    this.tone = BannerTone.error,
    this.icon,
    this.margin = EdgeInsets.zero,
  }) : assert(message != null || child != null);

  final String? message;
  final Widget? child;
  final BannerTone tone;
  final IconData? icon;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final (fg, bg, defaultIcon) = switch (tone) {
      BannerTone.error => (
          AppColors.error,
          AppColors.errorSoft,
          Icons.error_outline
        ),
      BannerTone.warning => (
          AppColors.warning,
          AppColors.warningSoft,
          Icons.warning_amber_rounded
        ),
      BannerTone.info => (
          AppColors.brandBlue,
          AppColors.brandBlueSoft,
          Icons.info_outline
        ),
      BannerTone.success => (
          AppColors.success,
          AppColors.successSoft,
          Icons.check_circle_outline
        ),
    };
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: fg.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? defaultIcon, color: fg, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: child ??
                Text(
                  message!,
                  style: const TextStyle(
                      color: AppColors.ink, height: 1.35, fontSize: 14),
                ),
          ),
        ],
      ),
    );
  }
}

/// Полноэкранное состояние: иконка в круге, заголовок, текст, действие.
/// Используется для empty и error — отличаются тоном.
class StateView extends StatelessWidget {
  const StateView({
    super.key,
    required this.icon,
    this.title,
    this.body,
    this.action,
    this.color = AppColors.brandBlue,
  });

  final IconData icon;
  final Widget? title;
  final Widget? body;
  final Widget? action;
  final Color color;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 40, color: color),
              ),
              if (title != null) ...[
                const SizedBox(height: 20),
                DefaultTextStyle.merge(
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: AppColors.ink,
                  ),
                  child: title!,
                ),
              ],
              if (body != null) ...[
                const SizedBox(height: 8),
                DefaultTextStyle.merge(
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 14, height: 1.45, color: AppColors.muted),
                  child: body!,
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: 24),
                action!,
              ],
            ],
          ),
        ),
      );
}

/// Скелетон-плейсхолдер с «дыханием» (пока грузятся данные).
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.width, this.height = 14, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween<double>(begin: 0.45, end: 1)
            .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        ),
      );
}

/// Бренд-знак: фургон в скруглённой плитке.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 88, this.onDark = false});

  final double size;

  /// На синем фоне — жёлтая плитка; на светлом — синяя.
  final bool onDark;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: onDark ? AppColors.brandYellow : null,
          gradient: onDark ? null : AppColors.brandGradient,
          borderRadius: BorderRadius.circular(size * 0.3),
          boxShadow: const [
            BoxShadow(
                color: Color(0x33000000),
                blurRadius: 24,
                offset: Offset(0, 10)),
          ],
        ),
        child: Icon(
          Icons.local_shipping_rounded,
          size: size * 0.5,
          color: onDark ? AppColors.brandBlueDeep : AppColors.brandYellow,
        ),
      );
}

/// Синяя градиентная поверхность с декоративными кругами (шапки, промо).
class BrandSurface extends StatelessWidget {
  const BrandSurface({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: borderRadius,
        child: DecoratedBox(
          decoration: const BoxDecoration(gradient: AppColors.brandGradient),
          child: Stack(
            children: [
              Positioned(
                right: -60,
                top: -70,
                child: _circle(200, Colors.white.withValues(alpha: 0.06)),
              ),
              Positioned(
                right: 30,
                bottom: -50,
                child:
                    _circle(110, AppColors.brandYellow.withValues(alpha: 0.14)),
              ),
              Positioned(
                left: -40,
                bottom: -60,
                child: _circle(140, Colors.white.withValues(alpha: 0.05)),
              ),
              Padding(padding: padding, child: child),
            ],
          ),
        ),
      );

  static Widget _circle(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// Круглый аватар с инициалом.
class InitialAvatar extends StatelessWidget {
  const InitialAvatar({
    super.key,
    required this.name,
    this.size = 44,
    this.background = AppColors.brandBlueSoft,
    this.foreground = AppColors.brandBlue,
  });

  final String name;
  final double size;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? 'А' : trimmed[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Text(
        initial,
        style: TextStyle(
          color: foreground,
          fontSize: size * 0.4,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Индикатор «занято» внутри кнопки.
class ButtonSpinner extends StatelessWidget {
  const ButtonSpinner({super.key, this.color = Colors.white});
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          color: color,
          backgroundColor: Colors.transparent,
        ),
      );
}

/// Форматирование дат без intl — одно место на всё приложение.
abstract final class AppFormat {
  static String hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static String ddmm(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';

  /// «45 мин» / «2 ч» / «1 ч 30 мин».
  static String duration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '$m мин';
    return m == 0 ? '$h ч' : '$h ч $m мин';
  }

  /// «Сегодня, 15:00» / «Завтра, 09:00» / «12.09, 09:00».
  static String relativeDay(DateTime d, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final day = DateTime(d.year, d.month, d.day);
    if (day == today) return 'Сегодня, ${hhmm(d)}';
    if (day == today.add(const Duration(days: 1))) return 'Завтра, ${hhmm(d)}';
    return '${d.day}.${d.month.toString().padLeft(2, '0')}, ${hhmm(d)}';
  }
}
