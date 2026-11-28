-- Задача от Артёма (26.11.2026): регистрация ТОЛЬКО как заказчик. Стать грузчиком
-- можно лишь подав заявку в личном кабинете; одобряет диспетчер/админ.
--
-- 1. Регистрация: роль из user_metadata больше не читаем — всегда client.
-- 2. add_role: самому себе можно добавить только client (porter — через заявку).
-- 3. has_role(): человек может быть одновременно заказчиком и грузчиком. Раньше
--    сервер смотрел только на «активную» роль (profiles.role), и у двойной роли
--    пропадали бы либо свои заказы, либо действия грузчика. Политики и функции,
--    где проверялось current_user_role() = 'client' / 'porter', переведены на has_role().
-- 4. worker_applications + RPC submit_worker_application / review_worker_application.

-- ---------------------------------------------------------------------------
-- 3. has_role
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.has_role(p_role text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid()
      AND NOT is_blocked
      AND (role::text = p_role OR p_role = ANY(roles))
  );
$$;
REVOKE ALL ON FUNCTION public.has_role(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_role(text) TO authenticated;

DROP POLICY IF EXISTS "orders_select_client" ON public.orders;
CREATE POLICY "orders_select_client" ON public.orders FOR SELECT TO authenticated
USING (public.has_role('client') AND client_id = auth.uid());

DROP POLICY IF EXISTS "orders_select_porter" ON public.orders;
CREATE POLICY "orders_select_porter" ON public.orders FOR SELECT TO authenticated
USING (public.has_role('porter') AND (porter_id = auth.uid() OR status = 'created'));

DROP POLICY IF EXISTS "orders_insert_client" ON public.orders;
CREATE POLICY "orders_insert_client" ON public.orders FOR INSERT TO authenticated
WITH CHECK (public.has_role('client') AND client_id = auth.uid()
            AND status = 'created' AND porter_id IS NULL);

DROP POLICY IF EXISTS "orders_cancel_own_client" ON public.orders;
CREATE POLICY "orders_cancel_own_client" ON public.orders FOR UPDATE TO authenticated
USING (public.has_role('client') AND client_id = auth.uid() AND status IN ('created', 'accepted'))
WITH CHECK (client_id = auth.uid());

CREATE OR REPLACE FUNCTION public.accept_order(p_order_id uuid)
 RETURNS orders
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_order public.orders;
BEGIN
  IF NOT public.has_role('porter') THEN
    RAISE EXCEPTION 'Only porters can accept orders';
  END IF;

  UPDATE public.orders
  SET porter_id = auth.uid(),
      status    = 'accepted'
  WHERE id = p_order_id
    AND status = 'created'
    AND porter_id IS NULL
  RETURNING * INTO v_order;

  IF v_order.id IS NULL THEN
    RAISE EXCEPTION 'Order already taken or not available';
  END IF;

  INSERT INTO public.order_takers (order_id, porter_id, is_lead)
  VALUES (p_order_id, auth.uid(), false)
  ON CONFLICT (order_id, porter_id) DO NOTHING;

  RETURN v_order;
END;
$function$;

CREATE OR REPLACE FUNCTION public.respond_to_order(p_order_id uuid, p_eta_minutes integer DEFAULT NULL::integer)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_order public.orders;
  v_response_id uuid;
  v_user_id uuid := auth.uid();
BEGIN
  IF NOT public.has_role('porter') THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: only porters';
  END IF;
  IF p_eta_minutes IS NULL OR p_eta_minutes NOT BETWEEN 1 AND 240 THEN
    RAISE EXCEPTION 'VALIDATION_FAILED: eta must be 1..240 minutes';
  END IF;

  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id;
  IF v_order.id IS NULL THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND';
  END IF;
  IF v_order.status <> 'created' THEN
    RAISE EXCEPTION 'ORDER_ALREADY_TAKEN: order is %', v_order.status;
  END IF;
  IF v_order.client_id = v_user_id THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: cannot respond to own order';
  END IF;

  INSERT INTO public.order_responses (order_id, porter_id, eta_minutes, status)
  VALUES (p_order_id, v_user_id, p_eta_minutes, 'pending')
  ON CONFLICT (order_id, porter_id) DO UPDATE
    SET eta_minutes = EXCLUDED.eta_minutes,
        status = 'pending'
  RETURNING id INTO v_response_id;

  RETURN v_response_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.advance_order_status(p_order_id uuid, p_new_status order_status)
 RETURNS orders
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_order public.orders;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF v_order.id IS NULL THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  -- Один человек может быть и заказчиком, и грузчиком: пускаем, если он
  -- участвует в ЭТОМ заказе в одной из своих ролей (или это персонал).
  IF NOT (
       public.current_user_role() IN ('dispatcher', 'admin')
    OR (public.has_role('porter') AND v_order.porter_id = auth.uid())
    OR (public.has_role('client') AND v_order.client_id = auth.uid())
  ) THEN
    RAISE EXCEPTION 'Not your order';
  END IF;

  IF NOT (
    (v_order.status = 'created'     AND p_new_status IN ('cancelled')) OR
    (v_order.status = 'accepted'    AND p_new_status IN ('in_progress', 'cancelled')) OR
    (v_order.status = 'in_progress' AND p_new_status IN ('completed', 'cancelled'))
  ) THEN
    RAISE EXCEPTION 'Invalid transition from % to %', v_order.status, p_new_status;
  END IF;

  UPDATE public.orders SET status = p_new_status WHERE id = p_order_id RETURNING * INTO v_order;
  RETURN v_order;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_order_safe(p_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_order public.orders;
  v_user_id uuid := auth.uid();
  v_role public.user_role;
  v_can_see_entrance boolean := false;
  v_result jsonb;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id;
  IF v_order.id IS NULL THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND';
  END IF;

  v_role := public.current_user_role();

  -- Заказчик видит свой заказ всегда
  IF public.has_role('client') AND v_order.client_id = v_user_id THEN
    v_can_see_entrance := true;
  END IF;

  -- Диспетчер/админ видят всегда
  IF v_role IN ('dispatcher', 'admin') THEN
    v_can_see_entrance := true;
  END IF;

  -- Грузчик видит, если он старший и статус started/in_progress/completed
  IF public.has_role('porter') THEN
    IF EXISTS (
      SELECT 1 FROM public.order_takers
      WHERE order_id = p_order_id AND porter_id = v_user_id AND is_lead = true
    ) AND v_order.status IN ('in_progress', 'completed') THEN
      v_can_see_entrance := true;
    END IF;
  END IF;

  v_result := to_jsonb(v_order);
  IF NOT v_can_see_entrance THEN
    v_result := v_result - 'entrance';
  END IF;

  RETURN v_result;
END;
$function$;

-- ---------------------------------------------------------------------------
-- 1. Регистрация всегда как заказчик
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inv uuid;
BEGIN
  BEGIN
    v_inv := NULLIF(NEW.raw_user_meta_data->>'invited_by', '')::uuid;
  EXCEPTION WHEN others THEN
    v_inv := NULL;
  END;
  IF v_inv IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_inv) THEN
    v_inv := NULL;
  END IF;

  INSERT INTO public.profiles (id, phone, role, roles, full_name, invited_by)
  VALUES (
    NEW.id,
    COALESCE(NEW.phone, NEW.email, ''),
    'client',
    ARRAY['client'],
    left(NEW.raw_user_meta_data->>'full_name', 120),
    v_inv
  );
  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. add_role: только client
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
  IF p_role IS DISTINCT FROM 'client' THEN
    RAISE EXCEPTION 'ROLE_NOT_ALLOWED: porter only via worker application, staff only via admin'
      USING ERRCODE = '42501';
  END IF;
  UPDATE public.profiles
  SET roles = array_append(roles, p_role)
  WHERE id = auth.uid() AND NOT (p_role = ANY(roles));
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Заявки на работу грузчиком
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.worker_applications (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  full_name     text NOT NULL CHECK (length(btrim(full_name)) BETWEEN 2 AND 120),
  city          text NOT NULL CHECK (length(btrim(city)) BETWEEN 2 AND 60),
  experience    text CHECK (experience IS NULL OR length(experience) <= 1000),
  status        text NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending', 'approved', 'rejected')),
  reject_reason text CHECK (reject_reason IS NULL OR length(reject_reason) <= 500),
  reviewed_by   uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  reviewed_at   timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_worker_app_one_pending
  ON public.worker_applications(user_id) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_worker_app_status
  ON public.worker_applications(status, created_at DESC);

ALTER TABLE public.worker_applications ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.worker_applications FROM anon, authenticated;
GRANT SELECT ON public.worker_applications TO authenticated;

DROP POLICY IF EXISTS "worker_app_select" ON public.worker_applications;
CREATE POLICY "worker_app_select" ON public.worker_applications FOR SELECT TO authenticated
USING (user_id = auth.uid() OR public.current_user_role() IN ('dispatcher', 'admin'));
-- Записи — только через RPC ниже.

CREATE OR REPLACE FUNCTION public.submit_worker_application(
  p_full_name text, p_city text, p_experience text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role('client') THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: not authenticated' USING ERRCODE = '42501';
  END IF;
  IF public.has_role('porter') THEN
    RAISE EXCEPTION 'VALIDATION_FAILED: Вы уже работаете грузчиком.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.worker_applications
             WHERE user_id = auth.uid() AND status = 'pending') THEN
    RAISE EXCEPTION 'VALIDATION_FAILED: Заявка уже на рассмотрении.';
  END IF;
  IF (SELECT count(*) FROM public.worker_applications
      WHERE user_id = auth.uid() AND created_at > now() - interval '30 days') >= 3 THEN
    RAISE EXCEPTION 'RATE_LIMITED: не больше 3 заявок за 30 дней';
  END IF;
  IF length(btrim(coalesce(p_full_name, ''))) < 2 THEN
    RAISE EXCEPTION 'VALIDATION_FAILED: Укажите имя и фамилию.';
  END IF;
  IF length(btrim(coalesce(p_city, ''))) < 2 THEN
    RAISE EXCEPTION 'VALIDATION_FAILED: Укажите город.';
  END IF;

  INSERT INTO public.worker_applications (user_id, full_name, city, experience)
  VALUES (auth.uid(), btrim(p_full_name), btrim(p_city),
          NULLIF(btrim(coalesce(p_experience, '')), ''))
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.submit_worker_application(text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_worker_application(text, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.review_worker_application(
  p_id uuid, p_approve boolean, p_reason text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_app public.worker_applications;
BEGIN
  IF public.current_user_role() IS NULL
     OR public.current_user_role() NOT IN ('dispatcher', 'admin') THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: dispatcher or admin only' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_app FROM public.worker_applications WHERE id = p_id FOR UPDATE;
  IF v_app.id IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_FAILED: Заявка не найдена.';
  END IF;
  IF v_app.status <> 'pending' THEN
    RAISE EXCEPTION 'VALIDATION_FAILED: Заявка уже рассмотрена.';
  END IF;

  UPDATE public.worker_applications
  SET status = CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END,
      reject_reason = CASE WHEN p_approve THEN NULL ELSE left(NULLIF(btrim(p_reason), ''), 500) END,
      reviewed_by = auth.uid(),
      reviewed_at = now()
  WHERE id = p_id;

  IF p_approve THEN
    UPDATE public.profiles
    SET roles = ARRAY(SELECT DISTINCT r FROM unnest(
                  coalesce(roles, '{}') || ARRAY[role::text, 'porter']) AS r),
        full_name = coalesce(NULLIF(full_name, ''), v_app.full_name),
        city = coalesce(NULLIF(city, ''), v_app.city)
    WHERE id = v_app.user_id;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.review_worker_application(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.review_worker_application(uuid, boolean, text) TO authenticated;
