/// Заявка на работу грузчиком (просьба Артёма 26.11.2026).
///
/// Все регистрируются заказчиками. В личном кабинете — карточка «Работа
/// грузчиком» с кнопкой «Подать заявку»; диспетчер/админ одобряет или
/// отклоняет заявку на своём пульте, после одобрения у человека появляются
/// вкладки грузчика. Сервер: миграция 20261126120000_worker_applications.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/geo/service_cities.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../data/orders_repository.dart';
import '../../order_flow/domain/models.dart';

// ─────────────────────────────────────────────────────────────
// Карточка в кабинете заказчика
// ─────────────────────────────────────────────────────────────

class WorkerApplicationCard extends StatefulWidget {
  const WorkerApplicationCard({
    super.key,
    required this.repository,
    this.defaultName,
    this.defaultCity,
  });

  final OrdersRepository repository;
  final String? defaultName;
  final String? defaultCity;

  @override
  State<WorkerApplicationCard> createState() => _WorkerApplicationCardState();
}

class _WorkerApplicationCardState extends State<WorkerApplicationCard> {
  WorkerApplication? _app;
  bool _loaded = false;
  AppFailure? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final app = await widget.repository.myWorkerApplication();
      if (!mounted) return;
      setState(() {
        _app = app;
        _loaded = true;
        _error = null;
      });
      // Одобрили, а вкладок грузчика ещё нет — перечитать профиль.
      if (app?.status == WorkerApplicationStatus.approved) {
        await widget.repository.refreshCurrentUser();
      }
    } on AppFailure catch (f) {
      if (mounted) {
        setState(() {
          _error = f;
          _loaded = true;
        });
      }
    }
  }

  Future<void> _apply() async {
    final sent = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => WorkerApplicationScreen(
        repository: widget.repository,
        defaultName: _app?.fullName ?? widget.defaultName,
        defaultCity: _app?.city ?? widget.defaultCity,
      ),
    ));
    if (sent == true) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          key: Key('worker_app_sent_snack'),
          content: Text('Заявка отправлена. Диспетчер рассмотрит её и позвонит вам.'),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = _app;
    final status = app?.status;
    return AppCard(
      key: const Key('cab_worker_card'),
      accent: AppColors.brandYellow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.badge_outlined, color: AppColors.brandBlue),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Работа грузчиком',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              if (status == WorkerApplicationStatus.pending)
                const AppPill(
                    key: Key('worker_app_pending'),
                    label: 'На рассмотрении',
                    color: AppColors.warning),
              if (status == WorkerApplicationStatus.rejected)
                const AppPill(
                    key: Key('worker_app_rejected'),
                    label: 'Отклонена',
                    color: AppColors.error),
              if (status == WorkerApplicationStatus.approved)
                const AppPill(
                    key: Key('worker_app_approved'),
                    label: 'Одобрена',
                    color: AppColors.success),
            ],
          ),
          const SizedBox(height: 8),
          if (!_loaded)
            const LinearProgressIndicator(minHeight: 2)
          else if (_error != null)
            Text(_error!.message, style: const TextStyle(color: AppColors.error))
          else
            Text(
              switch (status) {
                null => 'Берите заказы в своём городе, работайте в удобное '
                    'время. Заполните короткую анкету — диспетчер проверит её '
                    'и откроет вам ленту заказов.',
                WorkerApplicationStatus.pending =>
                  'Заявка от ${app!.createdAt == null ? 'вас' : AppFormat.ddmm(app.createdAt!)} '
                      'ждёт диспетчера. Обычно отвечаем в течение дня.',
                WorkerApplicationStatus.rejected =>
                  'Заявку отклонили${(app!.rejectReason ?? '').isEmpty ? '.' : ': ${app.rejectReason}'} '
                      'Можно подать её снова.',
                WorkerApplicationStatus.approved =>
                  'Заявку одобрили — вкладка «Лента» с заказами уже доступна.',
              },
              style: const TextStyle(color: AppColors.inkSoft),
            ),
          if (_loaded &&
              _error == null &&
              (status == null || status == WorkerApplicationStatus.rejected)) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('cab_worker_apply'),
              onPressed: _apply,
              icon: const Icon(Icons.send_outlined),
              label: Text(status == null ? 'Подать заявку' : 'Подать снова'),
            ),
          ],
          if (_error != null)
            TextButton(
              key: const Key('cab_worker_retry'),
              onPressed: _load,
              child: const Text('Повторить'),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Анкета
// ─────────────────────────────────────────────────────────────

class WorkerApplicationScreen extends StatefulWidget {
  const WorkerApplicationScreen({
    super.key,
    required this.repository,
    this.defaultName,
    this.defaultCity,
  });

  final OrdersRepository repository;
  final String? defaultName;
  final String? defaultCity;

  @override
  State<WorkerApplicationScreen> createState() => _WorkerApplicationScreenState();
}

class _WorkerApplicationScreenState extends State<WorkerApplicationScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.defaultName ?? '');
  final TextEditingController _experience = TextEditingController();
  late String? _city = serviceCityByName(widget.defaultCity)?.name;
  bool _adult = false;
  bool _busy = false;
  AppFailure? _error;

  @override
  void dispose() {
    _name.dispose();
    _experience.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    String? problem;
    if (name.length < 2) {
      problem = 'Укажите имя и фамилию.';
    } else if (_city == null) {
      problem = 'Выберите город.';
    } else if (!_adult) {
      problem = 'Работать грузчиком можно с 18 лет.';
    }
    if (problem != null) {
      setState(() => _error = Failures.validation('form', problem!));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.submitWorkerApplication(
        fullName: name,
        city: _city!,
        experience: _experience.text.trim().isEmpty ? null : _experience.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on AppFailure catch (f) {
      if (mounted) setState(() => _error = f);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Заявка грузчика')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              const Text(
                'Диспетчер проверит анкету и позвонит вам. После одобрения '
                'в приложении появится лента заказов.',
                style: TextStyle(color: AppColors.inkSoft),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('worker_app_name'),
                controller: _name,
                textCapitalization: TextCapitalization.words,
                inputFormatters: [LengthLimitingTextInputFormatter(120)],
                decoration: const InputDecoration(
                  labelText: 'Имя и фамилия',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Город', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final c in serviceCities)
                    ChoiceChip(
                      key: Key('worker_app_city_${c.name}'),
                      label: Text(c.name),
                      selected: _city == c.name,
                      onSelected: (_) => setState(() => _city = c.name),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('worker_app_experience'),
                controller: _experience,
                minLines: 3,
                maxLines: 6,
                inputFormatters: [LengthLimitingTextInputFormatter(1000)],
                decoration: const InputDecoration(
                  labelText: 'Опыт работы (необязательно)',
                  hintText: 'Где и сколько работали, есть ли опыт переездов',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                key: const Key('worker_app_adult'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _adult,
                onChanged: (v) => setState(() => _adult = v ?? false),
                title: const Text('Мне исполнилось 18 лет'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                AppBanner(
                  key: const Key('worker_app_error'),
                  message: _error!.message,
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('worker_app_submit'),
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const ButtonSpinner()
                    : const Text('Отправить заявку'),
              ),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────
// Пульт диспетчера: заявки на рассмотрении
// ─────────────────────────────────────────────────────────────

class WorkerApplicationsReview extends StatefulWidget {
  const WorkerApplicationsReview({super.key, required this.repository});

  final OrdersRepository repository;

  @override
  State<WorkerApplicationsReview> createState() => _WorkerApplicationsReviewState();
}

class _WorkerApplicationsReviewState extends State<WorkerApplicationsReview> {
  List<WorkerApplication>? _apps;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final apps = await widget.repository.pendingWorkerApplications();
      if (mounted) setState(() => _apps = apps);
    } on AppFailure {
      if (mounted) setState(() => _apps = const []);
    }
  }

  Future<void> _review(WorkerApplication a, bool approve) async {
    String? reason;
    if (!approve) {
      reason = await showDialog<String>(
        context: context,
        builder: (_) => const _RejectDialog(),
      );
      if (reason == null) return; // отмена
    }
    setState(() => _busy.add(a.id));
    try {
      await widget.repository.reviewWorkerApplication(
          id: a.id, approve: approve, reason: reason);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(approve
            ? '${a.fullName} теперь грузчик.'
            : 'Заявка ${a.fullName} отклонена.'),
      ));
      await _load();
    } on AppFailure catch (f) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(f.message)));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(a.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final apps = _apps;
    if (apps == null || apps.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const Key('disp_worker_apps'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Заявки в грузчики',
          trailing: AppPill(label: '${apps.length}', color: AppColors.warning),
        ),
        for (final a in apps)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              key: Key('disp_worker_app_${a.id}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.fullName,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    [a.city, if (a.phone != null) a.phone!].join(' · '),
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  if ((a.experience ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(a.experience!),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          key: Key('disp_worker_reject_${a.id}'),
                          onPressed: _busy.contains(a.id) ? null : () => _review(a, false),
                          child: const Text('Отклонить'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          key: Key('disp_worker_approve_${a.id}'),
                          onPressed: _busy.contains(a.id) ? null : () => _review(a, true),
                          child: const Text('Одобрить'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _RejectDialog extends StatefulWidget {
  const _RejectDialog();

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Отклонить заявку?'),
        content: TextField(
          key: const Key('disp_worker_reject_reason'),
          controller: _reason,
          maxLines: 3,
          inputFormatters: [LengthLimitingTextInputFormatter(500)],
          decoration: const InputDecoration(
            labelText: 'Причина (увидит человек)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            key: const Key('disp_worker_reject_confirm'),
            onPressed: () => Navigator.of(context).pop(_reason.text.trim()),
            child: const Text('Отклонить'),
          ),
        ],
      );
}
