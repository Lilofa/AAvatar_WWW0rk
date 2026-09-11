/// ЕДИНЫЙ ТИП ОШИБКИ ПРИЛОЖЕНИЯ.
///
/// Просьба к Матвею: репозитории бросают ИМЕННО это, а не сырые
/// `PostgrestException` / `AuthException` / `SocketException`.
/// Иначе русский текст ошибки придётся писать в каждом экране,
/// а это уже зона Коли (снакбары) и моя (формулировки) — получится зоопарк.
library;

/// Машинный код ошибки — по нему UI решает, ЧТО делать.
/// Текст — для человека, уже готовый к показу в снакбаре.
enum FailureCode {
  // сеть и сервер
  offline,
  timeout,
  server,
  unknown,

  // доступ
  unauthorized,
  forbidden,

  // заказ
  orderNotFound,
  orderAlreadyTaken, // гонка: заказ забрали у нас из-под носа
  orderNotApproved,
  orderClosed,
  orderCancelled,

  // отклик
  responseAlreadyExists,
  responseExpired, // 5 минут на одобрение истекли
  etaRejected,

  // этапы
  wrongStageOrder,
  stageAlreadySet,
  leadOnly,
  notMorningOrder,
  morningDeadlineMissed, // не ошибка, а «успех со штрафом» — но UI должен показать
  feedbackWindowClosed,
  overtimeRequiresReason,

  // валидация ввода
  validation,

  // создание заявки
  addressNotFound,
  tariffUnavailable,

  // отзывы
  reviewAlreadySubmitted,
  reviewNotAllowed;
}

class AppFailure implements Exception {
  const AppFailure({
    required this.code,
    required this.message,
    this.retryable = false,
    this.details,
    this.cause,
  });

  final FailureCode code;

  /// Готовый русский текст. Показываем как есть — не конструируем в виджетах.
  final String message;

  /// Имеет ли смысл кнопка «Повторить».
  final bool retryable;

  /// Отладочная инфа (id заказа, имя поля). НЕ показываем пользователю.
  final Map<String, Object?>? details;

  final Object? cause;

  /// Ошибка означает, что экран должен сменить своё состояние целиком,
  /// а не просто показать снакбар. Например, заказ забрали — уходим из active.
  bool get isFatalForScreen => switch (code) {
        FailureCode.orderAlreadyTaken ||
        FailureCode.orderClosed ||
        FailureCode.orderCancelled ||
        FailureCode.orderNotFound ||
        FailureCode.forbidden =>
          true,
        _ => false,
      };

  /// Показывать ли кнопку «Повторить» в ErrorState.
  bool get showRetry => retryable || code == FailureCode.server || code == FailureCode.timeout;

  @override
  String toString() => 'AppFailure(${code.name}): $message';
}

/// Быстрые конструкторы — чтобы Матвею не писать длинные литералы.
abstract final class Failures {
  static AppFailure offline() => const AppFailure(
        code: FailureCode.offline,
        message: 'Нет соединения. Проверьте интернет и попробуйте снова.',
        retryable: true,
      );

  static AppFailure timeout() => const AppFailure(
        code: FailureCode.timeout,
        message: 'Сервер не ответил вовремя. Повторите попытку.',
        retryable: true,
      );

  static AppFailure server([String? detail]) => AppFailure(
        code: FailureCode.server,
        message: 'Ошибка на сервере. Мы уже знаем и чиним.',
        retryable: true,
        details: detail == null ? null : {'detail': detail},
      );

  static AppFailure unknown(Object e) => AppFailure(
        code: FailureCode.unknown,
        message: 'Что-то пошло не так. Попробуйте ещё раз.',
        retryable: true,
        cause: e,
      );

  static AppFailure orderAlreadyTaken() => const AppFailure(
        code: FailureCode.orderAlreadyTaken,
        message: 'Заказ уже взят другим грузчиком.',
      );

  static AppFailure orderClosed() => const AppFailure(
        code: FailureCode.orderClosed,
        message: 'Заказ закрыт. Действия недоступны.',
      );

  static AppFailure leadOnly() => const AppFailure(
        code: FailureCode.leadOnly,
        message: 'Этот этап нажимает только старший бригады.',
      );

  static AppFailure wrongStageOrder() => const AppFailure(
        code: FailureCode.wrongStageOrder,
        message: 'Сначала завершите предыдущий этап.',
      );

  static AppFailure responseExpired() => const AppFailure(
        code: FailureCode.responseExpired,
        message: 'Время на одобрение отклика истекло (5 минут).',
      );

  static AppFailure feedbackWindowClosed() => const AppFailure(
        code: FailureCode.feedbackWindowClosed,
        message: 'Окно обратной связи закрылось. Заказ закрыт без комментария.',
      );

  static AppFailure validation(String field, String problem) => AppFailure(
        code: FailureCode.validation,
        message: problem,
        details: {'field': field},
      );

  static AppFailure unauthorized() => const AppFailure(
        code: FailureCode.unauthorized,
        message: 'Сессия истекла. Войдите заново.',
      );
}
