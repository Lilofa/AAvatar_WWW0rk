/// Города, где работает «Аватар» (avagruz.ru: «В Томске и Новосибирске,
/// включая область»). Центры и радиусы — для определения города по
/// приблизительной геопозиции и для карты.
library;

import 'dart:math' as math;

import '../../features/order_flow/domain/models.dart';

class ServiceCity {
  const ServiceCity({
    required this.name,
    required this.center,
    required this.radiusKm,
  });

  final String name;
  final GeoPoint center;

  /// Город вместе с ближними пригородами («включая область» — заказы туда
  /// тоже берём, но город человека считаем ближайшим центром в этом радиусе).
  final double radiusKm;
}

const List<ServiceCity> serviceCities = [
  ServiceCity(
    name: 'Томск',
    center: GeoPoint(lat: 56.4847, lng: 84.9482),
    radiusKm: 60,
  ),
  ServiceCity(
    name: 'Новосибирск',
    center: GeoPoint(lat: 55.0302, lng: 82.9204),
    radiusKm: 70,
  ),
];

ServiceCity? serviceCityByName(String? name) {
  for (final c in serviceCities) {
    if (c.name == name) return c;
  }
  return null;
}

/// Расстояние по поверхности Земли, км (формула гаверсинусов).
double distanceKm(GeoPoint a, GeoPoint b) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(b.lat - a.lat);
  final dLng = rad(b.lng - a.lng);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(a.lat)) * math.cos(rad(b.lat)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.min(1, math.sqrt(h)));
}

/// Город обслуживания для точки или null, если человек далеко от всех городов.
/// Считается на телефоне: координаты никуда не отправляются.
ServiceCity? detectServiceCity(GeoPoint p) {
  ServiceCity? best;
  var bestKm = double.infinity;
  for (final c in serviceCities) {
    final km = distanceKm(p, c.center);
    if (km <= c.radiusKm && km < bestKm) {
      best = c;
      bestKm = km;
    }
  }
  return best;
}
