/// ТЕСТЫ ТАРИФА: золотые значения формулы RPC quote_order (Матвей, 12.09).
///
/// Если бэк поменяет формулу — эти тесты упадут первыми, и мы сверим цифры
/// до того, как калькулятор начнёт врать заказчику.
library;

import 'package:avatar_app/features/order_flow/domain/enums.dart';
import 'package:avatar_app/features/order_flow/domain/pricing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('база + работа без коэффициента: 1 человек, 30 мин, текущий, без транспорта', () {
    final t = computeTariff(
      peopleCount: 1,
      plannedDurationMin: 30,
      urgency: OrderUrgency.current,
    );
    // planned_hours = 1, work = 400, ×1.0, +500, +0
    expect(t.plannedHours, 1);
    expect(t.work, 400);
    expect(t.total, 900);
  });

  test('срочный с газелью: 2 человека, 90 мин', () {
    final t = computeTariff(
      peopleCount: 2,
      plannedDurationMin: 90,
      urgency: OrderUrgency.urgent,
      transport: TransportType.gazelle,
    );
    // planned_hours = 2, work = 400×2×2 = 1600, ×1.5 = 2400, +500 +1500
    expect(t.plannedHours, 2);
    expect(t.work, 1600);
    expect(t.total, 4400);
  });

  test('заранее с фурой: 3 человека, 120 мин', () {
    final t = computeTariff(
      peopleCount: 3,
      plannedDurationMin: 120,
      urgency: OrderUrgency.advance,
      transport: TransportType.truck,
    );
    // planned_hours = 2, work = 400×3×2 = 2400, ×0.8 = 1920, +500 +3000
    expect(t.total, 5420);
  });

  test('округление часов вверх: 61 мин = 2 часа', () {
    final t = computeTariff(
      peopleCount: 2,
      plannedDurationMin: 61,
      urgency: OrderUrgency.preliminary,
    );
    // planned_hours = 2, work = 1600, ×0.9 = 1440, +500
    expect(t.plannedHours, 2);
    expect(t.total, 1940);
  });

  test('транспорт_none не добавляет ничего', () {
    final a = computeTariff(peopleCount: 1, plannedDurationMin: 60, urgency: OrderUrgency.current);
    final b = computeTariff(
      peopleCount: 1,
      plannedDurationMin: 60,
      urgency: OrderUrgency.current,
      transport: TransportType.none,
    );
    expect(a.total, b.total);
    expect(a.transportFee, 0);
  });
}
