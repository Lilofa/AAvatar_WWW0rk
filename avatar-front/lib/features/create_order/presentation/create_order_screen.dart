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
import '../../../data/orders_repository.dart';
import '../../order_flow/domain/enums.dart';
import '../../order_flow/domain/models.dart';

class CreateOrderScreen extends StatefulWidget {
  const CreateOrderScreen({super.key, required this.repository});

  final OrdersRepository repository;

  static const Color brandBlue = Color(0xFF1D5BA6);

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
        appBar: AppBar(
          title: const Text('Новая заявка'),
          backgroundColor: CreateOrderScreen.brandBlue,
          foregroundColor: Colors.white,
        ),
        body: _done ? _doneView() : _form(),
      );

  Widget _doneView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            key: const Key('create_done'),
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle,
                  size: 64, color: CreateOrderScreen.brandBlue),
              const SizedBox(height: 16),
              const Text(
                'Заявка создана!\nДиспетчер одобрит — и она появится у грузчиков.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('create_done_back'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('К моим заказам'),
              ),
            ],
          ),
        ),
      );

  Widget _form() => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('create_address'),
              controller: _address,
              onChanged: _onAddressChanged,
              decoration: const InputDecoration(
                labelText: 'Адрес',
                hintText: 'Начните вводить: улица, дом',
                border: OutlineInputBorder(),
              ),
            ),
            if (_suggestions.isNotEmpty)
              Container(
                key: const Key('create_suggest_box'),
                constraints: const BoxConstraints(maxHeight: 180),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey.shade300),
                ),
                // Material обязателен: ListTile рисует чернила на ближайшем
                // Material-предке, иначе debug-ассерт в тестах.
                child: Material(
                  color: Colors.white,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _suggestions.length,
                    itemBuilder: (context, i) => ListTile(
                      key: Key('create_suggest_$i'),
                      dense: true,
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
                  child: FilledButton.tonalIcon(
                    key: const Key('create_date_btn'),
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _start,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 60)),
                      );
                      if (d != null) {
                        setState(() => _start = DateTime(
                            d.year, d.month, d.day, _start.hour, _start.minute));
                      }
                    },
                    icon: const Icon(Icons.calendar_month),
                    label: Text(
                        '${_start.day.toString().padLeft(2, '0')}.${_start.month.toString().padLeft(2, '0')}.${_start.year}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    key: const Key('create_time_btn'),
                    onPressed: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(_start),
                      );
                      if (t != null) {
                        setState(() =>
                            _start = DateTime(_start.year, _start.month,
                                _start.day, t.hour, t.minute));
                      }
                    },
                    icon: const Icon(Icons.schedule),
                    label: Text(
                        '${_start.hour.toString().padLeft(2, '0')}:${_start.minute.toString().padLeft(2, '0')}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _stepper(
              label: 'Грузчиков',
              value: '$_people',
              minusKey: const Key('create_people_minus'),
              plusKey: const Key('create_people_plus'),
              onMinus: _people > 1 ? () => setState(() => _people--) : null,
              onPlus: _people < 20 ? () => setState(() => _people++) : null,
            ),
            const SizedBox(height: 8),
            _stepper(
              label: 'Длительность',
              value: '${_durationMin ~/ 60} ч ${_durationMin % 60 > 0 ? '${_durationMin % 60} мин' : ''}',
              minusKey: const Key('create_duration_minus'),
              plusKey: const Key('create_duration_plus'),
              onMinus: _durationMin > 30
                  ? () => setState(() => _durationMin -= 30)
                  : null,
              onPlus: _durationMin < 720
                  ? () => setState(() => _durationMin += 30)
                  : null,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('create_title'),
              controller: _title,
              decoration: const InputDecoration(
                labelText: 'Наименование (что повезём/переносим)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('create_description'),
              controller: _description,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Что делать (подробности)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
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
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
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
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('create_entrance'),
                    controller: _entrance,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Подъезд (необязательно)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: const Key('create_phone'),
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Телефон на месте',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              key: const Key('create_quote_btn'),
              onPressed: _quoting ? null : _quoteIt,
              icon: _quoting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.calculate),
              label: Text(_quoting ? 'Считаем…' : 'Рассчитать тариф'),
            ),
            if (_quote != null)
              Container(
                key: const Key('create_quote_panel'),
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5E326).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFF5E326)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final l in _quote!.breakdown)
                      Text('${l.label}: ${l.amount.toInt()} ₽'),
                    const Divider(),
                    Text(
                      'Итого: ${_quote!.price.toInt()} ₽ · ~${_quote!.hours} ч',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            if (_error != null)
              Container(
                key: const Key('create_error'),
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!.message)),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('create_submit'),
              style: FilledButton.styleFrom(
                backgroundColor: CreateOrderScreen.brandBlue,
                padding: const EdgeInsets.symmetric(vertical: 16),
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
          SizedBox(width: 110, child: Text(label)),
          IconButton.filledTonal(
            key: minusKey,
            onPressed: onMinus,
            icon: const Icon(Icons.remove),
          ),
          SizedBox(width: 90, child: Center(child: Text(value))),
          IconButton.filledTonal(
            key: plusKey,
            onPressed: onPlus,
            icon: const Icon(Icons.add),
          ),
        ],
      );
}
