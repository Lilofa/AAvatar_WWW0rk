/// МАППЕР ОШИБОК SUPABASE → AppFailure (зона Артёма).
///
/// Матвей, 12.09: «AppFailure{code,message} — реализую на твоей стороне парсер PGRST.
/// Коды: ORDER_NOT_FOUND, STAGE_INVALID_ORDER, STAGE_NOT_YOUR_TURN,
/// PERMISSION_DENIED, VALIDATION_FAILED, RATE_LIMITED».
///
/// Здесь живёт ровно этот парсер: сырые PostgrestException/AuthException НЕ
/// выходят наружу — только AppFailure с готовым русским текстом (тексты ошибок
/// сочиняются в одном месте, а не в виджетах).
library;

import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error/app_failure.dart';

class SupabaseErrorMapper {
  const SupabaseErrorMapper();

  AppFailure map(Object error) {
    if (error is SocketException || error is HttpException) {
      return Failures.offline();
    }

    if (error is PostgrestException) {
      return _fromPostgrest(error);
    }

    if (error is AuthSessionMissingException) {
      return Failures.unauthorized();
    }

    if (error is AuthException) {
      return Failures.unauthorized();
    }

    if (error is StorageException) {
      return Failures.server(error.message);
    }

    return Failures.unknown(error);
  }

  AppFailure _fromPostgrest(PostgrestException e) {
    // RAISE EXCEPTION 'CODE: message' у Матвея: машинный код читаем
    // из начала сообщения (соглашение из его письма).
    final msg = e.message;
    final dbCode = _dbCode(msg) ?? e.code;

    switch (dbCode) {
      case 'ORDER_NOT_FOUND':
        return Failures.orderNotFound();
      case 'STAGE_INVALID_ORDER':
        if (msg.contains('cancelled') || msg.contains('completed')) {
          return Failures.orderClosed();
        }
        if (msg.contains('woke')) {
          return failure(
            FailureCode.notMorningOrder,
            'Этап «Проснулся» — только для утренних заказов (4:00–12:00).',
          );
        }
        return Failures.wrongStageOrder();
      case 'STAGE_NOT_YOUR_TURN':
        return Failures.wrongStageOrder();
      case 'PERMISSION_DENIED':
        if (msg.contains('lead')) return Failures.leadOnly();
        if (msg.contains('dispatcher') || msg.contains('admin')) {
          return failure(FailureCode.forbidden, 'Это действие доступно диспетчеру.');
        }
        return Failures.notInBrigade();
      case 'VALIDATION_FAILED':
        return Failures.validation('server', _humanPart(msg) ?? 'Проверьте введённые данные.');
      case 'RATE_LIMITED':
        return failure(
          FailureCode.rateLimited,
          'Слишком часто. Подождите минуту и попробуйте снова.',
          retryable: true,
        );
      case 'ROLE_NOT_ASSIGNED':
        return failure(FailureCode.forbidden, 'Роль не назначена этому пользователю.');
      case '42501': // RLS: row-level security violation
        return failure(FailureCode.forbidden, 'Недостаточно прав на это действие.');
      case 'P0002': // no data found
        return Failures.orderNotFound();
      case '23505': // unique_violation: идемпотентность этапов покрыта на бэке
        return Failures.stageAlreadySet();
      default:
        return Failures.server(_humanPart(msg) ?? e.message);
    }
  }

  /// 'STAGE_NOT_YOUR_TURN: cannot mark ...' → 'STAGE_NOT_YOUR_TURN'.
  String? _dbCode(String message) {
    final m = RegExp(r'^([A-Z][A-Z0-9_]{2,}):').firstMatch(message.trim());
    return m?.group(1);
  }

  /// Человекочитаемый хвост сообщения после кода.
  String? _humanPart(String message) {
    final i = message.indexOf(':');
    if (i < 0 || i + 2 > message.length) return null;
    final tail = message.substring(i + 1).trim();
    return tail.isEmpty ? null : tail;
  }
}
