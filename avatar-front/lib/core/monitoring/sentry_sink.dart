/// SENTRY-СINK мониторинга (только для прод-сборки через main_sentry.dart).
///
/// Пользовательские ошибки (validation/unauthorized) — breadcrumb,
/// серверные/неизвестные/краши — события с тегом layer и контекстом.
library;

import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'app_monitor.dart';

Future<void> runWithSentry({
  required String dsn,
  required Widget app,
}) async {
  await SentryFlutter.init(
    (options) {
      options.dsn = dsn;
      options.environment =
          const bool.fromEnvironment('dart.vm.product') ? 'production' : 'dev';
      options.release = 'avatar-app@1.0.0';
      // Телефоны/имена/адреса — персональные данные: в Sentry не отправляем.
      options.sendDefaultPii = false;
      options.attachScreenshot = false;
    },
    appRunner: () {
      AppMonitor.sink = (e) {
        if (e.kind == 'failure' &&
            (e.code == 'validation' || e.code == 'unauthorized')) {
          Sentry.addBreadcrumb(Breadcrumb(
            message: '${e.where}: ${e.code}',
            level: SentryLevel.info,
          ));
          return;
        }
        Sentry.captureException(
          e.error ?? e.message,
          stackTrace: e.stack,
          withScope: (scope) => scope
            ..setTag('layer', e.where)
            ..setContexts('failure', {'code': e.code, 'message': e.message}),
        );
      };
      runApp(SentryWidget(child: app));
    },
  );
}
