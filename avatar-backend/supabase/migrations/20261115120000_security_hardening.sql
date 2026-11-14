-- =============================================================================
-- SECURITY HARDENING (аудит 15.11.2026)
--
-- Закрывает находки аудита:
--  C1  Любой пользователь мог зарегистрироваться как admin/dispatcher
--      (verify-sms клал role из тела запроса в user_metadata, а handle_new_user
--      слепо кастовал её в user_role).
--  C2  add_role('admin') + switch_role('admin') = самоповышение до админа.
--  C3  RLS не был включён на 7 таблицах (order_responses, order_takers,
--      order_stages, messages, order_locations, device_tokens, sms_codes), а
--      роли anon/authenticated имели GRANT ALL => публичный publishable-ключ
--      читал sms_codes (коды входа) и писал в чужие таблицы.
--  C4  profiles: пользователь мог сам менять balance/rating/roles/pool/phone.
--  C5  orders: клиент/грузчик могли напрямую менять price/status/porter_id.
--  H1  Прямые INSERT в order_takers/order_stages/order_responses/reviews
--      обходили бизнес-RPC (самозачисление в бригаду, накрутка рейтинга).
--  H2  anon мог вызывать любые функции public.*; служебные функции
--      (крон, триггерные) были доступны authenticated.
--  H3  profiles читались всеми (телефоны, баланс) — сузили до «своих».
--  M1  storage 'orders': листинг всех фото заказов любым пользователем.
--
-- ВАЖНО: накатывать СНАЧАЛА на staging и прогнать сквозной тест (R6).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. RLS на ВСЕХ таблицах (C3)
-- ---------------------------------------------------------------------------
ALTER TABLE public.profiles        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_responses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_takers    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_stages    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reviews         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.device_tokens   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log       ENABLE ROW LEVEL SECURITY;
-- sms_codes: RLS включён и политик НЕТ => доступ только у service_role.
ALTER TABLE public.sms_codes       ENABLE ROW LEVEL SECURITY;

-- Журнал отправок SMS для rate-limit (пишет/читает только edge-функция).
CREATE TABLE IF NOT EXISTS public.sms_sends (
  id         bigserial PRIMARY KEY,
  phone      text        NOT NULL,
  ip         text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sms_sends_phone ON public.sms_sends(phone, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sms_sends_ip    ON public.sms_sends(ip, created_at DESC);
ALTER TABLE public.sms_sends ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- 2. Права ролей: least privilege (C3, H2)
-- ---------------------------------------------------------------------------
-- anon (публичный ключ в APK) в public не нужен вообще: вход идёт через
-- edge-функции, всё остальное — после логина под authenticated.
REVOKE ALL ON ALL TABLES    IN SCHEMA public FROM anon;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM anon, PUBLIC;

ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES    FROM anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON FUNCTIONS FROM anon, PUBLIC;

-- authenticated: без TRUNCATE/REFERENCES/TRIGGER, а служебные таблицы закрыты.
REVOKE TRUNCATE, REFERENCES, TRIGGER ON ALL TABLES IN SCHEMA public FROM authenticated;
REVOKE ALL ON public.sms_codes, public.sms_sends FROM authenticated;
REVOKE ALL ON public.audit_log FROM authenticated;
GRANT SELECT ON public.audit_log TO authenticated;       -- читает admin по RLS

-- Служебные/триггерные/кроновые функции не должны вызываться клиентом по RPC.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        'cleanup_expired_sms_codes', 'auto_decline_stale_responses',
        'process_order_deadlines', 'hide_entrance_before_started',
        'handle_new_user', 'reviews_recalc_rating', 'check_order_filled',
        'add_taker_on_approve', 'set_updated_at', 'set_review_editable_until',
        'profiles_gen_referral_code', 'orders_status_timestamps'
      )
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', r.sig);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- 3. Регистрация: роль только client/porter (C1)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text := lower(COALESCE(NEW.raw_user_meta_data->>'role', ''));
  v_inv  uuid;
BEGIN
  -- user_metadata контролирует клиент => доверять можно только безопасным ролям.
  -- dispatcher/admin выдаёт только администратор через service_role.
  IF v_role NOT IN ('client', 'porter') THEN
    v_role := 'client';
  END IF;

  BEGIN
    v_inv := NULLIF(NEW.raw_user_meta_data->>'invited_by', '')::uuid;
  EXCEPTION WHEN others THEN
    v_inv := NULL;
  END;
  IF v_inv IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_inv) THEN
    v_inv := NULL;
  END IF;

  INSERT INTO public.profiles (id, phone, role, full_name, invited_by)
  VALUES (
    NEW.id,
    COALESCE(NEW.phone, NEW.email, ''),
    v_role::public.user_role,
    left(NEW.raw_user_meta_data->>'full_name', 120),
    v_inv
  );
  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Самоповышение через add_role / switch_role (C2)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.add_role(p_role text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: not authenticated' USING ERRCODE = '42501';
  END IF;
  -- Самому себе можно добавить только «пользовательские» роли.
  IF p_role IS NULL OR p_role NOT IN ('client', 'porter') THEN
    RAISE EXCEPTION 'ROLE_NOT_ALLOWED: role % cannot be self-assigned', p_role
      USING ERRCODE = '42501';
  END IF;

  UPDATE public.profiles
  SET roles = array_append(roles, p_role)
  WHERE id = auth.uid()
    AND NOT (p_role = ANY(roles));
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Защита чувствительных колонок от прямых UPDATE (C4, C5)
--    Срабатывает ТОЛЬКО для прямых запросов клиента (current_user = authenticated).
--    SECURITY DEFINER RPC выполняются от владельца и не затрагиваются.
--    Имена a_* — чтобы сработать раньше остальных BEFORE-триггеров.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.guard_profile_update()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF current_user IN ('authenticated', 'anon') THEN
    IF NEW.id              IS DISTINCT FROM OLD.id
       OR NEW.phone        IS DISTINCT FROM OLD.phone
       OR NEW.role         IS DISTINCT FROM OLD.role
       OR NEW.roles        IS DISTINCT FROM OLD.roles
       OR NEW.active_role  IS DISTINCT FROM OLD.active_role
       OR NEW.pool         IS DISTINCT FROM OLD.pool
       OR NEW.rating       IS DISTINCT FROM OLD.rating
       OR NEW.reviews_count   IS DISTINCT FROM OLD.reviews_count
       OR NEW.completed_count IS DISTINCT FROM OLD.completed_count
       OR NEW.balance      IS DISTINCT FROM OLD.balance
       OR NEW.referral_code IS DISTINCT FROM OLD.referral_code
       OR NEW.invited_by   IS DISTINCT FROM OLD.invited_by
       OR NEW.is_blocked   IS DISTINCT FROM OLD.is_blocked
       OR NEW.created_at   IS DISTINCT FROM OLD.created_at
    THEN
      RAISE EXCEPTION 'PERMISSION_DENIED: protected profile field' USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS a_guard_profile_update ON public.profiles;
CREATE TRIGGER a_guard_profile_update
BEFORE UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.guard_profile_update();

CREATE OR REPLACE FUNCTION public.guard_order_update()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_free text[] := ARRAY['status', 'cancelled_at', 'comment', 'updated_at'];
  v_new jsonb;
  v_old jsonb;
  k text;
BEGIN
  IF current_user IN ('authenticated', 'anon')
     AND public.current_user_role() NOT IN ('dispatcher', 'admin') THEN
    v_new := to_jsonb(NEW);
    v_old := to_jsonb(OLD);
    FOREACH k IN ARRAY v_free LOOP
      v_new := v_new - k;
      v_old := v_old - k;
    END LOOP;
    IF v_new IS DISTINCT FROM v_old THEN
      RAISE EXCEPTION 'PERMISSION_DENIED: protected order field' USING ERRCODE = '42501';
    END IF;

    -- Единственный разрешённый прямой переход статуса — отмена заказчиком.
    IF NEW.status::text IS DISTINCT FROM OLD.status::text THEN
      IF NOT (
        NEW.status::text = 'cancelled'
        AND OLD.client_id = auth.uid()
        AND OLD.status::text IN ('created', 'accepted')
      ) THEN
        RAISE EXCEPTION 'PERMISSION_DENIED: use RPC for status change' USING ERRCODE = '42501';
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS a_guard_order_update ON public.orders;
CREATE TRIGGER a_guard_order_update
BEFORE UPDATE ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.guard_order_update();

-- profiles_update_own сверялся с собственной строкой подзапросом по profiles; вместе
-- с новой SELECT-политикой это даёт «infinite recursion in policy». Защиту role /
-- is_blocked теперь обеспечивает триггер guard_profile_update, поэтому политика проще.
DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;
CREATE POLICY "profiles_update_own"
ON public.profiles FOR UPDATE TO authenticated
USING (auth.uid() = id)
WITH CHECK (auth.uid() = id);

-- ---------------------------------------------------------------------------
-- 6. Политики: убрать прямые записи в обход RPC (H1)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "profiles_insert_self"       ON public.profiles;   -- профиль создаёт триггер
DROP POLICY IF EXISTS "orders_accept_porter"       ON public.orders;     -- есть RPC accept_order
DROP POLICY IF EXISTS "orders_update_own_porter"   ON public.orders;
DROP POLICY IF EXISTS "responses_insert_porter"    ON public.order_responses;  -- RPC respond_to_order
DROP POLICY IF EXISTS "takers_insert_system"       ON public.order_takers;     -- только триггер одобрения
DROP POLICY IF EXISTS "stages_insert_own"          ON public.order_stages;     -- только RPC mark_stage
DROP POLICY IF EXISTS "reviews_insert_client"      ON public.reviews;          -- только RPC submit_review

-- Геотрек: писать можно только по своему заказу, где я в бригаде.
DROP POLICY IF EXISTS "locations_insert_own" ON public.order_locations;
CREATE POLICY "locations_insert_own"
ON public.order_locations FOR INSERT TO authenticated
WITH CHECK (
  auth.uid() = porter_id
  AND EXISTS (
    SELECT 1 FROM public.order_takers t
    WHERE t.order_id = order_locations.order_id AND t.porter_id = auth.uid()
  )
);

-- Сообщения: заказчик тоже участник чата своего заказа.
DROP POLICY IF EXISTS "messages_select_participants" ON public.messages;
CREATE POLICY "messages_select_participants"
ON public.messages FOR SELECT TO authenticated
USING (
  EXISTS (SELECT 1 FROM public.order_takers t WHERE t.order_id = messages.order_id AND t.porter_id = auth.uid())
  OR EXISTS (SELECT 1 FROM public.orders o WHERE o.id = messages.order_id AND o.client_id = auth.uid())
  OR public.current_user_role() IN ('dispatcher', 'admin')
);

DROP POLICY IF EXISTS "messages_insert_participants" ON public.messages;
CREATE POLICY "messages_insert_participants"
ON public.messages FOR INSERT TO authenticated
WITH CHECK (
  auth.uid() = author_id
  AND (
    EXISTS (SELECT 1 FROM public.order_takers t WHERE t.order_id = messages.order_id AND t.porter_id = auth.uid())
    OR EXISTS (SELECT 1 FROM public.orders o WHERE o.id = messages.order_id AND o.client_id = auth.uid())
    OR public.current_user_role() IN ('dispatcher', 'admin')
  )
);

-- ---------------------------------------------------------------------------
-- 7. Видимость профилей: не всем подряд (H3)
--    Свой, персонал, мои приглашённые, участники общих заказов.
-- ---------------------------------------------------------------------------
-- Логика — в SECURITY DEFINER-функции: она читает таблицы в обход их RLS, поэтому
-- видимость профиля не зависит от того, что RLS скрывает заказы/бригаду, и не
-- даёт рекурсии политик.
CREATE OR REPLACE FUNCTION public.can_view_profile(p_target uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT auth.uid() IS NOT NULL AND (
    p_target = auth.uid()
    OR EXISTS (SELECT 1 FROM public.profiles me WHERE me.id = auth.uid() AND me.role IN ('dispatcher', 'admin'))
    OR EXISTS (SELECT 1 FROM public.profiles t  WHERE t.id = p_target
                 AND (t.role IN ('dispatcher', 'admin') OR t.invited_by = auth.uid()))
    -- коллеги по бригаде
    OR EXISTS (SELECT 1 FROM public.order_takers t
               JOIN public.order_takers me ON me.order_id = t.order_id AND me.porter_id = auth.uid()
               WHERE t.porter_id = p_target)
    -- грузчики моих заказов (я заказчик)
    OR EXISTS (SELECT 1 FROM public.order_takers t
               JOIN public.orders o ON o.id = t.order_id
               WHERE o.client_id = auth.uid() AND t.porter_id = p_target)
    -- заказчик заказа, где я в бригаде
    OR EXISTS (SELECT 1 FROM public.order_takers t
               JOIN public.orders o ON o.id = t.order_id
               WHERE t.porter_id = auth.uid() AND o.client_id = p_target)
    -- откликнувшиеся на мои заказы
    OR EXISTS (SELECT 1 FROM public.order_responses r
               JOIN public.orders o ON o.id = r.order_id
               WHERE o.client_id = auth.uid() AND r.porter_id = p_target)
  );
$$;
REVOKE ALL ON FUNCTION public.can_view_profile(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_view_profile(uuid) TO authenticated;

DROP POLICY IF EXISTS "profiles_select_authenticated" ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_scoped"        ON public.profiles;
CREATE POLICY "profiles_select_scoped"
ON public.profiles FOR SELECT TO authenticated
USING (public.can_view_profile(id));

-- ---------------------------------------------------------------------------
-- 8. Storage (M1)
-- ---------------------------------------------------------------------------
-- Бакет остаётся public (прямые ссылки по неугадываемому пути работают),
-- но ЛИСТИНГ/SELECT через API — только участникам заказа.
DROP POLICY IF EXISTS "orders_public_read" ON storage.objects;
DROP POLICY IF EXISTS "orders_read_participants" ON storage.objects;
CREATE POLICY "orders_read_participants"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'orders'
  AND (
    EXISTS (SELECT 1 FROM public.orders o
            WHERE o.id::text = (storage.foldername(name))[1] AND o.client_id = auth.uid())
    OR EXISTS (SELECT 1 FROM public.order_takers t
               WHERE t.order_id::text = (storage.foldername(name))[1] AND t.porter_id = auth.uid())
    OR public.current_user_role() IN ('dispatcher', 'admin')
  )
);

-- avatars_update_own без WITH CHECK позволял «переселить» файл в чужую папку.
DROP POLICY IF EXISTS "avatars_update_own" ON storage.objects;
CREATE POLICY "avatars_update_own"
ON storage.objects FOR UPDATE TO authenticated
USING (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text)
WITH CHECK (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);
