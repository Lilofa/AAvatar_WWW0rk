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
import 'core/theme/app_theme.dart';
import 'data/mock_orders_repository.dart';
import 'data/orders_repository.dart';
import 'data/supabase/supabase_orders_repository.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/order_active/presentation/order_active_screen.dart';

const String _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const String _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  OrdersRepository repository = MockOrdersRepository();
  if (_supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty) {
    WidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(url: _supabaseUrl, publishableKey: _supabaseAnonKey);
    repository = SupabaseOrdersRepository(Supabase.instance.client);
  }
  runApp(AvatarApp(repository: repository));
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
        home: AuthGate(repository: repository),
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
