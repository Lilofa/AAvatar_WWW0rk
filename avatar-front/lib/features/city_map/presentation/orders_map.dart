/// Карта города с заказами (OpenStreetMap, пакет flutter_map).
///
/// Грузчик видит открытые заказы точками на карте своего города; заказчик —
/// свои заказы. Точки берутся из координат адреса (подсказки адресов при
/// создании заказа). Тайлы — tile.openstreetmap.org с указанием авторства;
/// при большом трафике заменить [osmTileUrl] на свой сервер тайлов или
/// MapTiler — остальной код не меняется.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/geo/city_locator.dart';
import '../../../core/geo/service_cities.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../data/orders_repository.dart';
import '../../order_flow/domain/models.dart';
import 'city_picker.dart';

const String osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

class OrdersMap extends StatefulWidget {
  const OrdersMap({
    super.key,
    required this.orders,
    required this.repository,
    this.onOpenOrder,
    this.tileUrl = osmTileUrl,
    this.locator = const GeolocatorCityLocator(),
  });

  final List<Order> orders;
  final OrdersRepository repository;
  final ValueChanged<Order>? onOpenOrder;

  /// null — без подложки (виджет-тесты: без сети).
  final String? tileUrl;
  final CityLocator locator;

  @override
  State<OrdersMap> createState() => _OrdersMapState();
}

class _OrdersMapState extends State<OrdersMap> {
  final MapController _map = MapController();
  String? _profileCity;
  bool _ready = false;

  static LatLng _ll(GeoPoint p) => LatLng(p.lat, p.lng);

  List<Order> get _placed => widget.orders.where((o) => o.coords != null).toList();

  @override
  void initState() {
    super.initState();
    widget.repository.watchCurrentUser().first.then((p) {
      if (!mounted) return;
      setState(() => _profileCity = p?.city);
      final c = serviceCityByName(p?.city);
      if (c != null && _ready) _map.move(_ll(c.center), 11.5);
    }).catchError((_) {});
  }

  /// Центр: город из профиля → середина точек заказов → Томск.
  LatLng get _initialCenter {
    final c = serviceCityByName(_profileCity);
    if (c != null) return _ll(c.center);
    final pts = _placed;
    if (pts.isNotEmpty) {
      final lat = pts.map((o) => o.coords!.lat).reduce((a, b) => a + b) / pts.length;
      final lng = pts.map((o) => o.coords!.lng).reduce((a, b) => a + b) / pts.length;
      return LatLng(lat, lng);
    }
    return _ll(serviceCities.first.center);
  }

  void _show(Order o) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            key: Key('map_sheet_${o.id}'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(o.taskTitle,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                  if (o.urgency.isHot)
                    const AppPill(label: 'Срочно', color: AppColors.error),
                ],
              ),
              const SizedBox(height: 6),
              Text(o.address, style: const TextStyle(color: AppColors.inkSoft)),
              const SizedBox(height: 4),
              Text(
                '${AppFormat.relativeDay(o.timeStart)}, ${AppFormat.hhmm(o.timeStart)} · '
                '${o.peopleCount} чел. · ${AppFormat.duration(o.plannedDurationMin)}',
                style: const TextStyle(color: AppColors.muted),
              ),
              if (widget.onOpenOrder != null) ...[
                const SizedBox(height: 14),
                FilledButton(
                  key: const Key('map_sheet_open'),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    widget.onOpenOrder!(o);
                  },
                  child: const Text('Открыть заказ'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _pin(Order o) {
    final hot = o.urgency.isHot;
    return GestureDetector(
      key: Key('map_pin_${o.id}'),
      onTap: () => _show(o),
      child: Semantics(
        button: true,
        label: 'Заказ: ${o.address}',
        child: Icon(
          Icons.location_on,
          size: 40,
          color: hot ? AppColors.error : AppColors.brandBlue,
          shadows: const [Shadow(blurRadius: 4, color: Color(0x55000000))],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final placed = _placed;
    final missing = widget.orders.length - placed.length;
    return Stack(
      key: const Key('orders_map'),
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: _initialCenter,
            initialZoom: 11.5,
            minZoom: 8,
            maxZoom: 18,
            onMapReady: () => _ready = true,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            if (widget.tileUrl != null)
              TileLayer(
                urlTemplate: widget.tileUrl,
                userAgentPackageName: 'ru.avatar.avatarApp',
                maxZoom: 19,
              ),
            MarkerLayer(
              markers: [
                for (final o in placed)
                  Marker(
                    point: _ll(o.coords!),
                    width: 44,
                    height: 44,
                    alignment: Alignment.topCenter,
                    child: _pin(o),
                  ),
              ],
            ),
            // Авторство обязательно по правилам OSM; короткая форма разрешена.
            const Align(
              alignment: Alignment.bottomRight,
              child: ColoredBox(
                color: Color(0xCCFFFFFF),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text(
                    '© OpenStreetMap',
                    key: Key('map_attribution'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
                  ),
                ),
              ),
            ),
          ],
        ),
        Positioned(
          left: 12,
          top: 12,
          right: 12,
          child: Row(
            children: [
              CityPicker(
                repository: widget.repository,
                locator: widget.locator,
                onCityChanged: (c) {
                  setState(() => _profileCity = c.name);
                  if (_ready) _map.move(_ll(c.center), 11.5);
                },
              ),
              const Spacer(),
              if (missing > 0)
                AppPill(
                  key: const Key('map_missing'),
                  label: 'без точки: $missing',
                  color: AppColors.muted,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Отдельный экран «Мои заказы на карте» для заказчика.
class OrdersMapScreen extends StatelessWidget {
  const OrdersMapScreen({
    super.key,
    required this.title,
    required this.orders,
    required this.repository,
    this.onOpenOrder,
  });

  final String title;
  final List<Order> orders;
  final OrdersRepository repository;
  final ValueChanged<Order>? onOpenOrder;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: OrdersMap(
          orders: orders,
          repository: repository,
          onOpenOrder: onOpenOrder,
        ),
      );
}
