/// ТОЧКА ВХОДА.
///
/// Live-данные включаются сборкой:
///   flutter run --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=<publishable-key>
/// Без этих define приложение стартует на MockOrdersRepository (неделя 1).
/// Дизайн/тема/роутинг — зона Коли; здесь только выбор источника данных.
library;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/mock_orders_repository.dart';
import 'data/orders_repository.dart';
import 'data/supabase/supabase_orders_repository.dart';
import 'features/order_feed/presentation/order_feed_screen.dart';

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
        home: OrderFeedScreen(
          repository: repository,
          showMockSwitch: repository is MockOrdersRepository,
        ),
      );
}
