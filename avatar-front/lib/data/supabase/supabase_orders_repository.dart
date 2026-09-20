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
    } on AppFailure {
      rethrow;
    } on FunctionException catch (e) {
      // edge-функции отвечают {ok:false,error:'...'} с 4xx/5xx
      final msg = (e.details is Map ? (e.details as Map)['error'] : e.details)?.toString();
      throw Failures.server(msg ?? e.reasonPhrase);
    } catch (e) {
      throw _err.map(e);
    }
  }

  Stream<T> _guardStream<T>(Stream<T> Function() build) async* {
    try {
      yield* build();
    } on AppFailure {
      rethrow;
    } catch (e) {
      throw _err.map(e);
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
  Future<void> sendSmsCode({required String phone}) => _guard(() async {
        await _invokeJson('send-sms', {'phone': phone});
      });

  @override
  Future<AuthResult> verifySmsCode({required String phone, required String code}) =>
      _guard(() async {
        final data = await _invokeJson('verify-sms', {'phone': phone, 'code': code});
        final tokenHash = data['token_hash'] as String?;
        if (tokenHash == null) throw Failures.unauthorized();
        // gotrue 2.27: verifyOTP + phone обязателен для magiclink с tokenHash.
        await _client.auth.verifyOTP(
          type: OtpType.magiclink,
          phone: phone,
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
        yield* _client.auth.onAuthStateChange
            .asyncMap((state) => load(state.session?.user.id));
      });

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
      _guardStream(() async* {
        final base = _client.from('orders').stream(primaryKey: ['id']);
        Stream<List<Map<String, dynamic>>> orders;
        if (filter.onlyMine) {
          // «Мои»: realtime по бригаде, заказы любых живых статусов.
          orders = _client
              .from('order_takers')
              .stream(primaryKey: ['order_id', 'porter_id'])
              .eq('porter_id', _myId)
              .asyncMap((takers) async {
            final ids = takers.map((t) => t['order_id'] as String).toList();
            if (ids.isEmpty) return <Map<String, dynamic>>[];
            final rows = await _client.from('orders').select().inFilter('id', ids);
            return rows.cast<Map<String, dynamic>>();
          });
        } else {
          var q = base.inFilter('status', const ['created']);
          if (filter.urgencies != null && filter.urgencies!.isNotEmpty) {
            q = q.inFilter('urgency',
                filter.urgencies!.map((u) => u.wire).toSet().toList());
          }
          if (filter.dateFrom != null) {
            q = q.gte('scheduled_at', nskToWireUtc(filter.dateFrom!));
          }
          if (filter.dateTo != null) {
            q = q.lte('scheduled_at', nskToWireUtc(filter.dateTo!));
          }
          orders = q.order('scheduled_at', ascending: true);
        }

        final filtered = filter != FeedFilter.all;
        await for (final rows in orders) {
          var items = rows;
          if (filter.onlyMine) {
            items = items
                .where((r) => OrderStatus.fromWire(r['status'] as String? ?? '')
                    .isLive)
                .toList();
          }
          final myResponses = await _myResponsesFor(
              items.map((r) => r['id'] as String).toList());
          final now = DateTime.now();
          final page = FeedPage(
            items: items
                .map((r) => orderFromRow(
                      r,
                      myResponseStatus: myResponses[r['id']],
                      now: now,
                    ))
                .take(limit)
                .toList(),
            emptyReason: await _feedEmptyReason(items.isEmpty, filtered),
          );
          yield page;
        }
      });

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
            myResponseStatus: my[orderId], now: DateTime.now());
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
  Future<void> sendOrderChatMessage({required String orderId, required String text}) =>
      _guard(() async {
        await _client.from('messages').insert({
          'order_id': orderId,
          'author_id': _myId,
          'text': text,
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
        return orderFromRow(row, now: DateTime.now());
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
        final raw = await _client.rpc('quote_order', params: {
          'p_people_count': peopleCount,
          'p_planned_duration_min': plannedDurationMin,
          'p_urgency': urgency.wire,
          'p_transport': transport.wire,
        });
        final price = raw is num ? raw : num.tryParse(raw.toString()) ?? 0;
        return quoteFromPrice(price,
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
                    now: DateTime.now()))
                .toList()),
      );

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
  Future<List<OrderResponse>> getPendingResponses({required String orderId}) =>
      _guard(() async {
        final rows = await _client
            .from('order_responses')
            .select()
            .eq('order_id', orderId)
            .eq('status', 'pending')
            .order('created_at', ascending: true);
        final now = DateTime.now();
        return rows
            .map((r) => responseFromRow(r, now: now))
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
  // 10. ФОТО ЗАКАЗА (storage bucket 'orders')
  // ═══════════════════════════════════════════════════════════

  @override
  Future<String> uploadOrderPhoto({
    required String orderId,
    required Uint8List bytes,
    required String fileName,
  }) =>
      _guard(() async {
        final path = '$orderId/${DateTime.now().millisecondsSinceEpoch}_$fileName';
        await _client.storage.from('orders').uploadBinary(
              path,
              bytes,
              fileOptions: const FileOptions(
                contentType: 'image/jpeg',
                upsert: false,
              ),
            );
        return _client.storage.from('orders').getPublicUrl(path);
      });
}

/// Удобство: первая роль профиля для подписи автора в чате.
extension on Set<UserRole> {
  UserRole? get firstOrNullRole => isEmpty ? null : first;
}
