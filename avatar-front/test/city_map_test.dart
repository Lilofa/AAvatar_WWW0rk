/// Карта города с заказами и определение города (26.11.2026).
library;

import 'package:avatar_app/core/geo/city_locator.dart';
import 'package:avatar_app/core/geo/service_cities.dart';
import 'package:avatar_app/data/mock_orders_repository.dart';
import 'package:avatar_app/features/city_map/presentation/city_picker.dart';
import 'package:avatar_app/features/order_feed/presentation/order_feed_screen.dart';
import 'package:avatar_app/features/order_flow/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLocator implements CityLocator {
  _FakeLocator(this.result);
  final CityLookup result;
  int calls = 0;

  @override
  Future<CityLookup> detect() async {
    calls++;
    return result;
  }
}

void main() {
  setUp(() {
    MockControls.instant = true;
    MockControls.mode = MockMode.normal;
    MockControls.randomErrorEveryN = 0;
    MockControls.simulateOffline = false;
    MockControls.simulateDispatcher = false;
    MockControls.demoCity = null;
  });

  tearDown(() {
    MockControls.instant = false;
    MockControls.simulateDispatcher = true;
    MockControls.demoCity = null;
  });

  Future<void> settle(WidgetTester tester, [int frames = 6]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('город по координатам (на телефоне)', () {
    test('центр Томска и Северск → Томск', () {
      expect(detectServiceCity(const GeoPoint(lat: 56.47, lng: 84.95))?.name, 'Томск');
      expect(detectServiceCity(const GeoPoint(lat: 56.60, lng: 84.88))?.name, 'Томск');
    });
    test('Новосибирск и Бердск → Новосибирск', () {
      expect(detectServiceCity(const GeoPoint(lat: 55.03, lng: 82.92))?.name, 'Новосибирск');
      expect(detectServiceCity(const GeoPoint(lat: 54.76, lng: 83.10))?.name, 'Новосибирск');
    });
    test('Москва и Кемерово — не наши города', () {
      expect(detectServiceCity(const GeoPoint(lat: 55.75, lng: 37.62)), isNull);
      expect(detectServiceCity(const GeoPoint(lat: 55.35, lng: 86.09)), isNull);
    });
  });

  Future<void> pumpPicker(WidgetTester tester, CityLocator locator) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: CityPicker(repository: MockOrdersRepository(), locator: locator),
        ),
      ),
    ));
    await settle(tester);
  }

  testWidgets('«Определить автоматически» сохраняет найденный город', (tester) async {
    final loc = _FakeLocator(CityLookup(CityLookupOutcome.found, serviceCities.first));
    await pumpPicker(tester, loc);
    expect(find.text('Выбрать город'), findsOneWidget);

    await tester.tap(find.byKey(const Key('city_chip')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('city_detect')));
    await settle(tester);

    expect(loc.calls, 1);
    expect(MockControls.demoCity, 'Томск');
    expect(find.text('Томск'), findsOneWidget);
  });

  testWidgets('нет доступа к геопозиции — подсказка, город не меняется', (tester) async {
    final loc = _FakeLocator(const CityLookup(CityLookupOutcome.denied));
    await pumpPicker(tester, loc);
    await tester.tap(find.byKey(const Key('city_chip')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('city_detect')));
    await settle(tester);

    expect(MockControls.demoCity, isNull);
    expect(find.textContaining('Нет доступа к геопозиции'), findsOneWidget);
  });

  testWidgets('выбор города вручную, без геопозиции', (tester) async {
    final loc = _FakeLocator(const CityLookup(CityLookupOutcome.unavailable));
    await pumpPicker(tester, loc);
    await tester.tap(find.byKey(const Key('city_chip')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('city_option_Новосибирск')));
    await settle(tester);

    expect(loc.calls, 0);
    expect(MockControls.demoCity, 'Новосибирск');
  });

  testWidgets('лента грузчика: переключение «На карте», точки заказов, карточка по тапу',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);

    String? opened;
    await tester.pumpWidget(MaterialApp(
      home: OrderFeedScreen(
        repository: MockOrdersRepository(),
        mapTileUrl: null,
        onOpenOrder: (id) => opened = id,
      ),
    ));
    await settle(tester);

    await tester.tap(find.byKey(const Key('feed_map_toggle')));
    await settle(tester);
    expect(find.byKey(const Key('orders_map')), findsOneWidget);

    final pins = find.byWidgetPredicate(
        (w) => w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('map_pin_'));
    expect(pins, findsWidgets);

    await tester.tap(pins.first, warnIfMissed: false);
    await settle(tester);
    await tester.tap(find.byKey(const Key('map_sheet_open')));
    await settle(tester);
    expect(opened, isNotNull);

    // Обратно к списку.
    await tester.tap(find.byKey(const Key('feed_map_toggle')));
    await settle(tester);
    expect(find.byKey(const Key('orders_map')), findsNothing);
  });
}
