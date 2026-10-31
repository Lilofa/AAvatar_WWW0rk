-- =====================================================================
-- ПРОД qkcxfnfyjdesmaotsmya — ПОЧИНКА RPC/ГРАНТОВ (31.10.2026)
-- Порядок: сначала 01_prod_rpc_diag.sql (снимок «до»), потом этот файл,
-- потом ещё раз 01_ (снимок «после»).
-- =====================================================================

-- ---------- ШАГ A. ПЕРЕСОЗДАТЬ ФУНКЦИИ (идемпотентно) ----------
-- Всё ниже — CREATE OR REPLACE, данные не трогаются.
-- Надёжнее всего: накатить миграции целиком ещё раз
--   supabase link --project-ref qkcxfnfyjdesmaotsmya
--   supabase db push
-- и ПРИЛОЖИТЬ СЮДА В ЧАТ ТЕКСТ ОШИБКИ, если push упадёт (это и есть причина,
-- почему половины функций нет: миграция встала не до конца).
-- Если CLI недоступен — в SQL Editor по порядку:
--   20260910120100_auth_trigger.sql        (handle_new_user + ТРИГГЕР на auth.users)
--   20260910120300_triggers.sql            (trg_profiles_updated, trg_orders_updated,
--                                           trg_orders_status, trg_reviews_recalc,
--                                           trg_profiles_referral_code)
--   20260910120400_sms_codes.sql           (accept_order, advance_order_status)
--   20260912120200_rpc_contract.sql        (switch_role, add_role, quote_order,
--                                           get_stage_availability, mark_stage,
--                                           submit_delay_reason, get_pending_review_count,
--                                           update_porter_location, assign_lead,
--                                           find_replacement, force_close_order,
--                                           register_device_token)
--   20260912120300_triggers_contract.sql   (check_order_filled, add_taker_on_approve,
--                                           set_review_editable_until, get_order_safe + 3 триггера)
--   20260912130000_cron_and_missing_rpc.sql(finish_order, submit_review, крон)
--   20260913120000_fix_stages_and_takers.sql
--   20260913130000_fix_time_start_column.sql
--   20260913140000_add_people_count.sql
--   20260917120000_responses_rpc.sql       (respond_to_order, approve_response,
--                                           decline_response, cancel_response)
--   20260917120100_orders_form_fields.sql
--   20260918130000_submit_review_nullable.sql
--   20260920120000_fixes_for_artem.sql     (quote_order_detailed и пр.)
--   20260930120000_messages_attachment.sql
-- Дубли 20260915*≡20260917* идемпотентны (OR REPLACE) — можно гнать оба.

-- ---------- ШАГ B. ГРАНТЫ (главная подозреваемая причина) ----------
-- PostgREST не показывает функцию роли, у которой нет EXECUTE → клиент получает
-- PGRST202, как будто функции нет. Миграции дают грант только `authenticated`,
-- а часть функций ещё и REVOKE FROM PUBLIC — отсюда 6 видимых из 35.
do $$
declare r record;
begin
  for r in
    select p.oid, p.proname
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind = 'f'                      -- триггерные (prokind='t') не трогаем
  loop
    execute format('grant execute on function %s to authenticated',
                   r.oid::regprocedure);
  end loop;
end $$;

-- ---------- ШАГ C. ПЕРЕЗАГРУЗИТЬ КЭШ СХЕМЫ POSTGREST ----------
notify pgrst, 'reload schema';
-- Без этого новые/перегрантованные функции могут оставаться невидимыми
-- до рестарта PostgREST (Dashboard → Settings → restart API тоже годится).

-- ---------- ШАГ D. КОНТРОЛЬ ----------
-- Ещё раз 01_prod_rpc_diag.sql, ШАГ 1: у всех 30 строк
-- v_baze непусто И dostupna_authenticated = t.
select count(*) as func_v_public
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public';

-- ---------- ШАГ E. ТРИГГЕР НА auth.users (критично для логина) ----------
-- Если в ШАГЕ 2 диагностики on_auth_user_created отсутствует — пересоздать:
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
