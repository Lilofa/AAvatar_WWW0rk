-- =============================================
-- Fix: time_start → scheduled_at (реальное имя колонки в orders)
-- =============================================

-- mark_stage
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
  v_is_morning boolean := false;
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

  SELECT id INTO v_existing
  FROM public.order_stages
  WHERE order_id = p_order_id
    AND porter_id = v_user_id
    AND stage = p_stage::public.stage_type;

  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'already_set', true, 'stage', p_stage);
  END IF;

  IF v_order.scheduled_at IS NOT NULL
     AND extract(hour from (v_order.scheduled_at AT TIME ZONE 'Asia/Novosibirsk')) BETWEEN 4 AND 12
  THEN
    v_is_morning := true;
  END IF;

  v_prev_stage := CASE p_stage
    WHEN 'woke'     THEN NULL
    WHEN 'departed' THEN CASE WHEN v_is_morning THEN 'woke' ELSE NULL END
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

  IF p_stage = 'woke' AND NOT v_is_morning THEN
    RAISE EXCEPTION 'STAGE_INVALID_ORDER: woke only for morning orders (4:00-12:00)';
  END IF;

  IF p_stage IN ('started', 'finished') AND NOT COALESCE(v_is_lead, false) THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: only lead can mark %', p_stage;
  END IF;

  v_availability := public.get_stage_availability(p_order_id);
  v_penalty := COALESCE((v_availability->>'penalty_if_pressed_now')::int, 0);

  INSERT INTO public.order_stages (order_id, porter_id, stage, coords)
  VALUES (p_order_id, v_user_id, p_stage::public.stage_type, p_coords);

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

-- get_stage_availability
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
  v_is_morning boolean := false;
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

  IF v_order.scheduled_at IS NOT NULL THEN
    v_woke_deadline     := v_order.scheduled_at - interval '1 hour';
    v_departed_deadline := v_order.scheduled_at - interval '30 minutes';

    IF extract(hour from (v_order.scheduled_at AT TIME ZONE 'Asia/Novosibirsk')) BETWEEN 4 AND 12 THEN
      v_is_morning := true;
    END IF;
  END IF;

  IF v_is_morning AND NOT ('woke' = ANY(v_done_stages)) THEN
    v_next_required := 'woke';
    v_available := array_append(v_available, 'woke');
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

-- process_order_deadlines
CREATE OR REPLACE FUNCTION public.process_order_deadlines()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order record;
BEGIN
  UPDATE public.order_responses
  SET status = 'declined'
  WHERE status = 'pending'
    AND created_at < now() - interval '15 minutes';

  FOR v_order IN
    SELECT o.id
    FROM public.orders o
    WHERE o.status = 'accepted'
      AND o.accepted_at < now() - interval '5 minutes'
      AND NOT EXISTS (SELECT 1 FROM public.order_takers WHERE order_id = o.id AND is_lead = true)
  LOOP
    UPDATE public.order_takers ot
    SET is_lead = true
    FROM public.profiles p
    WHERE ot.order_id = v_order.id
      AND ot.porter_id = p.id
      AND ot.porter_id = (
        SELECT porter_id FROM public.order_takers ot2
        JOIN public.profiles p2 ON p2.id = ot2.porter_id
        WHERE ot2.order_id = v_order.id
        ORDER BY p2.rating DESC, p2.completed_count DESC
        LIMIT 1
      );

    INSERT INTO public.audit_log (user_id, action, entity, entity_id, payload)
    VALUES (NULL, 'lead_auto_assigned', 'order', v_order.id, '{}'::jsonb);
  END LOOP;

  FOR v_order IN
    SELECT o.id, o.scheduled_at
    FROM public.orders o
    WHERE o.status = 'accepted'
      AND o.scheduled_at IS NOT NULL
      AND extract(hour from (o.scheduled_at AT TIME ZONE 'Asia/Novosibirsk')) BETWEEN 4 AND 12
      AND now() > (o.scheduled_at - interval '1 hour') + interval '15 minutes'
      AND NOT EXISTS (SELECT 1 FROM public.order_stages WHERE order_id = o.id AND stage = 'woke')
  LOOP
    UPDATE public.orders
    SET status = 'created', is_replacement = true, porter_id = NULL, accepted_at = NULL
    WHERE id = v_order.id;

    DELETE FROM public.order_takers WHERE order_id = v_order.id;

    INSERT INTO public.audit_log (user_id, action, entity, entity_id, payload)
    VALUES (NULL, 'woke_deadline_missed', 'order', v_order.id,
            jsonb_build_object('scheduled_at', v_order.scheduled_at));
  END LOOP;

  FOR v_order IN
    SELECT o.id
    FROM public.orders o
    WHERE o.status = 'accepted'
      AND o.urgency = 'urgent'
      AND o.scheduled_at IS NOT NULL
      AND now() > (o.scheduled_at - interval '30 minutes') + interval '15 minutes'
      AND NOT EXISTS (SELECT 1 FROM public.order_stages WHERE order_id = o.id AND stage = 'departed')
  LOOP
    UPDATE public.orders
    SET status = 'cancelled', cancelled_at = now()
    WHERE id = v_order.id;

    INSERT INTO public.audit_log (user_id, action, entity, entity_id, payload)
    VALUES (NULL, 'deadline_cancelled', 'order', v_order.id, '{}'::jsonb);
  END LOOP;

  FOR v_order IN
    SELECT o.id
    FROM public.orders o
    WHERE o.status = 'in_progress'
      AND o.feedback_missed = false
      AND EXISTS (
        SELECT 1 FROM public.order_stages
        WHERE order_id = o.id AND stage = 'finished'
          AND created_at < now() - interval '5 minutes'
      )
  LOOP
    UPDATE public.orders
    SET status = 'completed', completed_at = now(), feedback_missed = true
    WHERE id = v_order.id;

    INSERT INTO public.audit_log (user_id, action, entity, entity_id, payload)
    VALUES (NULL, 'feedback_timeout', 'order', v_order.id, '{}'::jsonb);
  END LOOP;
END;
$$;
