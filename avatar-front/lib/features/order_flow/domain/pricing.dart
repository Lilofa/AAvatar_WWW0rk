/// ТАРИФ: единственная клиентская копия формулы RPC quote_order (Матвей, 12.09).
///
/// Источник правды — бэкенд. Здесь формула нужна, чтобы мок и тесты вели себя
/// как бэк, и чтобы UI калькулятора совпадал с ценой заказа цифра в цифру.
///
///   base_fee        = 500
///   planned_hours   = ceil(planned_duration_min / 60)
///   work            = 400 ₽/час × people_count × planned_hours
///   subtotal        = base_fee + work × urgency_multiplier + transport_fee
///   total           = round(subtotal, 2)
library;

import 'enums.dart';

class TariffBreakdown {
  const TariffBreakdown({
    required this.baseFee,
    required this.plannedHours,
    required this.work,
    required this.multiplier,
    required this.transportFee,
    required this.total,
  });

  final double baseFee;
  final int plannedHours;
  final double work;
  final double multiplier;
  final double transportFee;
  final double total;

  /// Строки для экрана калькулятора заказчика.
  List<(String, double)> get lines => [
        ('База', baseFee),
        ('Работа: $plannedHours ч × люди', work),
        if (multiplier != 1.0) ('Коэффициент срочности ×$multiplier', work * (multiplier - 1)),
        if (transportFee > 0) ('Транспорт', transportFee),
      ];
}

TariffBreakdown computeTariff({
  required int peopleCount,
  required int plannedDurationMin,
  required OrderUrgency urgency,
  TransportType transport = TransportType.none,
}) {
  const baseFee = 500.0;
  const perPersonHour = 400.0;
  final plannedHours = plannedDurationMin <= 0 ? 0 : (plannedDurationMin / 60).ceil();
  final work = perPersonHour * peopleCount * plannedHours;
  final multiplier = urgencyMultiplier(urgency);
  final transportFee = transport.feeRub.toDouble();
  final subtotal = baseFee + work * multiplier + transportFee;
  return TariffBreakdown(
    baseFee: baseFee,
    plannedHours: plannedHours,
    work: work,
    multiplier: multiplier,
    transportFee: transportFee,
    total: (subtotal * 100).round() / 100,
  );
}
