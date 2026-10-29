import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:avatar_app/core/monitoring/app_monitor.dart';
import 'package:avatar_app/core/monitoring/sentry_sink.dart';

void main() {
  setUp(() => AppMonitor.setSink(null));
  tearDown(() => AppMonitor.setSink(null));

  test('SentrySink отправляет событие с уровнем и кодом', () async {
    final captures = <(SentryLevel, MonitorEvent)>[];
    AppMonitor.setSink(SentrySink(
      capture: (level, event) async {
        captures.add((level, event));
      },
    ));

    AppMonitor.failure('chat_photo_upload', 'Не удалось загрузить фото',
        context: {'order_id': 'o-42'});
    await Future<void>.delayed(Duration.zero);

    expect(captures, hasLength(1));
    expect(captures.first.$1, SentryLevel.error);
    expect(captures.first.$2.code, 'chat_photo_upload');
    expect(captures.first.$2.context?['order_id'], 'o-42');
  });

  test('уровни маппятся в SentryLevel один в один', () async {
    final levels = <SentryLevel>[];
    AppMonitor.setSink(SentrySink(
      capture: (level, event) async {
        levels.add(level);
      },
    ));

    AppMonitor.warning('w', 'предупреждение');
    AppMonitor.info('i', 'инфо');
    AppMonitor.failure('e', 'ошибка');
    await Future<void>.delayed(Duration.zero);

    expect(levels, [SentryLevel.warning, SentryLevel.info, SentryLevel.error]);
  });

  test('ошибка доставки не роняет поток', () async {
    AppMonitor.setSink(SentrySink(
      capture: (level, event) async => throw StateError('сеть недоступна'),
    ));

    expect(() => AppMonitor.failure('x', 'y'), returnsNormally);
    await Future<void>.delayed(Duration.zero);
    // не упало — тест зелёный сам по себе
  });
}
