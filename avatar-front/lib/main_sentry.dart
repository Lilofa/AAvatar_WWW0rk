/// ТОЧКА ВХОДА ПРОД-СБОРОК С МОНИТОРИНГОМ (Sentry).
///
///   flutter build apk --release -t lib/main_sentry.dart \
///     --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... \
///     --dart-define=SENTRY_DSN=https://...@sentry.io/...
///
/// Без SENTRY_DSN ведёт себя как обычный main.dart.
library;

import 'package:flutter/material.dart';

import 'core/monitoring/sentry_sink.dart';
import 'main.dart' as base;

const String _sentryDsn = String.fromEnvironment('SENTRY_DSN');

Future<void> main() async {
  final app = await base.buildApp();
  if (_sentryDsn.isEmpty) {
    runApp(app);
    return;
  }
  await runWithSentry(dsn: _sentryDsn, app: app);
}
