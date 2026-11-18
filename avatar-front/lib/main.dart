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
import 'core/ui/sign_out.dart';
import 'features/order_flow/domain/enums.dart';
import 'features/splash/presentation/splash_screen.dart';
import 'data/mock_orders_repository.dart';
import 'data/orders_repository.dart';
import 'data/supabase/supabase_orders_repository.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/order_active/presentation/order_active_screen.dart';

const String _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const String _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// Демо-сборка для бета-тестов: весь сервер заменён mock-данными, вход —
/// любым кодом, кроме 0000. В базу ничего не уходит. Включается ЯВНО:
///   flutter build apk --dart-define=DEMO_MODE=true
/// На экране всегда висит лента «ДЕМО», чтобы её не спутали с боевой.
const bool _demoMode = bool.fromEnvironment('DEMO_MODE');

/// Точка входа БЕЗ мониторинга (тесты, mock-стенд, dev).
/// Прод с Sentry собирается через main_sentry.dart:
///   flutter build apk -t lib/main_sentry.dart --dart-define=SENTRY_DSN=...
Future<void> main() async => runApp(await buildApp());

/// Сборка приложения с выбором репозитория (mock vs Supabase).
///
/// 🔒 В release-сборке mock запрещён, если его не попросили явно
/// (DEMO_MODE=true): забытые --dart-define иначе превратили бы боевое
/// приложение в демо без авторизации. Без SUPABASE_URL/SUPABASE_ANON_KEY
/// и без DEMO_MODE релиз показывает экран ошибки конфигурации.
Future<Widget> buildApp() async {
  final configured = _supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty;
  const isRelease = bool.fromEnvironment('dart.vm.product');
  if (!configured && isRelease && !_demoMode) {
    return const _MisconfiguredApp();
  }
  OrdersRepository repository = MockOrdersRepository();
  if (configured && !_demoMode) {
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

class AvatarApp extends StatefulWidget {
  const AvatarApp({super.key, required this.repository, this.demoMode = _demoMode});

  final OrdersRepository repository;

  /// Демо-полоса с переключателем ролей. По умолчанию — из DEMO_MODE;
  /// параметр нужен виджет-тестам.
  final bool demoMode;

  @override
  State<AvatarApp> createState() => _AvatarAppState();
}

class _AvatarAppState extends State<AvatarApp> {
  final _navigator = GlobalKey<NavigatorState>();

  OrdersRepository get repository => widget.repository;

  @override
  Widget build(BuildContext context) => MaterialApp(
        navigatorKey: _navigator,
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
        // Демо-сборка помечена всегда, на любом экране: тонкая полоса НАД
        // приложением. Не угловая лента — та закрывала кнопку «Выйти».
        builder: widget.demoMode
            ? (context, child) => Column(
                  children: [
                    _DemoStrip(navigator: _navigator),
                    Expanded(
                      child: MediaQuery.removePadding(
                        context: context,
                        removeTop: true,
                        child: child!,
                      ),
                    ),
                  ],
                )
            : null,
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

  Future<void> _signOut() async {
    await widget.repository.signOut();
    // Supabase-ветку перестроит onAuthStateChange (signedOut), mock — флаг.
    if (_isMock && mounted) setState(() => _mockAuthed = false);
  }

  Widget _shell() => SignOutProvider(
        onSignOut: _signOut,
        child: HomeShell(
          // новый ключ на каждый вход: вкладки и кэш экрана не переживают выход
          key: ValueKey(_sessionEpoch),
          repository: widget.repository,
        ),
      );

  int _sessionEpoch = 0;

  @override
  Widget build(BuildContext context) {
    if (_isMock) {
      return _mockAuthed
          ? _shell()
          : LoginScreen(
              key: const Key('auth_login'),
              repository: widget.repository,
              onAuthenticated: (_) => setState(() {
                _sessionEpoch++;
                _mockAuthed = true;
              }),
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
          _sessionEpoch++;
          return LoginScreen(
            key: const Key('auth_login'),
            repository: widget.repository,
            onAuthenticated: (_) {},
          );
        }
        return _shell();
      },
    );
  }
}

/// Красная полоса демо-сборки над приложением. Нажатие — выбор роли
/// демо-пользователя: вкладки перестраиваются сразу, данные те же.
class _DemoStrip extends StatelessWidget {
  const _DemoStrip({required this.navigator});

  final GlobalKey<NavigatorState> navigator;

  static const _presets = <(String, Set<UserRole>)>[
    ('Все роли', MockControls.allDemoRoles),
    ('Заказчик', {UserRole.client}),
    ('Грузчик', {UserRole.porter}),
    ('Диспетчер', {UserRole.dispatcher}),
    ('Админ', {UserRole.admin}),
  ];

  static String _label(Set<UserRole> roles) {
    for (final (name, set) in _presets) {
      if (set.length == roles.length && set.containsAll(roles)) return name;
    }
    return roles.map((r) => r.name).join(', ');
  }

  void _pick() {
    final ctx = navigator.currentContext;
    if (ctx == null) return;
    showModalBottomSheet<void>(
      context: ctx,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Демо: войти как…',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            for (final (name, roles) in _presets)
              ListTile(
                key: Key('demo_role_$name'),
                title: Text(name),
                subtitle: Text(switch (name) {
                  'Все роли' => 'Лента, мои заказы, рефералы, пульт',
                  'Заказчик' => 'Создаёт заявки и следит за ними',
                  'Грузчик' => 'Лента заказов, отклики, этапы, рефералы',
                  'Диспетчер' => 'Пульт: отклики, бригада, замена',
                  _ => 'Пульт диспетчера с правами админа',
                }),
                trailing: _label(MockControls.demoRoles) == name
                    ? const Icon(Icons.check, color: AppColors.brandBlue)
                    : null,
                onTap: () {
                  MockControls.setDemoRoles(roles);
                  Navigator.pop(sheet);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Material(
        key: const Key('demo_strip'),
        color: AppColors.error,
        child: SafeArea(
          bottom: false,
          child: InkWell(
            onTap: _pick,
            child: SizedBox(
              height: 26,
              width: double.infinity,
              child: Center(
                child: StreamBuilder<Set<UserRole>>(
                  stream: MockControls.demoRolesChanges,
                  initialData: MockControls.demoRoles,
                  builder: (context, snap) => Text(
                    'ДЕМО · роль: ${_label(snap.data ?? MockControls.demoRoles)} ▾',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
