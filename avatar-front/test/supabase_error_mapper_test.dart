/// ТЕСТЫ МАППЕРА ОШИБОК SUPABASE → AppFailure.
///
/// Зона: Артём. Контракт с Матвеей (12.09): коды ORDER_NOT_FOUND,
/// STAGE_INVALID_ORDER, STAGE_NOT_YOUR_TURN, PERMISSION_DENIED,
/// VALIDATION_FAILED, RATE_LIMITED. Сырые PostgrestException наружу не выходят.
library;

import 'dart:io';

import 'package:avatar_app/core/error/app_failure.dart';
import 'package:avatar_app/data/supabase/supabase_error_mapper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const mapper = SupabaseErrorMapper();

  PostgrestException pg(String message) =>
      PostgrestException(message: message, code: 'P0001');

  test('ORDER_NOT_FOUND → orderNotFound', () {
    final f = mapper.map(pg('ORDER_NOT_FOUND: order does not exist'));
    expect(f.code, FailureCode.orderNotFound);
    expect(f.message, isNotEmpty);
  });

  test('STAGE_INVALID_ORDER: cancelled → orderClosed', () {
    final f = mapper.map(pg('STAGE_INVALID_ORDER: order is cancelled'));
    expect(f.code, FailureCode.orderClosed);
    expect(f.isFatalForScreen, isTrue, reason: 'экран активного заказа должен закрыться');
  });

  test('STAGE_INVALID_ORDER: woke → notMorningOrder', () {
    final f = mapper.map(pg('STAGE_INVALID_ORDER: woke only for morning orders (4:00-12:00)'));
    expect(f.code, FailureCode.notMorningOrder);
    expect(f.message, contains('утренних'));
  });

  test('STAGE_NOT_YOUR_TURN → wrongStageOrder', () {
    final f = mapper.map(pg('STAGE_NOT_YOUR_TURN: cannot mark arrived before departed'));
    expect(f.code, FailureCode.wrongStageOrder);
  });

  test('PERMISSION_DENIED: lead → leadOnly', () {
    final f = mapper.map(pg('PERMISSION_DENIED: only lead can mark started'));
    expect(f.code, FailureCode.leadOnly);
    expect(f.message, contains('старший'));
  });

  test('PERMISSION_DENIED: dispatcher → forbidden с текстом про диспетчера', () {
    final f = mapper.map(pg('PERMISSION_DENIED: only dispatcher or admin'));
    expect(f.code, FailureCode.forbidden);
    expect(f.message, contains('диспетчеру'));
  });

  test('VALIDATION_FAILED → validation с человекочитаемым хвостом', () {
    final f = mapper.map(pg('VALIDATION_FAILED: people_count must be >= 1'));
    expect(f.code, FailureCode.validation);
    expect(f.message, contains('people_count'));
  });

  test('RATE_LIMITED → rateLimited, retryable', () {
    final f = mapper.map(pg('RATE_LIMITED: too many sms per hour'));
    expect(f.code, FailureCode.rateLimited);
    expect(f.retryable, isTrue);
    expect(f.showRetry, isTrue);
  });

  test('RLS 42501 → forbidden', () {
    final f = mapper.map(const PostgrestException(message: 'row-level security policy violated', code: '42501'));
    expect(f.code, FailureCode.forbidden);
  });

  test('unique 23505 → stageAlreadySet (идемпотентность)', () {
    final f = mapper.map(const PostgrestException(message: 'duplicate key value', code: '23505'));
    expect(f.code, FailureCode.stageAlreadySet);
  });

  test('SocketException → offline', () {
    final f = mapper.map(const SocketException('no network'));
    expect(f.code, FailureCode.offline);
    expect(f.showRetry, isTrue);
  });

  test('AuthException → unauthorized', () {
    final f = mapper.map(const AuthException('invalid login factor'));
    expect(f.code, FailureCode.unauthorized);
  });

  test('неизвестная ошибка → server, текст не пустой и не сырьё', () {
    final f = mapper.map(pg('SOMETHING_WEIRD: boom'));
    expect(f.code, FailureCode.server);
    expect(f.message, isNotEmpty);
    expect(f.message, isNot(contains('SOMETHING_WEIRD')));
  });
}
