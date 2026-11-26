/// Город пользователя: чип «📍 Томск» и меню «Определить автоматически /
/// выбрать вручную». Используется на карте заказов и в кабинете.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/geo/city_locator.dart';
import '../../../core/geo/service_cities.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/orders_repository.dart';

class CityPicker extends StatefulWidget {
  const CityPicker({
    super.key,
    required this.repository,
    this.locator = const GeolocatorCityLocator(),
    this.onCityChanged,
  });

  final OrdersRepository repository;
  final CityLocator locator;
  final ValueChanged<ServiceCity>? onCityChanged;

  @override
  State<CityPicker> createState() => _CityPickerState();
}

class _CityPickerState extends State<CityPicker> {
  String? _city;
  bool _busy = false;
  StreamSubscription<UserProfile?>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.repository.watchCurrentUser().listen((p) {
      if (mounted) setState(() => _city = p?.city);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _say(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _save(ServiceCity c) async {
    setState(() => _busy = true);
    try {
      await widget.repository.updateMyCity(c.name);
      if (!mounted) return;
      setState(() => _city = c.name);
      widget.onCityChanged?.call(c);
    } on AppFailure catch (f) {
      if (mounted) _say(f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _detect() async {
    setState(() => _busy = true);
    final res = await widget.locator.detect();
    if (!mounted) return;
    setState(() => _busy = false);
    switch (res.outcome) {
      case CityLookupOutcome.found:
        await _save(res.city!);
        if (mounted) _say('Ваш город — ${res.city!.name}.');
      case CityLookupOutcome.outside:
        _say('Рядом нет городов, где мы работаем. Выберите город вручную.');
      case CityLookupOutcome.denied:
        _say('Нет доступа к геопозиции. Выберите город вручную '
            'или разрешите доступ в настройках телефона.');
      case CityLookupOutcome.unavailable:
        _say('Не удалось определить местоположение. Выберите город вручную.');
    }
  }

  Future<void> _open() async {
    final choice = await showModalBottomSheet<Object>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text('Ваш город',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            ListTile(
              key: const Key('city_detect'),
              leading: const Icon(Icons.my_location, color: AppColors.brandBlue),
              title: const Text('Определить автоматически'),
              subtitle: const Text(
                  'Приблизительно, по геопозиции. Координаты остаются на телефоне.'),
              onTap: () => Navigator.of(ctx).pop(true),
            ),
            const Divider(height: 1),
            for (final c in serviceCities)
              ListTile(
                key: Key('city_option_${c.name}'),
                leading: Icon(
                  c.name == _city ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: AppColors.brandBlue,
                ),
                title: Text(c.name),
                onTap: () => Navigator.of(ctx).pop(c),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == true) {
      await _detect();
    } else if (choice is ServiceCity) {
      await _save(choice);
    }
  }

  @override
  Widget build(BuildContext context) => ActionChip(
        key: const Key('city_chip'),
        avatar: _busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.place_outlined, size: 18, color: AppColors.brandBlue),
        label: Text(_city ?? 'Выбрать город'),
        backgroundColor: AppColors.surface,
        onPressed: _busy ? null : _open,
      );
}
