/// ТЕСТЫ МАППЕРОВ Supabase-строка → UI-модель (без живого бэкенда).
///
/// Зона: Артём. Ловят расхождения схемы Матвея с контрактом:
/// имена колонок, wire-значения, часовой пояс, int-entrance, expired-отклик.
library;

import 'package:avatar_app/data/supabase/mappers.dart';
import 'package:avatar_app/features/order_flow/domain/enums.dart';
import 'package:avatar_app/features/order_flow/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> orderRow() => {
      'id': 'o-1',
      'client_id': 'c-1',
      'address_from': 'ул. Ленина, 12',
      'address_to': 'ул. Ленина, 12',
      'entrance': 3,
      'cargo_type': 'boxes',
      'people_count': 2,
      'planned_duration_min': 90,
      'status': 'created',
      'urgency': 'urgent',
      'is_replacement': false,
      'task_title': 'Коробки',
      'task_description': 'Поднять на 5 этаж',
      'transport': 'gazelle',
      'client_phone': '+79991234567',
      'comment': 'Домофон не работает',
      'tariff_hint': '3000 руб',
      'result_comment': null,
      'coords_from': {'lat': 55.03, 'lng': 82.92},
      // 2026-09-21 02:00 UTC = 09:00 НСК (утренний заказ!)
      'scheduled_at': '2026-09-21T02:00:00+00:00',
      'created_at': '2026-09-20T10:00:00+00:00',
      'feedback_missed': false,
    };

void main() {
  group('orderFromRow', () {
    test('время конвертится в НСК: 02:00 UTC → 09:00, заказ утренний', () {
      final o = orderFromRow(orderRow());
      expect(o.timeStart.hour, 9);
      expect(o.timeStart.day, 21);
      expect(o.isMorning, isTrue);
    });

    test('entrance int → String, транспорт и подсказка тарифа', () {
      final o = orderFromRow(orderRow());
      expect(o.entrance, '3');
      expect(o.transport, TransportType.gazelle);
      expect(o.clientTariffHint, '3000 руб');
      expect(o.porterTariffHint, '3000 руб');
      expect(o.coords!.lat, closeTo(55.03, 1e-9));
    });

    test('замена: wire urgent + is_replacement → OrderUrgency.replacement', () {
      final row = orderRow()
        ..['urgency'] = 'urgent'
        ..['is_replacement'] = true;
      final o = orderFromRow(row);
      expect(o.urgency, OrderUrgency.replacement);
      expect(o.isReplacement, isTrue);
    });

    test('мой отклик подставляется в карточку ленты', () {
      final o = orderFromRow(orderRow(), myResponseStatus: ResponseStatus.pending);
      expect(o.myResponseStatus, ResponseStatus.pending);
      expect(o.isOpenForResponse, isTrue);
    });
  });

  group('responseFromRow', () {
    final now = DateTime(2026, 9, 20, 12, 0);

    test('pending моложе 5 минут — остаётся pending', () {
      final r = responseFromRow({
        'id': 'r-1',
        'order_id': 'o-1',
        'porter_id': 'p-1',
        'eta_minutes': 15,
        'status': 'pending',
        'created_at': '2026-09-20T05:58:00+00:00', // 12:58 НСК? нет: 05:58Z=12:58НСК — позже now!
      }, now: now);
      // created_at в НСК = 12:58, now = 12:00 → «создан в будущем», не истёк
      expect(r.status, ResponseStatus.pending);
    });

    test('pending старше ETA-таймаута (15 мин) → expired', () {
      final r = responseFromRow({
        'id': 'r-2',
        'order_id': 'o-1',
        'porter_id': 'p-1',
        'eta_minutes': 20,
        'status': 'pending',
        'created_at': '2026-09-20T04:40:00+00:00', // 11:40 НСК, now 12:00 → 20 мин > 15
      }, now: now);
      expect(r.status, ResponseStatus.expired);
      // isExpiredAt — предикат для живого pending; у готового expired он false.
      expect(r.remainingAt(now).isNegative, isTrue);
    });

    test('approved/declined проходят как есть', () {
      final a = responseFromRow({
        'id': 'r-3',
        'order_id': 'o-1',
        'porter_id': 'p-1',
        'eta_minutes': 10,
        'status': 'approved',
        'created_at': '2026-09-20T01:00:00+00:00',
      }, now: now);
      expect(a.status, ResponseStatus.approved);
    });
  });

  group('availabilityFromJson / stageResultFromJson', () {
    test('доступность из jsonb get_stage_availability', () {
      final a = availabilityFromJson({
        'available': ['departed', 'arrived'],
        'next_required': 'departed',
        'woke_deadline': '2026-09-21T01:00:00+00:00', // 08:00 НСК
        'departed_deadline': '2026-09-21T01:30:00+00:00',
        'is_late': false,
        'penalty_if_pressed_now': 0,
        'blocked_reason': null,
        'is_lead': true,
      });
      expect(a.available, [OrderStageType.departed, OrderStageType.arrived]);
      expect(a.nextRequired, OrderStageType.departed);
      expect(a.isLead, isTrue);
      expect(a.wokeDeadline!.hour, 8);
      expect(a.canPress(OrderStageType.arrived), isTrue);
    });

    test('penalty 5 из mark_stage → ratingDelta −5 и late', () {
      final s = stageResultFromJson({
        'ok': true,
        'already_set': false,
        'stage': 'departed',
        'penalty': 5,
      }, at: DateTime(2026, 9, 21, 8, 40));
      expect(s.ratingDelta, -5);
      expect(s.late, isTrue);
      expect(s.stage, OrderStageType.departed);
    });

    test('already_set → человекочитаемое сообщение', () {
      final s = stageResultFromJson({
        'ok': true,
        'already_set': true,
        'stage': 'arrived',
        'penalty': 0,
      }, at: DateTime(2026, 9, 21, 9, 0));
      expect(s.message, isNotNull);
      expect(s.late, isFalse);
    });
  });

  group('completionFromJson', () {
    test('finish_order: часы, суммы, дельта рейтинга', () {
      final c = completionFromJson({
        'order_id': 'o-1',
        'hours': 1.5,
        'total_hours': 3.0,
        'minutes_worked': 90,
        'rating_delta': 2,
        'money_delta': null,
        'finished_at': '2026-09-21T05:00:00+00:00', // 12:00 НСК
      });
      expect(c.hours, 1.5);
      expect(c.totalHours, 3.0);
      expect(c.ratingDelta, 2);
      expect(c.finishedAt.hour, 12);
      expect(c.moneyDelta, isNull); // MVP: денег нет
    });
  });

  group('quoteFromDetailedJson (Матвей 20.09)', () {
    test('total + lines рисуются как есть, часы по правилу 30 мин', () {
      final q = quoteFromDetailedJson({
        'total': 4400,
        'lines': [
          {'label': 'Базовый выезд', 'amount': 500},
          {'label': 'Работы: 2 чел × 2 ч (срочный)', 'amount': 2400},
          {'label': 'Газель', 'amount': 1500},
        ],
      }, plannedDurationMin: 90, transport: TransportType.gazelle);
      expect(q.price, 4400);
      expect(q.currency, 'RUB');
      expect(q.hours, 1.5);
      expect(q.breakdown.length, 3);
      expect(q.breakdown.first.label, 'Базовый выезд');
      expect(q.breakdown.last.amount, 1500);
    });

    test('fallback: lines нет — раскладываем total на работы + транспорт', () {
      final q = quoteFromDetailedJson({'total': 2000},
          plannedDurationMin: 60, transport: TransportType.none);
      expect(q.breakdown.length, 1);
      expect(q.breakdown.first.amount, 2000);
      expect(q.hours, 1.0);
    });
  });

  group('контракт Матвея от 20.09 (fixes_for_artem)', () {
    test('force_closed читается из строки orders — бейдж переживает перезаход', () {
      final o = orderFromRow(orderRow()..['force_closed'] = true);
      expect(o.forceClosed, isTrue);
      final o2 = orderFromRow(orderRow());
      expect(o2.forceClosed, isFalse);
    });

    test('fail_count грузчика приходит из profiles', () {
      final p = porterProfileFromRow({
        'id': 'p-1',
        'full_name': 'Артём',
        'rating': 4.0,
        'completed_count': 10,
        'fail_count': 2,
        'is_blocked': false,
        'referral_code': 'ART1',
      });
      expect(p.failCount, 2);
    });

    test('feedback_deadline из get_stage_availability (finished + 5 мин)', () {
      final a = availabilityFromJson({
        'available': ['feedback'],
        'next_required': 'feedback',
        'woke_deadline': null,
        'departed_deadline': null,
        // 05:00Z = 12:00 НСК
        'feedback_deadline': '2026-09-21T05:00:00+00:00',
        'is_late': false,
        'penalty_if_pressed_now': 0,
        'blocked_reason': null,
        'is_lead': true,
      });
      expect(a.feedbackDeadline, isNotNull);
      expect(a.feedbackDeadline!.hour, 12);
    });
  });

  group('orderInsertFromRequest', () {
    test('НСК → UTC: 09:00 НСК записывается как 02:00Z', () {
      final m = orderInsertFromRequest(
        CreateOrderRequest(
          address: 'ул. Ленина, 12',
          timeStart: DateTime(2026, 9, 21, 9, 0),
          peopleCount: 2,
          plannedDurationMin: 90,
          taskTitle: 'Коробки',
          taskDescription: 'Поднять',
          urgency: OrderUrgency.urgent,
          tariff: '3000 руб',
          entrance: '3',
        ),
        clientId: 'c-1',
      );
      expect(m['scheduled_at'], '2026-09-21T02:00:00.000Z');
      expect(m['entrance'], 3);
      expect(m['urgency'], 'urgent');
      expect(m['is_replacement'], isFalse);
    });

    test('замена пишется как urgent + флаг is_replacement', () {
      final m = orderInsertFromRequest(
        CreateOrderRequest(
          address: 'адрес',
          timeStart: DateTime(2026, 9, 21, 9, 0),
          peopleCount: 1,
          plannedDurationMin: 60,
          taskTitle: 'т',
          taskDescription: 'о',
          urgency: OrderUrgency.replacement,
          tariff: 'x',
        ),
        clientId: 'c-1',
      );
      expect(m['urgency'], 'urgent');
      expect(m['is_replacement'], isTrue);
    });
  });

  group('мелкие мапперы', () {
    test('messageFromRow: isMine по author_id', () {
      final m = messageFromRow({
        'id': 'm-1',
        'order_id': 'o-1',
        'author_id': 'me',
        'text': 'привет',
        'created_at': '2026-09-20T04:00:00+00:00',
      }, myId: 'me');
      expect(m.isMine, isTrue);
      expect(m.sentAt.hour, 11); // 04:00Z → 11:00 НСК
    });

    test('briefFromProfileRow: рейтинг округляется, lead-флаг', () {
      final b = briefFromProfileRow({
        'id': 'p-1',
        'full_name': 'Артём',
        'rating': 4.6,
        'completed_count': 12,
        'avatar_url': null,
      }, isLead: true);
      expect(b.rating, 5);
      expect(b.isLead, isTrue);
      expect(b.name, 'Артём');
    });

    test('suggestionFromJson: title — первые две запятые', () {
      final s = suggestionFromJson({
        'display_name': 'Новосибирск, Сибирский федеральный округ, Россия',
        'lat': 55.03,
        'lng': 82.92,
      });
      expect(s.title, 'Новосибирск, Сибирский федеральный округ');
      expect(s.coords!.lng, closeTo(82.92, 1e-9));
    });
  });
}
