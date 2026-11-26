/// Определение города по ПРИБЛИЗИТЕЛЬНОЙ геопозиции.
///
/// Приватность (см. Политику, п. 3): координаты используются только на
/// телефоне и никуда не отправляются — сервер получает лишь название города
/// (Томск / Новосибирск). Разрешение спрашиваем, только когда человек сам
/// нажал «Определить», а не при запуске.
library;

import 'package:geolocator/geolocator.dart';

import '../../features/order_flow/domain/models.dart';
import 'service_cities.dart';

enum CityLookupOutcome {
  /// Город найден.
  found,

  /// Геопозиция есть, но рядом нет городов, где мы работаем.
  outside,

  /// Человек не дал доступ к геопозиции.
  denied,

  /// Геолокация выключена или недоступна на устройстве.
  unavailable,
}

class CityLookup {
  const CityLookup(this.outcome, [this.city]);
  final CityLookupOutcome outcome;
  final ServiceCity? city;
}

abstract class CityLocator {
  Future<CityLookup> detect();
}

/// Реализация на пакете geolocator: точность «низкая» (≈ километры).
class GeolocatorCityLocator implements CityLocator {
  const GeolocatorCityLocator();

  @override
  Future<CityLookup> detect() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const CityLookup(CityLookupOutcome.unavailable);
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return const CityLookup(CityLookupOutcome.denied);
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 15),
        ),
      );
      final city = detectServiceCity(
          GeoPoint(lat: pos.latitude, lng: pos.longitude));
      return city == null
          ? const CityLookup(CityLookupOutcome.outside)
          : CityLookup(CityLookupOutcome.found, city);
    } catch (_) {
      return const CityLookup(CityLookupOutcome.unavailable);
    }
  }
}
