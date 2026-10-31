-- =====================================================================
-- ПРОД qkcxfnfyjdesmaotsmya — ДИАГНОСТИКА RPC/ТРИГГЕРОВ (31.10.2026)
-- Запускать: Dashboard → SQL Editor (под ролью postgres).
-- Зачем: снаружи через publishable-ключ из 35 функций public видны только 6,
--        остальные PostgREST отдаёт как PGRST202 «function not found».
--        Клиент после логина работает под ролью `authenticated` — её и меряем.
-- =====================================================================

-- ---------- ШАГ 1. ЧЕГО НЕ ХВАТАЕТ (главный список) ----------
with need(f) as (values
  -- эти 14 зовёт avatar-front/lib/data/supabase/supabase_orders_repository.dart
  ('respond_to_order'),('get_pending_review_count'),('profiles_gen_referral_code'),
  ('quote_order_detailed'),('get_stage_availability'),('mark_stage'),
  ('submit_delay_reason'),('approve_response'),('decline_response'),
  ('cancel_response'),('assign_lead'),('find_replacement'),('force_close_order'),
  ('submit_review'),
  -- служебные/крон (их тоже пересоздаём, чтобы не искать по одному)
  ('finish_order'),('accept_order'),('advance_order_status'),('quote_order'),
  ('get_order_safe'),('switch_role'),('add_role'),('register_device_token'),
  ('update_porter_location'),('orders_status_timestamps'),('check_order_filled'),
  ('reviews_recalc_rating'),('set_review_editable_until'),('set_updated_at'),
  ('add_taker_on_approve'),
  -- триггер на auth.users: без него ЛОГИН ПАДАЕТ (createUser → 500)
  ('handle_new_user')
)
select n.f                                                     as funkcija,
       (select string_agg(p.proname || '(' ||
               pg_get_function_identity_arguments(p.oid) || ')', ', ')
          from pg_proc p
          join pg_namespace ns on ns.oid = p.pronamespace
         where ns.nspname = 'public' and p.proname = n.f)       v_baze,
       exists (select 1
                 from pg_proc p
                 join pg_namespace ns on ns.oid = p.pronamespace
                where ns.nspname = 'public'
                  and p.proname = n.f
                  and has_function_privilege('authenticated', p.oid, 'EXECUTE'))
                                                                dostupna_authenticated
from need n
order by dostupna_authenticated, n.f;
-- Норма после фикса: v_baze непусто и dostupna_authenticated = t у ВСЕХ строк.

-- ---------- ШАГ 2. ТРИГГЕРЫ (9 штук по миграциям) ----------
select event_object_schema || '.' || event_object_table as na_tablice,
       trigger_name, action_timing, event_manipulation,
       action_statement
from information_schema.triggers
order by 1, 2;
-- Ожидаем: on_auth_user_created (auth.users), trg_profiles_updated,
-- trg_orders_updated, trg_orders_status, trg_reviews_recalc,
-- trg_profiles_referral_code, trg_check_order_filled,
-- trg_add_taker_on_approve, trg_reviews_editable_until.

-- ---------- ШАГ 3. REALTIME-публикация (лента/этапы/чат) ----------
select tablename
from pg_publication_tables
where pubname = 'supabase_realtime'
order by 1;
-- Ожидаем как минимум: orders, order_responses, order_stages, order_takers,
-- messages, profiles, reviews.

-- ---------- ШАГ 4. ПРОФИЛИ (пусто = никто ещё не логинился) ----------
select count(*) as profiles, count(*) filter (where role = 'porter') as porters
from public.profiles;

-- ---------- ШАГ 5. КРОН (дедлайны, авто-отклонение, чистка sms-кодов) ----------
select jobid, jobname, schedule, command, active
from cron.job
order by jobid;

-- ---------- ШАГ 6. СЕКРЕТЫ EDGE-ФУНКЦИЙ (только имена, значения не печатаем) ----------
-- Dashboard → Edge Functions → Secrets: должны быть
--   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SMSRU_API_KEY.
-- Проверка, что функции отвечают (можно с ноутбука, publishable-ключом):
--   POST {URL}/functions/v1/send-sms      {"phone":"123"}      → 400 Invalid phone format  (значит жива)
--   POST {URL}/functions/v1/verify-sms    {"phone":"+79000000000","code":"000000"} → 400 Code not found
--   POST {URL}/functions/v1/search-address {"query":"Новосибирск"} → 200 + results
-- Агент эти три проверил 31.10: все живы ✅ (search-address отдаёт Nominatim/OSM).
