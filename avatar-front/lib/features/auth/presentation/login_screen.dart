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
import '../../../core/theme/app_theme.dart';
import '../../../data/orders_repository.dart';
import '../../order_flow/domain/enums.dart';

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
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  AppFailure? _error;
  UserRole _role = UserRole.client;

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
  bool get _phoneValid =>
      RegExp(r'^\+7\d{10}$').hasMatch(_phoneNormalized);

  Future<void> _sendCode() async {
    if (!_phoneValid) {
      setState(() => _error = Failures.validation(
          'phone', 'Телефон: +7 и ровно 10 цифр (например, +79131234567).'));
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
      setState(() => _error =
          Failures.validation('code', 'Код — 4–6 цифр из СМС.'));
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
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 48),
                Container(
                  width: 88,
                  height: 88,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(Icons.local_shipping,
                      size: 44, color: AppColors.brandYellow),
                ),
                const SizedBox(height: 16),
                const Text(
                  'АВАТАР',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                ),
                Text(
                  'Используем силу с умом',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 32),
                if (!_codeSent) ...[
                  TextField(
                    key: const Key('login_phone'),
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[+\d]')),
                      LengthLimitingTextInputFormatter(16),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Телефон',
                      hintText: '+7 9XX XXX-XX-XX',
                      prefixIcon: Icon(Icons.phone),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const Key('login_send_code'),
                    onPressed: _busy ? null : _sendCode,
                    child: Text(_busy ? 'Отправляем…' : 'Получить код'),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final r in const [UserRole.client, UserRole.porter])
                        ChoiceChip(
                          key: Key('login_role_${r.name}'),
                          label: Text(r == UserRole.client
                              ? 'Я заказчик'
                              : 'Я грузчик'),
                          selected: _role == r,
                          onSelected: (_) => setState(() => _role = r),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Роль нужна только при первой регистрации.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ] else ...[
                  TextField(
                    key: const Key('login_code'),
                    controller: _code,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Код из СМС',
                      prefixIcon: Icon(Icons.sms_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
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
                  Container(
                    key: const Key('login_error'),
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: AppColors.error),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_error!.message)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
}
