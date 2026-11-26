/// РЕАЛИЗАЦИЯ OrdersRepository НА SUPABASE (живые данные).
///
/// Зона: Артём (поток заказа) поверх контракта Матвея (RPC + RLS + realtime).
/// Экраны не знают о Supabase: подмена mock ↔ live — одна строка в main.dart.
///
/// 🔑 Соглашения:
///  * Ошибки наружу — только AppFailure (через [SupabaseErrorMapper]).
///  * Время: провод — UTC, UI — НСК (конвертация в mappers.dart).
///  * Realtime-потоки: SupabaseStreamBuilder (.stream) по таблицам,
///    публикация supabase_realtime включена миграцией Матвея.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error/app_failure.dart';
import '../../core/monitoring/app_monitor.dart';
import '../../features/order_flow/domain/enums.dart';
import '../../features/order_flow/domain/models.dart';
import '../orders_repository.dart';
import 'mappers.dart';
import 'supabase_error_mapper.dart';

class SupabaseOrdersRepository implements OrdersRepository {
  SupabaseOrdersRepository(this._client, {SupabaseErrorMapper? errorMapper})
      : _err = errorMapper ?? const SupabaseErrorMapper();

  final SupabaseClient _client;
  final SupabaseErrorMapper _err;

  String get _myId => _client.auth.currentUser?.id ?? '';

  // ── обёртка ошибок: наружу только AppFailure ────────────────
  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on AppFailure catch (f) {
      AppMonitor.failure(f, where: 'data');
      rethrow;
    } on FunctionException catch (e) {
      // edge-функции отвечают {ok:false,error:'...'} с 4xx/5xx
      final msg = (e.details is Map ? (e.details as Map)['error'] : e.details)?.toString();
      throw switch (e.status) {
        429 => Failures.rateLimited(),
        401 => Failures.unauthorized(),
        403 => Failures.forbidden(),
        400 => Failures.validation('code', 'Неверный или просроченный код. Запросите новый.'),
        _ => Failures.server(msg ?? e.reasonPhrase),
      };
    } catch (e) {
      final f = _err.map(e);
      AppMonitor.failure(f, where: 'data');
      throw f;
    }
  }

  Stream<T> _guardStream<T>(Stream<T> Function() build) async* {
    try {
      yield* build();
    } on AppFailure {
      rethrow;
    } catch (e) {
      final f = _err.map(e);
      AppMonitor.failure(f, where: 'data-stream');
      throw f;
    }
  }

  Future<Map<String, dynamic>> _invokeJson(String fn, Map<String, dynamic> body) =>
      _guard(() async {
        final res = await _client.functions.invoke(fn, body: body);
        final data = res.data;
        if (data is Map<String, dynamic>) {
          if (data['ok'] == false) {
            throw Failures.server(data['error']?.toString());
          }
          return data;
        }
        if (data is Map) return data.map((k, v) => MapEntry(k.toString(), v));
        return <String, dynamic>{};
      });

  Future<Map<String, dynamic>> _rpcJson(String fn, [Map<String, dynamic>? params]) =>
      _guard(() async {
        final raw = await _client.rpc(fn, params: params ?? const {});
        final m = raw is Map
            ? raw.map((k, v) => MapEntry(k.toString(), v))
            : <String, dynamic>{};
        return m;
      });

  Future<void> _rpcVoid(String fn, [Map<String, dynamic>? params]) =>
      _guard(() async {
        await _client.rpc(fn, params: params ?? const {});
      });

  /// Кэш имён профилей (бригада/чат/отзывы), чтобы не дёргать БД на каждый кадр.
  final Map<String, Map<String, dynamic>> _profileCache = {};

  Future<Map<String, Map<String, dynamic>>> _profilesById(Iterable<String> ids) =>
      _guard(() async {
        final missing = ids.where((id) => !_profileCache.containsKey(id)).toSet();
        if (missing.isNotEmpty) {
          final rows = await _client
              .from('profiles')
              .select()
              .inFilter('id', missing.toList());
          for (final r in rows) {
            _profileCache[r['id'] as String] = r;
          }
        }
        return {
          for (final id in ids.toSet())
            if (_profileCache.containsKey(id)) id: _profileCache[id]!,
        };
      });

  // ═══════════════════════════════════════════════════════════
  // 1. АВТОРИЗАЦИЯ И ПРОФИЛЬ
  // ═══════════════════════════════════════════════════════════

  @override
  Future<void> signOut() async {
    _profileCache.clear();
    _signed.clear();
    try {
      // gotrue стирает локальную сессию ДО сетевого вызова, поэтому даже
      // без интернета пользователь выходит; ошибку сети просто глотаем.
      await _client.auth.signOut();
    } catch (_) {}
  }

  @override
  Future<void> sendSmsCode({required String phone}) => _guard(() async {
        await _invokeJson('send-sms', {'phone': phone});
      });

  @override
  Future<AuthResult> verifySmsCode({
    required String phone,
    required String code,
    String? fullName,
    String? consentVersion,
  }) =>
      _guard(() async {
        final data = await _invokeJson('verify-sms', {
          'phone': phone,
          'code': code,
          if (fullName != null) 'full_name': fullName,
          if (consentVersion != null) 'consent_version': consentVersion,
        });
        final tokenHash = data['token_hash'] as String?;
        if (tokenHash == null) throw Failures.unauthorized();
        // ВАЖНО (прод-фикс 31.10): GoTrue на проде (v2.197.0) принимает
        // ТОЛЬКО {type, token_hash}. Любой третий параметр — 400:
        //   {"error_code":"validation_failed",
        //    "msg":"Only the token_hash and type should be provided"}
        // Поэтому phone сюда НЕ передаём: пользователь в verify-sms создан
        // по синтетическому email (<номер>@phone.local), а token_hash сам
        // указывает на пользователя. gotrue 2.27.2 это разрешает: при
        // tokenHash != null assert про email/phone не срабатывает.
        await _client.auth.verifyOTP(
          type: OtpType.magiclink,
          tokenHash: tokenHash,
        );
        final userId = _client.auth.currentUser?.id ?? data['userId'] as String;
        final row = await _client.from('profiles').select().eq('id', userId).single();
        final profileRow = row;
        final roles = rolesFromProfileRow(profileRow);
        return AuthResult(
          userId: userId,
          roles: roles,
          profile: roles.contains(UserRole.porter)
              ? porterProfileFromRow(profileRow)
              : null,
        );
      });

  @override
  Stream<UserProfile?> watchCurrentUser() => _guardStream(() async* {
        Future<UserProfile?> load(String? uid) async {
          if (uid == null) return null;
          final rows = await _profilesById([uid]);
          final r = rows[uid];
          return r == null ? null : userProfileFromRow(r);
        }

        yield await load(_client.auth.currentUser?.id);
        // Профиль перечитываем при смене сессии и по [refreshCurrentUser]
        // (например, диспетчер одобрил заявку — появилась роль грузчика).
        final ids = StreamController<String?>();
        final onAuth = _client.auth.onAuthStateChange
            .listen((state) => ids.add(state.session?.user.id));
        final onRefresh = _profileRefresh.stream
            .listen((_) => ids.add(_client.auth.currentUser?.id));
        try {
          yield* ids.stream.asyncMap(load);
        } finally {
          await onAuth.cancel();
          await onRefresh.cancel();
          await ids.close();
        }
      });

  final StreamController<void> _profileRefresh =
      StreamController<void>.broadcast();

  @override
  Future<void> refreshCurrentUser() async {
    _profileCache.clear();
    _profileRefresh.add(null);
  }

  @override
  Future<PorterProfile> getPorterProfile({required String userId}) => _guard(() async {
        final row = await _client.from('profiles').select().eq('id', userId).single();
        final count = await _client
            .from('profiles')
            .count(CountOption.exact)
            .eq('invited_by', userId);
        return porterProfileFromRow(row,
            referralsCount: count);
      });

  @override
  Future<String?> getReferralCode({required String userId}) => _guard(() async {
        final row = await _client
            .from('profiles')
            .select('referral_code')
            .eq('id', userId)
            .maybeSingle();
        return row?['referral_code'] as String?;
      });

  // ═══════════════════════════════════════════════════════════
  // 2. ЛЕНТА И ОТКЛИК
  // ═══════════════════════════════════════════════════════════

  @override
  Stream<FeedPage> watchFeed(
          {FeedFilter filter = FeedFilter.all, int limit = 30, String? cursor}) =>
      _guardStream(() {
        // Триггеры обновления: сами заказы (realtime), мои отклики
        // (чип статуса на карточке без pull-to-refresh) и бригада для «Моих».
        // Слияние без package:async: SDK пинит свою версию async, и явная
        // зависимость отправляла solver pub в комбинаторный перебор (10+ мин).
        final subs = <StreamSubscription<dynamic>>[];
        final ctrl = StreamController<int>(
          onCancel: () {
            for (final s in subs) {
              s.cancel();
            }
          },
        );
        void pipe(Stream<Object?> src, int tag) => subs.add(
              src.listen((_) => ctrl.add(tag), onError: ctrl.addError),
            );
        pipe(_client.from('orders').stream(primaryKey: ['id']), 0);
        pipe(
          _client
              .from('order_responses')
              .stream(primaryKey: ['id'])
              .eq('porter_id', _myId),
          1,
        );
        if (filter.onlyMine) {
          pipe(
            _client
                .from('order_takers')
                .stream(primaryKey: ['order_id', 'porter_id'])
                .eq('porter_id', _myId),
            2,
          );
        }
        return ctrl.stream.asyncMap((_) => _fetchFeedPage(filter, limit));
      });

  /// Разовая сборка страницы ленты (по триггеру из watchFeed).
  Future<FeedPage> _fetchFeedPage(FeedFilter filter, int limit) async {
    List<Map<String, dynamic>> items;
    if (filter.onlyMine) {
      final takers = await _client
          .from('order_takers')
          .select('order_id')
          .eq('porter_id', _myId);
      final ids = takers.map((t) => t['order_id'] as String).toList();
      items = ids.isEmpty
          ? const []
          : (await _client.from('orders').select().inFilter('id', ids))
              .cast<Map<String, dynamic>>()
              .where((r) =>
                  OrderStatus.fromWire(r['status'] as String? ?? '').isLive)
              .toList();
    } else {
      var q = _client.from('orders').select().eq('status', 'created');
      if (filter.urgencies != null && filter.urgencies!.isNotEmpty) {
        q = q.inFilter(
            'urgency', filter.urgencies!.map((u) => u.wire).toSet().toList());
      }
      if (filter.dateFrom != null) {
        q = q.gte('scheduled_at', nskToWireUtc(filter.dateFrom!));
      }
      if (filter.dateTo != null) {
        q = q.lte('scheduled_at', nskToWireUtc(filter.dateTo!));
      }
      items = (await q.order('scheduled_at', ascending: true))
          .cast<Map<String, dynamic>>();
    }
    final myResponses =
        await _myResponsesFor(items.map((r) => r['id'] as String).toList());
    final now = DateTime.now();
    final filtered = filter != FeedFilter.all;
    return FeedPage(
      items: items
          .map((r) => orderFromRow(
                r,
                myResponseStatus: myResponses[r['id']],
                now: now,
                clientIsMe: r['client_id'] == _myId,
              ))
          .take(limit)
          .toList(),
      emptyReason: await _feedEmptyReason(items.isEmpty, filtered),
    );
  }

  Future<Map<String, ResponseStatus>> _myResponsesFor(List<String> orderIds) async {
    if (orderIds.isEmpty || _myId.isEmpty) return const {};
    final rows = await _client
        .from('order_responses')
        .select()
        .eq('porter_id', _myId)
        .inFilter('order_id', orderIds);
    final now = DateTime.now();
    return {
      for (final r in rows)
        r['order_id'] as String:
            responseFromRow(r, now: now).status,
    };
  }

  Future<FeedEmptyReason> _feedEmptyReason(bool pageEmpty, bool filtered) async {
    if (!pageEmpty) return FeedEmptyReason.noOrders; // не используется
    final open = await _client
        .from('orders')
        .count(CountOption.exact)
        .eq('status', 'created');
    if (open > 0 && filtered) return FeedEmptyReason.filteredOut;
    if (open > 0) return FeedEmptyReason.noOrders;
    final live = await _client
        .from('orders')
        .count(CountOption.exact)
        .inFilter('status', const ['accepted', 'in_progress']);
    return live > 0 ? FeedEmptyReason.allTaken : FeedEmptyReason.noOrders;
  }

  @override
  Future<Order> getOrder({required String orderId}) => _guard(() async {
        final row = await _client.from('orders').select().eq('id', orderId).single();
        final my = await _myResponsesFor([orderId]);
        return orderFromRow(row,
            myResponseStatus: my[orderId],
            now: DateTime.now(),
            clientIsMe: row['client_id'] == _myId);
      });

  @override
  Future<OrderResponse> respondToOrder(
          {required String orderId, required int etaMinutes}) =>
      _guard(() async {
        final id = await _client.rpc('respond_to_order', params: {
          'p_order_id': orderId,
          'p_eta_minutes': etaMinutes,
        });
        final row = await _client
            .from('order_responses')
            .select()
            .eq('id', id as String)
            .single();
        return responseFromRow(row, now: DateTime.now());
      });

  @override
  Future<void> cancelResponse({required String responseId}) =>
      _rpcVoid('cancel_response', {'p_response_id': responseId});

  @override
  Stream<OrderResponse?> watchMyResponse({required String orderId}) =>
      _guardStream(() => _client
          .from('order_responses')
          .stream(primaryKey: ['id'])
          .eq('order_id', orderId)
          .eq('porter_id', _myId)
          .map((rows) => rows.isEmpty
              ? null
              : responseFromRow(rows.last,
                  now: DateTime.now())));

  // ═══════════════════════════════════════════════════════════
  // 3. ЭТАПЫ
  // ═══════════════════════════════════════════════════════════

  @override
  Stream<List<OrderStage>> watchOrderStages({required String orderId}) =>
      _guardStream(() => _client
          .from('order_stages')
          .stream(primaryKey: ['id'])
          .eq('order_id', orderId)
          .order('created_at', ascending: true)
          .asyncMap((rows) async {
        final names = await _profilesById(
            rows.map((r) => r['porter_id'] as String).toList());
        return rows
            .map((r) => stageFromRow(r,
                porterName: names[r['porter_id']]?['full_name'] as String?))
            .toList();
      }));

  @override
  Future<StageResult> setStage({
    required String orderId,
    required OrderStageType stage,
    DateTime? clientTime,
    GeoPoint? location,
  }) =>
      _guard(() async {
        final j = await _rpcJson('mark_stage', {
          'p_order_id': orderId,
          'p_stage': stage.name,
          if (location != null)
            'p_coords': {'lat': location.lat, 'lng': location.lng},
        });
        return stageResultFromJson(j, at: clientTime ?? DateTime.now());
      });

  @override
  Future<StageAvailability> getStageAvailability({required String orderId}) =>
      _guard(() async {
        final j = await _rpcJson('get_stage_availability', {'p_order_id': orderId});
        return availabilityFromJson(j);
      });

  @override
  Future<void> submitDelayReason({required String orderId, required String reason}) =>
      _rpcVoid('submit_delay_reason', {'p_order_id': orderId, 'p_reason': reason});

  // ═══════════════════════════════════════════════════════════
  // 4. БРИГАДА И СТАРШИЙ
  // ═══════════════════════════════════════════════════════════

  @override
  Stream<PorterBrief?> watchLead({required String orderId}) => _guardStream(
        () => _client
            .from('order_takers')
            .stream(primaryKey: ['order_id', 'porter_id'])
            .eq('order_id', orderId)
            .eq('is_lead', true)
            .asyncMap((rows) async {
          if (rows.isEmpty) return null;
          final r = rows.first;
          final prof = await _profilesById([r['porter_id'] as String]);
          final p = prof[r['porter_id']];
          return p == null ? null : briefFromProfileRow(p, isLead: true);
        }),
      );

  @override
  Stream<List<OrderTaker>> watchOrderTakers({required String orderId}) =>
      _guardStream(
        () => _client
            .from('order_takers')
            .stream(primaryKey: ['order_id', 'porter_id'])
            .eq('order_id', orderId)
            .asyncMap((rows) async {
          final profs = await _profilesById(
              rows.map((r) => r['porter_id'] as String).toList());
          return rows.map((r) {
            final p = profs[r['porter_id']];
            return takerFromRow(
              r,
              porter: p == null
                  ? PorterBrief(id: r['porter_id'] as String, name: 'Грузчик')
                  : briefFromProfileRow(p),
            );
          }).toList();
        }),
      );

  // ═══════════════════════════════════════════════════════════
  // 5. ЗАКРЫТИЕ И ОБРАТНАЯ СВЯЗЬ
  // ═══════════════════════════════════════════════════════════

  @override
  Future<OrderCompletion> finishOrder({
    required String orderId,
    required bool wentWell,
    String? resultComment,
  }) =>
      _guard(() async {
        final j = await _rpcJson('finish_order', {
          'p_order_id': orderId,
          'p_went_well': wentWell,
          if (resultComment != null) 'p_result_comment': resultComment,
        });
        return completionFromJson(j);
      });

  @override
  Stream<OrderStatus> watchOrderStatus({required String orderId}) => _guardStream(
        () => _client
            .from('orders')
            .stream(primaryKey: ['id'])
            .eq('id', orderId)
            .map((rows) =>
                OrderStatus.fromWire(rows.first['status'] as String? ?? 'created')),
      );

  // ═══════════════════════════════════════════════════════════
  // 6. ОТЗЫВЫ И РЕЙТИНГ
  // ═══════════════════════════════════════════════════════════

  @override
  Future<void> submitClientReview(
          {required String orderId, required int rating, String? text}) =>
      // 🔴 Новая сигнатура Матвея от 18.09: target_id опционален (отзыв о заказе).
      _rpcVoid('submit_review', {
        'p_order_id': orderId,
        'p_rating': rating,
        if (text != null) 'p_text': text,
        'p_target_id': null,
      });

  @override
  Future<List<Review>> getPorterReviews({required String porterId, int limit = 20}) =>
      _guard(() async {
        final rows = await _client
            .from('reviews')
            .select()
            .eq('target_id', porterId)
            .order('created_at', ascending: false)
            .limit(limit);
        return rows
            .map((r) => reviewFromRow(r))
            .toList();
      });

  @override
  Stream<int> watchPendingReviewCount() => _guardStream(
        () => _client
            .from('orders')
            .stream(primaryKey: ['id'])
            .eq('client_id', _myId)
            .asyncMap((_) => _guard(() async {
                  final n = await _client.rpc('get_pending_review_count');
                  return n is int ? n : int.tryParse(n.toString()) ?? 0;
                })),
      );

  // ═══════════════════════════════════════════════════════════
  // 7. ЧАТ ПО ЗАКАЗУ
  // ═══════════════════════════════════════════════════════════

  @override
  Stream<List<ChatMessage>> watchOrderChat({required String orderId, int limit = 50}) =>
      _guardStream(
        () => _client
            .from('messages')
            .stream(primaryKey: ['id'])
            .eq('order_id', orderId)
            .order('created_at', ascending: true)
            .asyncMap((rows) async {
          final profs = await _profilesById(
              rows.map((r) => r['author_id'] as String).toList());
          return rows
              .take(limit)
              .map((r) => messageFromRow(
                    r,
                    myId: _myId,
                    authorName: profs[r['author_id']]?['full_name'] as String?,
                    authorRole: profs[r['author_id']] == null
                        ? null
                        : rolesFromProfileRow(profs[r['author_id']]!)
                            .firstOrNullRole,
                  ))
              .toList();
        }),
      );

  @override
  Future<void> sendOrderChatMessage({
    required String orderId,
    required String text,
    String? attachmentUrl,
  }) =>
      _guard(() async {
        await _client.from('messages').insert({
          'order_id': orderId,
          'author_id': _myId,
          'text': text,
          if (attachmentUrl != null) 'attachment_url': attachmentUrl,
        });
      });

  // ═══════════════════════════════════════════════════════════
  // 8. ЗАКАЗЧИК: СОЗДАНИЕ ЗАЯВКИ
  // ═══════════════════════════════════════════════════════════

  @override
  Future<Order> createOrder(CreateOrderRequest request) => _guard(() async {
        final row = await _client
            .from('orders')
            .insert(orderInsertFromRequest(request, clientId: _myId))
            .select()
            .single();
        return orderFromRow(row, now: DateTime.now(), clientIsMe: true);
      });

  @override
  Future<List<AddressSuggestion>> searchAddress({required String query}) =>
      _guard(() async {
        final data = await _invokeJson('search-address', {'query': query});
        final results = data['results'] as List? ?? const [];
        return results
            .map((e) => suggestionFromJson((e as Map).cast<String, dynamic>()))
            .toList();
      });

  @override
  Future<TariffQuote> quoteOrder({
    required int peopleCount,
    required int plannedDurationMin,
    required OrderUrgency urgency,
    TransportType transport = TransportType.none,
  }) =>
      _guard(() async {
        // Матвей 20.09: детализированный расчёт для калькулятора заказчика.
        final j = await _rpcJson('quote_order_detailed', {
          'p_people_count': peopleCount,
          'p_planned_duration_min': plannedDurationMin,
          'p_urgency': urgency.wire,
          'p_transport': transport.wire,
        });
        return quoteFromDetailedJson(j,
            plannedDurationMin: plannedDurationMin, transport: transport);
      });

  @override
  Stream<List<Order>> watchMyClientOrders() => _guardStream(
        () => _client
            .from('orders')
            .stream(primaryKey: ['id'])
            .eq('client_id', _myId)
            .order('created_at', ascending: false)
            .map((rows) => rows
                .map((r) => orderFromRow(r,
                    now: DateTime.now(), clientIsMe: true))
                .toList()),
      );

  @override
  Future<List<Order>> myWorkOrders() => _guard(() async {
        final takers = await _client
            .from('order_takers')
            .select('order_id')
            .eq('porter_id', _myId);
        final ids = takers.map((t) => t['order_id'] as String).toList();
        if (ids.isEmpty) return const <Order>[];
        final rows =
            await _client.from('orders').select().inFilter('id', ids);
        final now = DateTime.now();
        return rows
            .map((r) => orderFromRow(r,
                now: now, clientIsMe: r['client_id'] == _myId))
            .toList();
      });

  @override
  Future<void> cancelOrder({required String orderId, String? reason}) =>
      _guard(() async {
        await _client.from('orders').update({
          'status': 'cancelled',
          'cancelled_at': DateTime.now().toUtc().toIso8601String(),
          if (reason != null) 'comment': reason,
        }).eq('id', orderId).eq('client_id', _myId);
      });

  // ═══════════════════════════════════════════════════════════
  // 9. ДИСПЕТЧЕР (сквозной QA)
  // ═══════════════════════════════════════════════════════════

  @override
  Stream<List<Order>> watchDispatcherOrders() => _guardStream(() {
        final subs = <StreamSubscription<dynamic>>[];
        final ctrl = StreamController<int>(
          onCancel: () {
            for (final s in subs) {
              s.cancel();
            }
          },
        );
        subs.add(_client
            .from('orders')
            .stream(primaryKey: ['id'])
            .listen((_) => ctrl.add(0), onError: ctrl.addError));
        return ctrl.stream.asyncMap((_) => _guard(() async {
              final rows = await _client
                  .from('orders')
                  .select()
                  .inFilter('status', const ['created', 'accepted', 'in_progress'])
                  .order('created_at', ascending: false);
              final now = DateTime.now();
              return rows
                  .map((r) => orderFromRow(r, now: now))
                  .toList();
            }));
      });

  @override
  Future<List<OrderResponse>> getPendingResponses({required String orderId}) =>
      _guard(() async {
        final rows = await _client
            .from('order_responses')
            .select()
            .eq('order_id', orderId)
            .eq('status', 'pending')
            .order('created_at', ascending: true);
        final now = DateTime.now();
        final names = await _profilesById(
            rows.map((r) => r['porter_id'] as String).toList());
        return rows
            .map((r) => responseFromRow(
                  r,
                  now: now,
                  porterName: names[r['porter_id']]?['full_name'] as String?,
                ))
            .toList();
      });

  @override
  Future<void> approveResponse({required String responseId}) =>
      _rpcVoid('approve_response', {'p_response_id': responseId});

  @override
  Future<void> declineResponse({required String responseId}) =>
      _rpcVoid('decline_response', {'p_response_id': responseId});

  @override
  Future<void> assignLead({required String orderId, required String porterId}) =>
      _rpcVoid('assign_lead', {'p_order_id': orderId, 'p_porter_id': porterId});

  @override
  Future<void> forceCloseOrder({required String orderId, required String comment}) =>
      _rpcVoid('force_close_order', {'p_order_id': orderId, 'p_comment': comment});

  @override
  Future<void> findReplacement({required String orderId}) =>
      _rpcVoid('find_replacement', {'p_order_id': orderId});

  @override
  Stream<List<PorterLocation>> watchPorterLocations({required String orderId}) =>
      _guardStream(
        () => _client
            .from('order_locations')
            .stream(primaryKey: ['id'])
            .eq('order_id', orderId)
            .order('created_at', ascending: false)
            .asyncMap((rows) async {
          final profs = await _profilesById(
              rows.map((r) => r['porter_id'] as String).toList());
          return rows
              .map((r) => locationFromRow(r,
                  porterName: profs[r['porter_id']]?['full_name'] as String?))
              .toList();
        }),
      );

  // ═══════════════════════════════════════════════════════════
  // 11. РЕФЕРАЛКА (v2)
  // ═══════════════════════════════════════════════════════════

  @override
  Future<ReferralInfo> getMyReferralInfo() => _guard(() async {
        final me = await _client
            .from('profiles')
            .select('referral_code')
            .eq('id', _myId)
            .maybeSingle();
        final invited = await _client
            .from('profiles')
            .select('full_name, phone')
            .eq('invited_by', _myId);
        return ReferralInfo(
          code: me?['referral_code'] as String?,
          invited: [
            for (final r in invited)
              ReferralEntry(
                name: _str2(r['full_name']),
                phoneMasked: maskPhone(r['phone'] as String?),
                // 🔴 OPEN QUESTION Матвею: таблицы referrals со статусами
                // new/counted/left и кроном засчёта (5 дней) пока нет —
                // всё, что пришло, рисуем как fresh.
                status: ReferralStatus.fresh,
              ),
          ],
        );
      });

  @override
  Future<String> ensureReferralCode() => _guard(() async {
        final code = await _client.rpc('profiles_gen_referral_code');
        return code is String ? code : code.toString();
      });

  static String _str2(Object? v) {
    final s = v?.toString();
    return (s == null || s.isEmpty) ? 'Участник' : s;
  }

  // ═══════════════════════════════════════════════════════════
  // 10. ФОТО ЗАКАЗА (storage bucket 'orders')
  // ═══════════════════════════════════════════════════════════

  @override
  Future<String> uploadOrderPhoto({
    required String orderId,
    required Uint8List bytes,
    required String fileName,
  }) =>
      _guard(() async {
        // Имя файла от пользователя в путь не берём как есть: только безопасные символы.
        final safe = fileName
            .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
            .replaceAll('..', '_');
        final path = '$orderId/${DateTime.now().millisecondsSinceEpoch}_'
            '${safe.isEmpty ? 'photo.jpg' : safe}';
        await _client.storage.from('orders').uploadBinary(
              path,
              bytes,
              fileOptions: const FileOptions(
                contentType: 'image/jpeg',
                upsert: false,
              ),
            );
        return '$attachmentScheme$path';
      });

  // ═══════════════════════════════════════════════════════════
  // 12. ЗАЯВКА НА РАБОТУ ГРУЗЧИКОМ
  // ═══════════════════════════════════════════════════════════

  static WorkerApplication _appFromRow(Map<String, dynamic> r,
          {String? phone}) =>
      WorkerApplication(
        id: r['id'] as String,
        userId: r['user_id'] as String,
        fullName: (r['full_name'] ?? '') as String,
        city: (r['city'] ?? '') as String,
        status: WorkerApplicationStatus.fromWire(r['status'] as String?),
        experience: r['experience'] as String?,
        rejectReason: r['reject_reason'] as String?,
        phone: phone,
        createdAt: DateTime.tryParse('${r['created_at']}')?.toLocal(),
      );

  @override
  Future<WorkerApplication?> myWorkerApplication() => _guard(() async {
        final uid = _client.auth.currentUser?.id;
        if (uid == null) throw Failures.unauthorized();
        final row = await _client
            .from('worker_applications')
            .select()
            .eq('user_id', uid)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
        return row == null ? null : _appFromRow(row);
      });

  @override
  Future<void> submitWorkerApplication({
    required String fullName,
    required String city,
    String? experience,
  }) =>
      _guard(() async {
        await _client.rpc('submit_worker_application', params: {
          'p_full_name': fullName,
          'p_city': city,
          'p_experience': experience,
        });
      });

  @override
  Future<List<WorkerApplication>> pendingWorkerApplications() =>
      _guard(() async {
        final rows = await _client
            .from('worker_applications')
            .select()
            .eq('status', 'pending')
            .order('created_at')
            .limit(100);
        final list = List<Map<String, dynamic>>.from(rows);
        final profiles =
            await _profilesById(list.map((r) => r['user_id'] as String));
        return [
          for (final r in list)
            _appFromRow(r,
                phone: profiles[r['user_id']]?['phone'] as String?),
        ];
      });

  @override
  Future<void> reviewWorkerApplication({
    required String id,
    required bool approve,
    String? reason,
  }) =>
      _guard(() async {
        await _client.rpc('review_worker_application', params: {
          'p_id': id,
          'p_approve': approve,
          'p_reason': reason,
        });
      });

  /// Префикс ссылок на приватные фото заказа в messages.attachment_url.
  static const attachmentScheme = 'storage://orders/';

  /// Путь объекта в бакете 'orders' из ссылки в сообщении, или null.
  /// Понимает и старые публичные ссылки (до миграции 20261119120000).
  static String? attachmentPath(String url) {
    String? path;
    if (url.startsWith(attachmentScheme)) {
      path = url.substring(attachmentScheme.length);
    } else {
      const legacy = '/storage/v1/object/public/orders/';
      final i = url.indexOf(legacy);
      if (i >= 0) path = url.substring(i + legacy.length);
    }
    if (path == null || path.isEmpty || path.contains('..')) return null;
    return path;
  }

  final Map<String, ({String url, DateTime until})> _signed = {};

  @override
  Future<String?> resolveAttachmentUrl(String attachmentUrl) async {
    final path = attachmentPath(attachmentUrl);
    if (path == null) return null;
    final hit = _signed[path];
    if (hit != null && DateTime.now().isBefore(hit.until)) return hit.url;
    try {
      final url =
          await _client.storage.from('orders').createSignedUrl(path, 3600);
      _signed[path] = (
        url: url,
        until: DateTime.now().add(const Duration(minutes: 50)),
      );
      return url;
    } catch (_) {
      return null; // нет доступа (не участник) или файла нет
    }
  }
}

/// Удобство: первая роль профиля для подписи автора в чате.
extension on Set<UserRole> {
  UserRole? get firstOrNullRole => isEmpty ? null : first;
}
