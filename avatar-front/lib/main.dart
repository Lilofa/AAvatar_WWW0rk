/// ТОЧКА ВХОДА «АВАТАР».
///
/// Live-данные включаются сборкой:
///   flutter run --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=<publishable-key>
/// Без define — mock-режим (неделя 1), но С ЭКРАНОМ ВХОДА: мок-логин
/// пропускает любой код, кроме 0000.
///
/// Структура (скелет Коли → Артём после 20.09):
///   AuthGate (сессия/мок-вход) → HomeShell (табы по ролям) → экраны зон.
/// Роутинг: home + onGenerateRoute для /order/<id> (активный заказ).
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/home_shell.dart';
import 'core/security/secure_session_storage.dart';
import 'core/theme/app_theme.dart';
import 'features/splash/presentation/splash_screen.dart';
import 'data/mock_orders_repository.dart';
import 'data/orders_repository.dart';
import 'data/supabase/supabase_orders_repository.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/order_active/presentation/order_active_screen.dart';

const String _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const String _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// Точка входа БЕЗ мониторинга (тесты, mock-стенд, dev).
/// Прод с Sentry собирается через main_sentry.dart:
///   flutter build apk -t lib/main_sentry.dart --dart-define=SENTRY_DSN=...
Future<void> main() async => runApp(await buildApp());

/// Сборка приложения с выбором репозитория (mock vs Supabase).
///
/// 🔒 В release-сборке mock ЗАПРЕЩЁН: у него вход «любой код», и забытые
/// --dart-define превратили бы боевое приложение в демо без авторизации.
/// Без SUPABASE_URL/SUPABASE_ANON_KEY релиз показывает экран ошибки конфигурации.
Future<Widget> buildApp() async {
  final configured = _supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty;
  const isRelease = bool.fromEnvironment('dart.vm.product');
  if (!configured && isRelease) {
    return const _MisconfiguredApp();
  }
  OrdersRepository repository = MockOrdersRepository();
  if (configured) {
    WidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(
      url: _supabaseUrl,
      publishableKey: _supabaseAnonKey,
      authOptions: FlutterAuthClientOptions(
        localStorage: SecureSessionStorage(),
      ),
    );
    repository = SupabaseOrdersRepository(Supabase.instance.client);
  }
  return AvatarApp(repository: repository);
}

class _MisconfiguredApp extends StatelessWidget {
  const _MisconfiguredApp();

  @override
  Widget build(BuildContext context) => const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Сборка не настроена: нет адреса сервера.\n'
                'Установите актуальную версию приложения.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
}

class AvatarApp extends StatelessWidget {
  const AvatarApp({super.key, required this.repository});

  final OrdersRepository repository;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Аватар',
        // Русская локаль: 24-часовой формат и русские date/time-пикеры
        // (баг-репорт 25.09: «Select time / AM / PM» у начальника).
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.light(),
        home: const bool.fromEnvironment('dart.vm.product')
            ? SplashGate(child: AuthGate(repository: repository))
            : AuthGate(repository: repository),
        onGenerateRoute: (settings) {
          final uri = settings.name ?? '';
          if (uri.startsWith('/order/')) {
            final id = uri.substring('/order/'.length);
            return MaterialPageRoute(
              builder: (_) => OrderActiveScreen(
                repository: repository,
                orderId: id,
              ),
            );
          }
          return null;
        },
      );
}

/// Ворота авторизации: mock — локальный флаг после логина;
/// live — сессия Supabase (verify-sms создаёт её через verifyOtp).
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.repository});

  final OrdersRepository repository;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _mockAuthed = false;

  bool get _isMock => widget.repository is MockOrdersRepository;

  @override
  Widget build(BuildContext context) {
    if (_isMock) {
      return _mockAuthed
          ? HomeShell(repository: widget.repository)
          : LoginScreen(
              key: const Key('auth_login'),
              repository: widget.repository,
              onAuthenticated: (_) => setState(() => _mockAuthed = true),
            );
    }
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      initialData: AuthState(
        AuthChangeEvent.initialSession,
        Supabase.instance.client.auth.currentSession,
      ),
      builder: (context, snap) {
        if (snap.data?.session == null) {
          return LoginScreen(
            key: const Key('auth_login'),
            repository: widget.repository,
            onAuthenticated: (_) {},
          );
        }
        return HomeShell(repository: widget.repository);
      },
    );
  }
}
