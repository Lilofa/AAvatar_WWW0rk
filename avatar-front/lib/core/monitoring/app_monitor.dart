/// МОНИТОРИНГ ПРОДА, фасад без зависимостей (зона Артёма, прод-QA).
///
/// Плагин Sentry живёт ТОЛЬКО в sentry_sink.dart и подключается отдельной
/// точкой входа main_sentry.dart (прод-сборки: flutter build -t
/// lib/main_sentry.dart --dart-define=SENTRY_DSN=...). Обычный main.dart,
/// тесты и mock-стенд не тянут sentry в граф компиляции вообще.
///
/// Без установленного sink все вызовы — no-op.
library;

import '../error/app_failure.dart';

/// Событие мониторинга: ошибка слоя данных/UI или краш.
class MonitorEvent {
  const MonitorEvent({
    required this.kind,
    required this.code,
    required this.message,
    required this.where,
    this.error,
    this.stack,
  });

  /// 'failure' (AppFailure из репозитория/экрана) или 'crash'.
  final String kind;
  final String code;
  final String message;
  final String where;
  final Object? error;
  final StackTrace? stack;
}

abstract final class AppMonitor {
  static void Function(MonitorEvent)? sink;

  static bool get isEnabled => sink != null;

  static void failure(AppFailure f, {required String where}) => sink?.call(
        MonitorEvent(
          kind: 'failure',
          code: f.code.name,
          message: f.message,
          where: where,
          error: f,
        ),
      );

  static void crash(Object error, StackTrace stackTrace) => sink?.call(
        MonitorEvent(
          kind: 'crash',
          code: error.runtimeType.toString(),
          message: error.toString(),
          where: 'uncaught',
          error: error,
          stack: stackTrace,
        ),
      );
}
