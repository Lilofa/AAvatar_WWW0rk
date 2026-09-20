-- =============================================
-- 1. Форс-закрытие: устойчивый флаг
-- =============================================
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS force_closed boolean NOT NULL DEFAULT false;

-- =============================================
-- 2. fail_count у грузчика (пропуск утренних дедлайнов)
-- =============================================
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS fail_count int NOT NULL DEFAULT 0;

-- =============================================
-- 3. force_close_order → ставит флаг
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
  SET status          = 'completed',
      feedback_missed = true,
      force_closed    = true,
      completed_at    = now(),
      result_comment  = p_comment
  WHERE id = p_order_id;

  INSERT INTO public.audit_log (user_id, action, entity, entity_id, payload)
  VALUES (auth.uid(), 'force_close', 'order', p_order_id,
          jsonb_build_object('comment', p_comment));
END;
$$;

-- =============================================
-- 4. get_stage_availability — добавить feedback_deadline
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
  v_feedback_deadline timestamptz;
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

  -- Дедлайны
  IF v_order.scheduled_at IS NOT NULL THEN
    v_woke_deadline     := v_order.scheduled_at - interval '1 hour';
    v_departed_deadline := v_order.scheduled_at - interval '30 minutes';

    IF extract(hour from (v_order.scheduled_at AT TIME ZONE 'Asia/Novosibirsk')) BETWEEN 4 AND 12 THEN
      v_is_morning := true;
    END IF;
  END IF;

  -- feedback_deadline: 5 минут после finished
  IF 'finished' = ANY(v_done_stages) THEN
    SELECT created_at + interval '5 minutes'
    INTO v_feedback_deadline
    FROM public.order_stages
    WHERE order_id = p_order_id
      AND porter_id = v_user_id
      AND stage = 'finished';
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
    v_blocked_reason := CASE WHEN v_order.force_closed THEN 'Закрыт принудительно' ELSE 'Заказ завершён' END;
    v_available := ARRAY[]::text[];
  END IF;

  RETURN jsonb_build_object(
    'available',              to_jsonb(v_available),
    'next_required',          v_next_required,
    'woke_deadline',          v_woke_deadline,
    'departed_deadline',      v_departed_deadline,
    'feedback_deadline',      v_feedback_deadline,
    'is_late',                v_is_late,
    'penalty_if_pressed_now', v_penalty,
    'blocked_reason',         v_blocked_reason,
    'is_lead',                COALESCE(v_is_lead, false)
  );
END;
$$;

-- =============================================
-- 5. process_order_deadlines — инкремент fail_count
-- =============================================
CREATE OR REPLACE FUNCTION public.process_order_deadlines()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order record;
BEGIN
  -- 1. Авто-отклонение просроченных откликов
  UPDATE public.order_responses
  SET status = 'declined'
  WHERE status = 'pending'
    AND created_at < now() - interval '15 minutes';

  -- 2. Автоназначение старшего через 5 мин после accepted
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

  -- 3. Возврат в ленту при пропуске woke + fail_count у бригады
  FOR v_order IN
    SELECT o.id, o.scheduled_at
    FROM public.orders o
    WHERE o.status = 'accepted'
      AND o.scheduled_at IS NOT NULL
      AND extract(hour from (o.scheduled_at AT TIME ZONE 'Asia/Novosibirsk')) BETWEEN 4 AND 12
      AND now() > (o.scheduled_at - interval '1 hour') + interval '15 minutes'
      AND NOT EXISTS (SELECT 1 FROM public.order_stages WHERE order_id = o.id AND stage = 'woke')
  LOOP
    -- Инкремент fail_count всем в бригаде
    UPDATE public.profiles
    SET fail_count = fail_count + 1
    WHERE id IN (SELECT porter_id FROM public.order_takers WHERE order_id = v_order.id);

    UPDATE public.orders
    SET status = 'created', is_replacement = true, porter_id = NULL, accepted_at = NULL
    WHERE id = v_order.id;

    DELETE FROM public.order_takers WHERE order_id = v_order.id;

    INSERT INTO public.audit_log (user_id, action, entity, entity_id, payload)
    VALUES (NULL, 'woke_deadline_missed', 'order', v_order.id,
            jsonb_build_object('scheduled_at', v_order.scheduled_at));
  END LOOP;

  -- 4. Отмена срочного при пропуске departed > 15 мин
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

  -- 5. feedback_timeout
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

-- =============================================
-- 6. quote_order_detailed — с детализацией
-- =============================================
CREATE OR REPLACE FUNCTION public.quote_order_detailed(
  p_people_count int,
  p_planned_duration_min int,
  p_urgency text,
  p_transport text DEFAULT NULL
)
RETURNS jsonb
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
  v_transport_label text;
  v_work_amount numeric;
  v_total numeric;
  v_urgency_label text;
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

  v_urgency_label := CASE p_urgency
    WHEN 'urgent'  THEN 'срочный'
    WHEN 'current' THEN 'текущий'
    WHEN 'pre'     THEN 'предварительный'
    WHEN 'ahead'   THEN 'заранее'
    ELSE 'стандартный'
  END;

  v_transport_fee := CASE p_transport
    WHEN 'gazelle' THEN 1500
    WHEN 'truck'   THEN 3000
    ELSE 0
  END;

  v_transport_label := CASE p_transport
    WHEN 'gazelle' THEN 'Газель'
    WHEN 'truck'   THEN 'Грузовик'
    ELSE 'Без транспорта'
  END;

  v_work_amount := round(v_per_person_hour * p_people_count * v_planned_hours * v_urgency_mult, 2);
  v_total := round(v_base_fee + v_work_amount + v_transport_fee, 2);

  RETURN jsonb_build_object(
    'total', v_total,
    'lines', jsonb_build_array(
      jsonb_build_object('label', 'Базовый выезд', 'amount', v_base_fee),
      jsonb_build_object(
        'label',
        format('Работы: %s чел × %s ч (%s)', p_people_count, v_planned_hours, v_urgency_label),
        'amount', v_work_amount
      ),
      jsonb_build_object('label', v_transport_label, 'amount', v_transport_fee)
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.quote_order_detailed(int, int, text, text) TO authenticated;

-- quote_order — оставляю как обёртку для совместимости
CREATE OR REPLACE FUNCTION public.quote_order(
  p_people_count int,
  p_planned_duration_min int,
  p_urgency text,
  p_transport text DEFAULT NULL
)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT (public.quote_order_detailed(
    p_people_count, p_planned_duration_min, p_urgency, p_transport
  )->>'total')::numeric;
$$;

-- =============================================
-- 7. check_order_filled — пересчёт price при accepted
-- =============================================
CREATE OR REPLACE FUNCTION public.check_order_filled()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_approved int;
  v_needed int;
  v_status public.order_status;
  v_planned_duration int;
  v_urgency text;
  v_transport text;
BEGIN
  IF NEW.status <> 'approved' THEN
    RETURN NEW;
  END IF;

  SELECT people_count, status, planned_duration_min, urgency, transport
  INTO v_needed, v_status, v_planned_duration, v_urgency, v_transport
  FROM public.orders WHERE id = NEW.order_id;

  IF v_status <> 'created' THEN
    RETURN NEW;
  END IF;

  SELECT count(*) INTO v_approved
  FROM public.order_responses
  WHERE order_id = NEW.order_id AND status = 'approved';

  IF v_approved >= v_needed THEN
    UPDATE public.orders
    SET status      = 'accepted',
        porter_id   = (SELECT porter_id FROM public.order_takers WHERE order_id = NEW.order_id LIMIT 1),
        accepted_at = now(),
        price       = CASE
                        WHEN v_planned_duration IS NOT NULL
                        THEN public.quote_order(v_needed, v_planned_duration, v_urgency, v_transport)
                        ELSE price
                      END
    WHERE id = NEW.order_id;
  END IF;

  RETURN NEW;
END;
$$;
