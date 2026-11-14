/// ВИЗАРД СОЗДАНИЯ ЗАЯВКИ (зона Артёма, MVP «создание заявки»).
///
/// Неделя 3 по плану — «ядро заказчика»; экран уже закрывает MVP-цикл:
/// адрес с автодополнением (edge search-address / Nominatim), время,
/// люди, длительность, задача, срочность, транспорт, калькулятор тарифа
/// (RPC quote_order_detailed — строки Матвея) и создание заявки.
///
/// Состояния: form / quoting(loading) / error / done.
/// 🔴 Контракт Матвея 20.09: planned_duration_min обязателен, иначе триггер
///    check_order_filled не пересчитает price при одобрении.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../data/orders_repository.dart';
import '../../order_flow/domain/enums.dart';
import '../../order_flow/domain/models.dart';

class CreateOrderScreen extends StatefulWidget {
  const CreateOrderScreen({super.key, required this.repository});

  final OrdersRepository repository;

  @override
  State<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends State<CreateOrderScreen> {
  final _address = TextEditingController();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _entrance = TextEditingController();
  final _phone = TextEditingController();
  final _comments = TextEditingController();

  Timer? _debounce;
  List<AddressSuggestion> _suggestions = const [];
  GeoPoint? _coords;

  DateTime _start = DateTime.now()
      .add(const Duration(hours: 1))
      .copyWith(second: 0, millisecond: 0);
  int _people = 2;
  int _durationMin = 60;
  OrderUrgency _urgency = OrderUrgency.current;
  TransportType _transport = TransportType.none;

  TariffQuote? _quote;
  bool _quoting = false;
  bool _sending = false;
  bool _done = false;
  AppFailure? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [
      _address,
      _title,
      _description,
      _entrance,
      _phone,
      _comments
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onAddressChanged(String v) {
    _debounce?.cancel();
    _coords = null;
    _suggestions = const [];
    if (v.trim().length < 3) return;
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final list = await widget.repository.searchAddress(query: v.trim());
        if (mounted) setState(() => _suggestions = list.take(5).toList());
      } on AppFailure {
        if (mounted) setState(() => _suggestions = const []);
      }
    });
  }

  Future<void> _quoteIt() async {
    setState(() {
      _quoting = true;
      _error = null;
    });
    try {
      final q = await widget.repository.quoteOrder(
        peopleCount: _people,
        plannedDurationMin: _durationMin,
        urgency: _urgency,
        transport: _transport,
      );
      if (mounted) setState(() => _quote = q);
    } on AppFailure catch (f) {
      if (mounted) setState(() => _error = f);
    } finally {
      if (mounted) setState(() => _quoting = false);
    }
  }

  Future<void> _submit() async {
    if (_sending) return;
    if (_address.text.trim().isEmpty) {
      setState(() => _error = Failures.validation('address', 'Укажите адрес.'));
      return;
    }
    if (_title.text.trim().isEmpty) {
      setState(() =>
          _error = Failures.validation('taskTitle', 'Что повезём/переносим?'));
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.repository.createOrder(CreateOrderRequest(
        address: _address.text.trim(),
        timeStart: _start,
        peopleCount: _people,
        plannedDurationMin: _durationMin,
        taskTitle: _title.text.trim(),
        taskDescription: _description.text.trim(),
        urgency: _urgency,
        tariff: _quote == null ? '' : '${_quote!.price.toInt()} RUB',
        entrance: _entrance.text.trim().isEmpty ? null : _entrance.text.trim(),
        transport: _transport,
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        extraComments:
            _comments.text.trim().isEmpty ? null : _comments.text.trim(),
        coords: _coords,
      ));
      if (mounted) setState(() => _done = true);
    } on AppFailure catch (f) {
      if (mounted) setState(() => _error = f);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Новая заявка')),
        body: _done ? _doneView() : _form(),
      );

  Widget _doneView() => StateView(
        key: const Key('create_done'),
        icon: Icons.check_rounded,
        color: AppColors.success,
        title: const Text('Готово'),
        body: const Text(
          'Заявка создана!\nДиспетчер одобрит — и она появится у грузчиков.',
          textAlign: TextAlign.center,
        ),
        action: FilledButton(
          key: const Key('create_done_back'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('К моим заказам'),
        ),
      );

  Widget _section({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.brandBlueSoft,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(icon, size: 18, color: AppColors.brandBlue),
                  ),
                  const SizedBox(width: 10),
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2)),
                ],
              ),
              const SizedBox(height: 14),
              ...children,
            ],
          ),
        ),
      );

  static const _fieldFill = InputDecoration(fillColor: AppColors.surfaceAlt);

  Widget _pickerTile({
    required Key key,
    required IconData icon,
    required String caption,
    required String value,
    required VoidCallback onPressed,
  }) =>
      Material(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onPressed,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: AppColors.brandBlue),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(caption,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.muted)),
                      Text(value,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _form() => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _section(
              icon: Icons.place_outlined,
              title: 'Где и когда',
              children: [
                TextField(
                  key: const Key('create_address'),
                  controller: _address,
                  onChanged: _onAddressChanged,
                  decoration: _fieldFill.copyWith(
                    labelText: 'Адрес',
                    hintText: 'Начните вводить: улица, дом',
                    prefixIcon: const Icon(Icons.search),
                  ),
                ),
                if (_suggestions.isNotEmpty)
                  Container(
                    key: const Key('create_suggest_box'),
                    margin: const EdgeInsets.only(top: 6),
                    constraints: const BoxConstraints(maxHeight: 180),
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: AppColors.border),
                      boxShadow: AppShadows.card,
                    ),
                    // Material обязателен: ListTile рисует чернила на ближайшем
                    // Material-предке, иначе debug-ассерт в тестах.
                    child: Material(
                      color: AppColors.surface,
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _suggestions.length,
                        itemBuilder: (context, i) => ListTile(
                          key: Key('create_suggest_$i'),
                          dense: true,
                          leading: const Icon(Icons.place_outlined, size: 20),
                          title: Text(_suggestions[i].title),
                          subtitle: Text(_suggestions[i].fullAddress,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => setState(() {
                            _address.text = _suggestions[i].fullAddress;
                            _coords = _suggestions[i].coords;
                            _suggestions = const [];
                          }),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _pickerTile(
                        key: const Key('create_date_btn'),
                        icon: Icons.calendar_month,
                        caption: 'Дата',
                        value:
                            '${_start.day.toString().padLeft(2, '0')}.${_start.month.toString().padLeft(2, '0')}.${_start.year}',
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _start,
                            firstDate: DateTime.now(),
                            lastDate:
                                DateTime.now().add(const Duration(days: 60)),
                          );
                          if (d != null) {
                            setState(() => _start = DateTime(d.year, d.month,
                                d.day, _start.hour, _start.minute));
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _pickerTile(
                        key: const Key('create_time_btn'),
                        icon: Icons.schedule,
                        caption: 'Время',
                        value:
                            '${_start.hour.toString().padLeft(2, '0')}:${_start.minute.toString().padLeft(2, '0')}',
                        onPressed: () async {
                          // Баг-репорт 25.09: без «странного циферблата» —
                          // сначала прямой ввод ЧЧ:ММ, циферблат — иконкой рядом.
                          final t = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(_start),
                            initialEntryMode: TimePickerEntryMode.input,
                          );
                          if (t != null) {
                            setState(() => _start = DateTime(_start.year,
                                _start.month, _start.day, t.hour, t.minute));
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
            _section(
              icon: Icons.inventory_2_outlined,
              title: 'Что делать',
              children: [
                TextField(
                  key: const Key('create_title'),
                  controller: _title,
                  decoration: _fieldFill.copyWith(
                    labelText: 'Что повезём / переносим',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('create_description'),
                  controller: _description,
                  minLines: 2,
                  maxLines: 4,
                  decoration: _fieldFill.copyWith(
                    labelText: 'Что делать (подробности)',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 14),
                _stepper(
                  label: 'Грузчиков',
                  value: '$_people',
                  minusKey: const Key('create_people_minus'),
                  plusKey: const Key('create_people_plus'),
                  onMinus: _people > 1 ? () => setState(() => _people--) : null,
                  onPlus: _people < 20 ? () => setState(() => _people++) : null,
                ),
                const Divider(height: 20),
                _stepper(
                  label: 'Длительность',
                  value:
                      '${_durationMin ~/ 60} ч ${_durationMin % 60 > 0 ? '${_durationMin % 60} мин' : ''}',
                  minusKey: const Key('create_duration_minus'),
                  plusKey: const Key('create_duration_plus'),
                  onMinus: _durationMin > 30
                      ? () => setState(() => _durationMin -= 30)
                      : null,
                  onPlus: _durationMin < 720
                      ? () => setState(() => _durationMin += 30)
                      : null,
                ),
              ],
            ),
            _section(
              icon: Icons.tune,
              title: 'Срочность и транспорт',
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final u in const [
                      OrderUrgency.urgent,
                      OrderUrgency.current,
                      OrderUrgency.preliminary,
                      OrderUrgency.advance,
                    ])
                      ChoiceChip(
                        key: Key('create_urgency_${u.name}'),
                        label: Text(switch (u) {
                          OrderUrgency.urgent => 'Срочно',
                          OrderUrgency.current => 'Текущий',
                          OrderUrgency.preliminary => 'Предварительный',
                          OrderUrgency.advance => 'Заранее',
                          OrderUrgency.replacement => 'Замена',
                        }),
                        selected: _urgency == u,
                        onSelected: (_) => setState(() {
                          _urgency = u;
                          _quote = null;
                        }),
                      ),
                  ],
                ),
                const Divider(height: 24),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in TransportType.values)
                      ChoiceChip(
                        key: Key('create_transport_${t.name}'),
                        label: Text(switch (t) {
                          TransportType.none => 'Без транспорта',
                          TransportType.gazelle => 'Газель (+1500)',
                          TransportType.truck => 'Грузовик (+3000)',
                        }),
                        selected: _transport == t,
                        onSelected: (_) => setState(() {
                          _transport = t;
                          _quote = null;
                        }),
                      ),
                  ],
                ),
              ],
            ),
            _section(
              icon: Icons.door_front_door_outlined,
              title: 'На месте',
              children: [
                TextField(
                  key: const Key('create_entrance'),
                  controller: _entrance,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _fieldFill.copyWith(
                    labelText: 'Подъезд (необязательно)',
                    prefixIcon: const Icon(Icons.meeting_room_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('create_phone'),
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: _fieldFill.copyWith(
                    labelText: 'Телефон на месте',
                    prefixIcon: const Icon(Icons.phone_outlined),
                  ),
                ),
              ],
            ),
            OutlinedButton.icon(
              key: const Key('create_quote_btn'),
              onPressed: _quoting ? null : _quoteIt,
              style: OutlinedButton.styleFrom(
                backgroundColor: AppColors.surface,
              ),
              icon: _quoting
                  ? const ButtonSpinner(color: AppColors.brandBlue)
                  : const Icon(Icons.calculate_outlined),
              label: Text(_quoting ? 'Считаем…' : 'Рассчитать тариф'),
            ),
            if (_quote != null)
              Container(
                key: const Key('create_quote_panel'),
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.brandYellowSoft,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.brandYellow, width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final l in _quote!.breakdown)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('${l.label}: ${l.amount.toInt()} ₽',
                            style: const TextStyle(color: AppColors.inkSoft)),
                      ),
                    const Divider(color: Color(0x33000000), height: 20),
                    Text(
                      'Итого: ${_quote!.price.toInt()} ₽ · ~${_quote!.hours} ч',
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2),
                    ),
                  ],
                ),
              ),
            if (_error != null)
              AppBanner(
                key: const Key('create_error'),
                margin: const EdgeInsets.only(top: 12),
                message: _error!.message,
              ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('create_submit'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(64, 56),
              ),
              onPressed: _sending ? null : _submit,
              child: _sending
                  ? const SizedBox(
                      key: Key('create_sending'),
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Создать заявку'),
            ),
          ],
        ),
      );

  Widget _stepper({
    required String label,
    required String value,
    required Key minusKey,
    required Key plusKey,
    required VoidCallback? onMinus,
    required VoidCallback? onPlus,
  }) =>
      Row(
        children: [
          Expanded(
            child: Text(label,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          IconButton.filledTonal(
            key: minusKey,
            onPressed: onMinus,
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: 92,
            child: Center(
              child: Text(value.trim(),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ),
          IconButton.filledTonal(
            key: plusKey,
            onPressed: onPlus,
            icon: const Icon(Icons.add),
          ),
        ],
      );
}
