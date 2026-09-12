-- =============================================
-- switch_role — переключение активной роли
-- =============================================
CREATE OR REPLACE FUNCTION public.switch_role(p_role text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid()
      AND (p_role = ANY(roles) OR role::text = p_role)
  ) THEN
    RAISE EXCEPTION 'ROLE_NOT_ASSIGNED: role % is not assigned to user', p_role;
  END IF;

  UPDATE public.profiles
  SET active_role = p_role,
      role = p_role::public.user_role
  WHERE id = auth.uid();
END;
$$;

REVOKE EXECUTE ON FUNCTION public.switch_role(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.switch_role(text) TO authenticated;

-- =============================================
-- add_role — добавить роль
-- =============================================
CREATE OR REPLACE FUNCTION public.add_role(p_role text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.profiles
  SET roles = array_append(roles, p_role)
  WHERE id = auth.uid()
    AND NOT (p_role = ANY(roles));
END;
$$;

REVOKE EXECUTE ON FUNCTION public.add_role(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.add_role(text) TO authenticated;

-- =============================================
-- quote_order — калькулятор тарифа
-- =============================================
CREATE OR REPLACE FUNCTION public.quote_order(
  p_people_count int,
  p_planned_duration_min int,
  p_urgency text,
  p_transport text DEFAULT NULL
)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_base_fee constant numeric := 500;
  v_per_person_hour constant numeric := 400;
  v_planned_hours numeric;
  v_urgency_mult numeric;
  v_transport_fee numeric := 0;
  v_subtotal numeric;
BEGIN
  IF p_people_count IS NULL OR p_people_count < 1 THEN
    RAISE EXCEPTION 'VALIDATION_FAILED: people_count must be >= 1';
  END IF;
  IF p_planned_duration_min IS NULL OR p_planned_duration_min < 30 THEN
    RAISE EXCEPTION 'VALIDATION_FAILED: planned_duration_min must be >= 30';
  END IF;

  v_planned_hours := ceil(p_planned_duration_min::numeric / 60);

  v_urgency_mult := CASE p_urgency
    WHEN 'urgent'  THEN 1.5
    WHEN 'current' THEN 1.0
    WHEN 'pre'     THEN 0.9
    WHEN 'ahead'   THEN 0.8
    ELSE 1.0
  END;

  v_transport_fee := CASE p_transport
    WHEN 'gazelle' THEN 1500
    WHEN 'truck'   THEN 3000
    ELSE 0
  END;

  v_subtotal := v_base_fee
              + v_per_person_hour * p_people_count * v_planned_hours * v_urgency_mult
              + v_transport_fee;

  RETURN round(v_subtotal, 2);
END;
$$;

GRANT EXECUTE ON FUNCTION public.quote_order(int, int, text, text) TO authenticated;

-- =============================================
-- get_stage_availability — что доступно нажать
-- =============================================
CREATE OR REPLACE FUNCTION public.get_stage_availability(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders;
  v_user_id uuid := auth.uid();
  v_is_lead boolean;
  v_done_stages text[];
  v_available text[] := ARRAY[]::text[];
  v_next_required text;
  v_woke_deadline timestamptz;
  v_departed_deadline timestamptz;
  v_is_late boolean := false;
  v_penalty int := 0;
  v_blocked_reason text;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id;
  IF v_order.id IS NULL THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND';
  END IF;

  SELECT is_lead INTO v_is_lead
  FROM public.order_takers
  WHERE order_id = p_order_id AND porter_id = v_user_id;

  SELECT array_agg(stage::text) INTO v_done_stages
  FROM public.order_stages
  WHERE order_id = p_order_id AND porter_id = v_user_id;

  IF v_done_stages IS NULL THEN v_done_stages := ARRAY[]::text[]; END IF;

  IF v_order.time_start IS NOT NULL THEN
    v_woke_deadline     := v_order.time_start - interval '1 hour';
    v_departed_deadline := v_order.time_start - interval '30 minutes';
  END IF;

  IF NOT ('woke' = ANY(v_done_stages)) THEN
    v_next_required := 'woke';
    IF v_order.time_start IS NOT NULL
       AND extract(hour from (v_order.time_start AT TIME ZONE 'Asia/Novosibirsk')) BETWEEN 4 AND 12 THEN
      v_available := array_append(v_available, 'woke');
    END IF;
  ELSIF NOT ('departed' = ANY(v_done_stages)) THEN
    v_next_required := 'departed';
    v_available := array_append(v_available, 'departed');
    IF v_departed_deadline IS NOT NULL AND now() > v_departed_deadline THEN
      v_is_late := true;
      v_penalty := -5;
    END IF;
  ELSIF NOT ('arrived' = ANY(v_done_stages)) THEN
    v_next_required := 'arrived';
    v_available := array_append(v_available, 'arrived');
  ELSIF NOT ('started' = ANY(v_done_stages)) THEN
    v_next_required := 'started';
    IF COALESCE(v_is_lead, false) THEN
      v_available := array_append(v_available, 'started');
    ELSE
      v_blocked_reason := 'Только старший может начать работу';
    END IF;
  ELSIF NOT ('finished' = ANY(v_done_stages)) THEN
    v_next_required := 'finished';
    IF COALESCE(v_is_lead, false) THEN
      v_available := array_append(v_available, 'finished');
    ELSE
      v_blocked_reason := 'Только старший может завершить работу';
    END IF;
  END IF;

  IF v_order.status = 'cancelled' THEN
    v_blocked_reason := 'Заказ отменён';
    v_available := ARRAY[]::text[];
  ELSIF v_order.status = 'completed' THEN
    v_blocked_reason := 'Заказ завершён';
    v_available := ARRAY[]::text[];
  END IF;

  RETURN jsonb_build_object(
    'available',              to_jsonb(v_available),
    'next_required',          v_next_required,
    'woke_deadline',          v_woke_deadline,
    'departed_deadline',      v_departed_deadline,
    'is_late',                v_is_late,
    'penalty_if_pressed_now', v_penalty,
    'blocked_reason',         v_blocked_reason,
    'is_lead',                COALESCE(v_is_lead, false)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_stage_availability(uuid) TO authenticated;

-- =============================================
-- mark_stage — идемпотентная отметка этапа
-- =============================================
CREATE OR REPLACE FUNCTION public.mark_stage(
  p_order_id uuid,
  p_stage text,
  p_coords jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders;
  v_user_id uuid := auth.uid();
  v_is_lead boolean;
  v_existing uuid;
  v_availability jsonb;
  v_prev_stage text;
  v_penalty int := 0;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF v_order.id IS NULL THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND';
  END IF;

  IF v_order.status IN ('cancelled', 'completed') THEN
    RAISE EXCEPTION 'STAGE_INVALID_ORDER: order is %', v_order.status;
  END IF;

  SELECT is_lead INTO v_is_lead
  FROM public.order_takers
  WHERE order_id = p_order_id AND porter_id = v_user_id;

  IF v_is_lead IS NULL THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: not assigned to this order';
  END IF;

  -- идемпотентность
  SELECT id INTO v_existing
  FROM public.order_stages
  WHERE order_id = p_order_id
    AND porter_id = v_user_id
    AND stage = p_stage::public.stage_type;

  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'already_set', true, 'stage', p_stage);
  END IF;

  -- порядок
  v_prev_stage := CASE p_stage
    WHEN 'departed' THEN 'woke'
    WHEN 'arrived'  THEN 'departed'
    WHEN 'started'  THEN 'arrived'
    WHEN 'finished' THEN 'started'
    ELSE NULL
  END;

  IF v_prev_stage IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.order_stages
    WHERE order_id = p_order_id
      AND porter_id = v_user_id
      AND stage = v_prev_stage::public.stage_type
  ) THEN
    RAISE EXCEPTION 'STAGE_NOT_YOUR_TURN: cannot mark % before %', p_stage, v_prev_stage;
  END IF;

  -- только старший для started/finished
  IF p_stage IN ('started', 'finished') AND NOT COALESCE(v_is_lead, false) THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: only lead can mark %', p_stage;
  END IF;

  -- woke только для утренних
  IF p_stage = 'woke' AND v_order.time_start IS NOT NULL THEN
    IF NOT (extract(hour from (v_order.time_start AT TIME ZONE 'Asia/Novosibirsk')) BETWEEN 4 AND 12) THEN
      RAISE EXCEPTION 'STAGE_INVALID_ORDER: woke only for morning orders (4:00-12:00)';
    END IF;
  END IF;

  -- штраф
  v_availability := public.get_stage_availability(p_order_id);
  v_penalty := COALESCE((v_availability->>'penalty_if_pressed_now')::int, 0);

  -- запись
  INSERT INTO public.order_stages (order_id, porter_id, stage, coords)
  VALUES (p_order_id, v_user_id, p_stage::public.stage_type, p_coords);

  -- автосмена статуса
  IF p_stage = 'started' AND v_order.status = 'accepted' THEN
    UPDATE public.orders SET status = 'in_progress' WHERE id = p_order_id;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'already_set', false,
    'stage', p_stage,
    'penalty', v_penalty
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.mark_stage(uuid, text, jsonb) TO authenticated;

-- =============================================
-- submit_delay_reason
-- =============================================
CREATE OR REPLACE FUNCTION public.submit_delay_reason(
  p_order_id uuid,
  p_reason text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.order_takers
    WHERE order_id = p_order_id AND porter_id = auth.uid() AND is_lead = true
  ) THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: only lead can submit delay reason';
  END IF;

  INSERT INTO public.audit_log (user_id, action, entity, entity_id, payload)
  VALUES (auth.uid(), 'delay_reason', 'order', p_order_id, jsonb_build_object('reason', p_reason));
END;
$$;

GRANT EXECUTE ON FUNCTION public.submit_delay_reason(uuid, text) TO authenticated;

-- =============================================
-- get_pending_review_count
-- =============================================
CREATE OR REPLACE FUNCTION public.get_pending_review_count()
RETURNS int
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT count(*)::int
  FROM public.orders o
  WHERE o.client_id = auth.uid()
    AND o.status = 'completed'
    AND NOT EXISTS (
      SELECT 1 FROM public.reviews r
      WHERE r.order_id = o.id AND r.author_id = auth.uid()
    );
$$;

GRANT EXECUTE ON FUNCTION public.get_pending_review_count() TO authenticated;

-- =============================================
-- update_porter_location
-- =============================================
CREATE OR REPLACE FUNCTION public.update_porter_location(
  p_order_id uuid,
  p_lat numeric,
  p_lng numeric,
  p_accuracy_m numeric DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.order_takers
    WHERE order_id = p_order_id AND porter_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: not your order';
  END IF;

  INSERT INTO public.order_locations (order_id, porter_id, lat, lng, accuracy_m)
  VALUES (p_order_id, auth.uid(), p_lat, p_lng, p_accuracy_m);
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_porter_location(uuid, numeric, numeric, numeric) TO authenticated;

-- =============================================
-- assign_lead
-- =============================================
CREATE OR REPLACE FUNCTION public.assign_lead(
  p_order_id uuid,
  p_porter_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF public.current_user_role() NOT IN ('dispatcher', 'admin') THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: only dispatcher or admin';
  END IF;

  UPDATE public.order_takers SET is_lead = false WHERE order_id = p_order_id;

  UPDATE public.order_takers
  SET is_lead = true
  WHERE order_id = p_order_id AND porter_id = p_porter_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_FAILED: porter % not assigned to order %', p_porter_id, p_order_id;
  END IF;

  INSERT INTO public.audit_log (user_id, action, entity, entity_id, payload)
  VALUES (auth.uid(), 'lead_assigned', 'order', p_order_id,
          jsonb_build_object('porter_id', p_porter_id));
END;
$$;

GRANT EXECUTE ON FUNCTION public.assign_lead(uuid, uuid) TO authenticated;

-- =============================================
-- find_replacement
-- =============================================
CREATE OR REPLACE FUNCTION public.find_replacement(p_order_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF public.current_user_role() NOT IN ('dispatcher', 'admin') THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: only dispatcher or admin';
  END IF;

  UPDATE public.orders
  SET is_replacement = true,
      status         = 'created',
      porter_id      = NULL,
      accepted_at    = NULL
  WHERE id = p_order_id;

  INSERT INTO public.audit_log (user_id, action, entity, entity_id, payload)
  VALUES (auth.uid(), 'find_replacement', 'order', p_order_id, '{}'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION public.find_replacement(uuid) TO authenticated;

-- =============================================
-- force_close_order
-- =============================================
CREATE OR REPLACE FUNCTION public.force_close_order(
  p_order_id uuid,
  p_comment text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF public.current_user_role() NOT IN ('dispatcher', 'admin') THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: only dispatcher or admin';
  END IF;

  UPDATE public.orders
  SET status           = 'completed',
      feedback_missed  = true,
      completed_at     = now()
  WHERE id = p_order_id;

  INSERT INTO public.audit_log (user_id, action, entity, entity_id, payload)
  VALUES (auth.uid(), 'force_close', 'order', p_order_id,
          jsonb_build_object('comment', p_comment));
END;
$$;

GRANT EXECUTE ON FUNCTION public.force_close_order(uuid, text) TO authenticated;

-- =============================================
-- register_device_token
-- =============================================
CREATE OR REPLACE FUNCTION public.register_device_token(
  p_token text,
  p_platform text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_platform NOT IN ('ios', 'android') THEN
    RAISE EXCEPTION 'VALIDATION_FAILED: platform must be ios or android';
  END IF;

  INSERT INTO public.device_tokens (user_id, token, platform)
  VALUES (auth.uid(), p_token, p_platform)
  ON CONFLICT (user_id, token) DO NOTHING;
END;
$$;

GRANT EXECUTE ON FUNCTION public.register_device_token(text, text) TO authenticated;
