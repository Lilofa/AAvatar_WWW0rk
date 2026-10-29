/// ТЕСТЫ ФАСАДА МОНИТОРИНГА: без sink — no-op, с sink — события нужной формы.
library;

import 'package:avatar_app/core/error/app_failure.dart';
import 'package:avatar_app/core/monitoring/app_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('без sink: полный no-op, ничего не бросает', () {
    AppMonitor.sink = null;
    expect(AppMonitor.isEnabled, isFalse);
    AppMonitor.failure(Failures.server('mock'), where: 'test');
    AppMonitor.failure(Failures.validation('f', 'p'), where: 'test');
    AppMonitor.crash(StateError('x'), StackTrace.current);
  });

  test('с sink: failure и crash приходят событиями с кодом и where', () {
    final events = <MonitorEvent>[];
    AppMonitor.sink = events.add;
    addTearDown(() => AppMonitor.sink = null);
    expect(AppMonitor.isEnabled, isTrue);

    AppMonitor.failure(Failures.server('бэк упал'), where: 'data');
    AppMonitor.failure(Failures.validation('phone', 'формат'), where: 'ui');
    AppMonitor.crash(StateError('boom'), StackTrace.current);

    expect(events, hasLength(3));
    expect(events[0].kind, 'failure');
    expect(events[0].code, 'server');
    expect(events[0].where, 'data');
    expect(events[1].code, 'validation');
    expect(events[2].kind, 'crash');
    expect(events[2].stack, isNotNull);
  });
}
