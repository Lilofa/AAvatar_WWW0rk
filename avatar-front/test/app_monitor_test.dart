import 'package:flutter_test/flutter_test.dart';

import 'package:avatar_app/core/monitoring/app_monitor.dart';

class _FakeSink implements AppMonitorSink {
  final List<MonitorEvent> events = <MonitorEvent>[];

  @override
  void event(MonitorEvent event) => events.add(event);
}

class _ExplodingSink implements AppMonitorSink {
  @override
  void event(MonitorEvent event) => throw StateError('sink сломался');
}

void main() {
  setUp(() => AppMonitor.reset());
  tearDown(() => AppMonitor.reset());

  test('failure без sink не падает и остаётся в recent', () {
    AppMonitor.failure('test_code', 'Что-то сломалось');

    expect(AppMonitor.recent, isNotEmpty);
    final last = AppMonitor.recent.last;
    expect(last.code, 'test_code');
    expect(last.level, MonitorLevel.error);
  });

  test('событие форвардится в поставленный sink', () {
    final sink = _FakeSink();
    AppMonitor.setSink(sink);

    AppMonitor.warning('warn_code', 'Осторожно', context: {'order_id': 'o-1'});

    expect(sink.events, hasLength(1));
    expect(sink.events.first.level, MonitorLevel.warning);
    expect(sink.events.first.context?['order_id'], 'o-1');
  });

  test('setSink(null) отключает форвардинг', () {
    final sink = _FakeSink();
    AppMonitor.setSink(sink);

    AppMonitor.setSink(null);
    AppMonitor.info('info_code', 'Инфо');

    expect(sink.events, isEmpty);
    expect(AppMonitor.recent.last.code, 'info_code');
  });

  test('recent — кольцо на 20 событий', () {
    for (var i = 0; i < 25; i++) {
      AppMonitor.info('code_$i', 'событие $i');
    }

    expect(AppMonitor.recent.length, 20);
    expect(AppMonitor.recent.first.code, 'code_5');
    expect(AppMonitor.recent.last.code, 'code_24');
  });

  test('упавший sink не роняет приложение', () {
    AppMonitor.setSink(_ExplodingSink());

    expect(() => AppMonitor.failure('boom', 'проверка'), returnsNormally);
    // событие записано в recent ДО вызова sink — диагностика не теряется
    expect(AppMonitor.recent.last.code, 'boom');
  });
}
