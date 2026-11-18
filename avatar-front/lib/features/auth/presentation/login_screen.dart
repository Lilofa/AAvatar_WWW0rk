/// ЭКРАН ВХОДА ПО SMS (зона Коли → Артём; MVP «регистрация по телефону»).
///
/// Шаги: телефон → код. Роль выбирается только при первой регистрации
/// (edge verify-sms создаёт пользователя с ролью; повторный вход роль игнорирует).
/// Состояния: form / sending / error. После успеха сессию держит Supabase,
/// в mock-режиме вызывается [onAuthenticated].
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/legal/consent_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../data/orders_repository.dart';
import '../../order_flow/domain/enums.dart';

/// Валидность российского номера: +7 и ровно 10 цифр после.
/// Вынесено из виджета для регресс-тестов (баг-репорт 25.09).
bool isRuPhoneValid(String text) {
  final d = text.replaceAll(RegExp(r'\D'), '');
  final core = (d.startsWith('7') || d.startsWith('8')) ? d.substring(1) : d;
  return core.length == 10;
}

/// Маска российского номера: +7(983)-355-95-99.
/// Скобки/тире появляются сами по мере ввода цифр; лишние цифры не лезут.
String formatRuPhone(String raw) {
  var d = raw.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('7') || d.startsWith('8')) d = d.substring(1);
  if (d.length > 10) d = d.substring(0, 10);
  final b = StringBuffer('+7');
  if (d.isNotEmpty) b.write('(${d.substring(0, d.length > 3 ? 3 : d.length)}');
  if (d.length >= 3) b.write(')');
  if (d.length >= 4) b.write('-${d.substring(3, d.length > 6 ? 6 : d.length)}');
  if (d.length >= 7) b.write('-${d.substring(6, d.length > 8 ? 8 : d.length)}');
  if (d.length >= 9) b.write('-${d.substring(8, d.length)}');
  return b.toString();
}

class _RuPhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = formatRuPhone(newValue.text);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.repository,
    required this.onAuthenticated,
  });

  final OrdersRepository repository;
  final ValueChanged<AuthResult> onAuthenticated;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController(text: '+7');
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  AppFailure? _error;
  UserRole _role = UserRole.client;
  bool _consent = false;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  String get _phoneNormalized {
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('7') || digits.startsWith('8')) {
      return '+7${digits.substring(1, 11)}';
    }
    return '+7$digits';
  }

  /// +7 и ровно 10 цифр после; всё остальное — ошибка (баг-репорт:
  /// «ввожу больше — программа ничего не говорит»).
  bool get _phoneValid => isRuPhoneValid(_phone.text);

  Future<void> _sendCode() async {
    // 152-ФЗ: согласие — ДО отправки номера на сервер.
    if (!_consent) {
      setState(() => _error = Failures.validation('consent',
          'Чтобы продолжить, дайте согласие на обработку персональных данных.'));
      return;
    }
    if (!_phoneValid) {
      setState(() => _error = Failures.validation('phone',
          'Введите номер целиком: +7(983)-355-95-99 — 10 цифр после +7.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.sendSmsCode(phone: _phoneNormalized);
      if (mounted) setState(() => _codeSent = true);
    } on AppFailure catch (f) {
      if (mounted) setState(() => _error = f);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_code.text.trim().length < 4) {
      setState(
          () => _error = Failures.validation('code', 'Код — 4–6 цифр из СМС.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await widget.repository.verifySmsCode(
        phone: _phoneNormalized,
        code: _code.text.trim(),
        role: _role,
        consentVersion: consentVersion,
      );
      if (mounted) widget.onAuthenticated(res);
    } on AppFailure catch (f) {
      if (mounted) setState(() => _error = f);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.brandBlueDeep,
        body: BrandSurface(
          child: SafeArea(
            bottom: false,
            // SliverFillRemaining: шапка центрируется в свободном месте,
            // форма прижата к низу; на низком экране всё просто скроллится.
            // Ширину ограничиваем СНАРУЖИ скролла: SliverFillRemaining меряет
            // высоту по ширине вьюпорта, сужение внутри даёт overflow.
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: CustomScrollView(
                  slivers: [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Column(
                        children: [
                          Expanded(child: Center(child: _hero())),
                          _sheet(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  Widget _hero() => Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandMark(size: 76, onDark: true),
            const SizedBox(height: 16),
            const Text(
              'АВАТАР',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w900,
                letterSpacing: 5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Используем силу с умом',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.82), fontSize: 15),
            ),
          ],
        ),
      );

  Widget _sheet() => Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
            24, 28, 24, 24 + MediaQuery.paddingOf(context).bottom),
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _codeSent ? 'Введите код' : 'Вход по номеру телефона',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _codeSent
                  ? 'Отправили СМС на ${_phone.text}'
                  : 'Пришлём СМС с кодом — пароль не нужен.',
              style: const TextStyle(color: AppColors.muted, height: 1.35),
            ),
            const SizedBox(height: 20),
            if (!_codeSent) ...[
              TextField(
                key: const Key('login_phone'),
                controller: _phone,
                keyboardType: TextInputType.phone,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[+\d()\- ]')),
                  _RuPhoneFormatter(),
                ],
                decoration: const InputDecoration(
                  labelText: 'Телефон',
                  hintText: '+7(983)-355-95-99',
                  helperText: 'Формат: +7(983)-355-95-99',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 12),
              _consentRow(),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('login_send_code'),
                onPressed: _busy ? null : _sendCode,
                child: Text(_busy ? 'Отправляем…' : 'Получить код'),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  for (final r in const [UserRole.client, UserRole.porter]) ...[
                    if (r == UserRole.porter) const SizedBox(width: 10),
                    Expanded(child: _roleCard(r)),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Роль нужна только при первой регистрации.',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ] else ...[
              TextField(
                key: const Key('login_code'),
                controller: _code,
                autofocus: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 10,
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Код из СМС',
                  counterText: '',
                  floatingLabelAlignment: FloatingLabelAlignment.center,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('login_submit'),
                onPressed: _busy ? null : _verify,
                child: Text(_busy ? 'Проверяем…' : 'Войти'),
              ),
              const SizedBox(height: 8),
              TextButton(
                key: const Key('login_change_phone'),
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _codeSent = false;
                          _error = null;
                        }),
                child: const Text('Изменить номер'),
              ),
            ],
            if (_error != null)
              AppBanner(
                key: const Key('login_error'),
                margin: const EdgeInsets.only(top: 16),
                message: _error!.message,
              ),
          ],
        ),
      );

  Widget _consentRow() => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: Checkbox(
              key: const Key('login_consent'),
              value: _consent,
              onChanged: (v) => setState(() {
                _consent = v ?? false;
                if (_consent && _error?.code == FailureCode.validation) {
                  _error = null;
                }
              }),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                children: [
                  const Text('Я даю ',
                      style: TextStyle(fontSize: 13, color: AppColors.inkSoft)),
                  GestureDetector(
                    key: const Key('login_consent_open'),
                    onTap: _showConsent,
                    child: const Text(
                      'согласие на обработку персональных данных',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.brandBlue,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  const Text(' и подтверждаю, что мне есть 18 лет',
                      style: TextStyle(fontSize: 13, color: AppColors.inkSoft)),
                ],
              ),
            ),
          ),
        ],
      );

  Future<void> _showConsent() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: ConstrainedBox(
            constraints:
                BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(consentTitle,
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  const Text(consentText,
                      style: TextStyle(fontSize: 14, height: 1.45)),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const Key('login_consent_accept'),
                    onPressed: () {
                      setState(() {
                        _consent = true;
                        _error = null;
                      });
                      Navigator.pop(ctx);
                    },
                    child: const Text('Согласен(на)'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _roleCard(UserRole r) {
    final selected = _role == r;
    final isClient = r == UserRole.client;
    return Material(
      color: selected ? AppColors.brandBlueSoft : AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        key: Key('login_role_${r.name}'),
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => setState(() => _role = r),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected ? AppColors.brandBlue : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isClient
                    ? Icons.inventory_2_outlined
                    : Icons.fitness_center_outlined,
                size: 22,
                color: selected ? AppColors.brandBlue : AppColors.muted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isClient ? 'Я заказчик' : 'Я грузчик',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: selected ? AppColors.brandBlueDeep : AppColors.ink,
                  ),
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle,
                    size: 18, color: AppColors.brandBlue),
            ],
          ),
        ),
      ),
    );
  }
}
