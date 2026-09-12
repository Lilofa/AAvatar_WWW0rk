-- =============================================
-- pg_cron и обработка дедлайнов
-- =============================================
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Обработка всех просроченных дедлайнов раз в минуту
CREATE OR REPLACE FUNCTION public.process_order_deadlines()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order record;
BEGIN
  -- 1. Авто-отклонение просроченных откликов (15 мин)
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
      AND NOT EXISTS (
        SELECT 1 FROM public.order_takers
        WHERE order_id = o.id AND is_lead = true
      )
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

  -- 3. Возврат заказа в ленту при пропуске woke (утренние)
  FOR v_order IN
    SELECT o.id, o.time_start
    FROM public.orders o
    WHERE o.status = 'accepted'
      AND o.time_start IS NOT NULL
      AND extract(hour from (o.time_start AT TIME ZONE 'Asia/Novosibirsk')) BETWEEN 4 AND 12
      AND now() > (o.time_start - interval '1 hour') + interval '15 minutes'
      AND NOT EXISTS (
        SELECT 1 FROM public.order_stages
        WHERE order_id = o.id AND stage = 'woke'
      )
  LOOP
    UPDATE public.orders
    SET status = 'created',
        is_replacement = true,
        porter_id = NULL,
        accepted_at = NULL
    WHERE id = v_order.id;

    DELETE FROM public.order_takers WHERE order_id = v_order.id;

    INSERT INTO public.audit_log (user_id, action, entity, entity_id, payload)
    VALUES (NULL, 'woke_deadline_missed', 'order', v_order.id,
            jsonb_build_object('time_start', v_order.time_start));
  END LOOP;

  -- 4. Отмена срочного при пропуске departed > 15 мин
  FOR v_order IN
    SELECT o.id
    FROM public.orders o
    WHERE o.status = 'accepted'
      AND o.urgency = 'urgent'
      AND o.time_start IS NOT NULL
      AND now() > (o.time_start - interval '30 minutes') + interval '15 minutes'
      AND NOT EXISTS (
        SELECT 1 FROM public.order_stages
        WHERE order_id = o.id AND stage = 'departed'
      )
  LOOP
    UPDATE public.orders
    SET status = 'cancelled',
        cancelled_at = now()
    WHERE id = v_order.id;

    INSERT INTO public.audit_log (user_id, action, entity, entity_id, payload)
    VALUES (NULL, 'deadline_cancelled', 'order', v_order.id, '{}'::jsonb);
  END LOOP;

  -- 5. Авто-закрытие по feedback_timeout (5 мин после finished)
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
    SET status = 'completed',
        completed_at = now(),
        feedback_missed = true
    WHERE id = v_order.id;

    INSERT INTO public.audit_log (user_id, action, entity, entity_id, payload)
    VALUES (NULL, 'feedback_timeout', 'order', v_order.id, '{}'::jsonb);
  END LOOP;
END;
$$;

-- Регистрируем джоб в pg_cron
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'process_order_deadlines') THEN
    PERFORM cron.schedule(
      'process_order_deadlines',
      '* * * * *',
      $cron$ SELECT public.process_order_deadlines(); $cron$
    );
  END IF;
END $$;

-- =============================================
-- RPC: finish_order
-- =============================================
CREATE OR REPLACE FUNCTION public.finish_order(
  p_order_id uuid,
  p_went_well boolean,
  p_result_comment text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders;
  v_started timestamptz;
  v_finished timestamptz;
  v_minutes int;
  v_hours numeric;
  v_total numeric;
  v_rating_delta int;
  v_is_lead boolean;
  v_user_id uuid := auth.uid();
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF v_order.id IS NULL THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND';
  END IF;

  SELECT is_lead INTO v_is_lead
  FROM public.order_takers
  WHERE order_id = p_order_id AND porter_id = v_user_id;

  IF NOT COALESCE(v_is_lead, false) THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: only lead can finish order';
  END IF;

  IF v_order.status <> 'in_progress' THEN
    RAISE EXCEPTION 'STAGE_INVALID_ORDER: order is %', v_order.status;
  END IF;

  SELECT created_at INTO v_started
  FROM public.order_stages
  WHERE order_id = p_order_id AND porter_id = v_user_id AND stage = 'started';

  IF v_started IS NULL THEN
    RAISE EXCEPTION 'STAGE_NOT_YOUR_TURN: started stage missing';
  END IF;

  v_finished := now();
  v_minutes := greatest(1, extract(epoch from (v_finished - v_started))::int / 60);
  v_hours := ceil(v_minutes::numeric / 30) * 0.5;
  v_total := v_hours * v_order.people_count;

  v_rating_delta := 2; -- старший получает +2

  UPDATE public.orders
  SET status          = 'completed',
      completed_at    = v_finished,
      went_well       = p_went_well,
      result_comment  = p_result_comment
  WHERE id = p_order_id;

  -- Начисляем рейтинг всем участникам
  UPDATE public.profiles
  SET rating = rating + v_rating_delta,
      completed_count = completed_count + 1
  WHERE id IN (
    SELECT porter_id FROM public.order_takers WHERE order_id = p_order_id
  );

  INSERT INTO public.audit_log (user_id, action, entity, entity_id, payload)
  VALUES (v_user_id, 'order_finished', 'order', p_order_id,
          jsonb_build_object('went_well', p_went_well, 'minutes', v_minutes));

  RETURN jsonb_build_object(
    'order_id',       p_order_id,
    'hours',          v_hours,
    'total_hours',    v_total,
    'minutes_worked', v_minutes,
    'rating_delta',   v_rating_delta,
    'money_delta',    NULL,
    'finished_at',    v_finished
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.finish_order(uuid, boolean, text) TO authenticated;

-- =============================================
-- RPC: submit_review
-- =============================================
CREATE OR REPLACE FUNCTION public.submit_review(
  p_order_id uuid,
  p_target_id uuid,
  p_rating int,
  p_text text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders;
  v_review_id uuid;
  v_old_count int;
  v_old_rating numeric;
  v_new_rating numeric;
BEGIN
  IF p_rating NOT BETWEEN 1 AND 5 THEN
    RAISE EXCEPTION 'VALIDATION_FAILED: rating must be 1..5';
  END IF;

  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id;
  IF v_order.id IS NULL THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND';
  END IF;

  IF v_order.client_id <> auth.uid() THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: only client can review';
  END IF;

  IF v_order.status <> 'completed' THEN
    RAISE EXCEPTION 'VALIDATION_FAILED: order not completed';
  END IF;

  INSERT INTO public.reviews (order_id, author_id, target_id, rating, text)
  VALUES (p_order_id, auth.uid(), p_target_id, p_rating, p_text)
  RETURNING id INTO v_review_id;

  -- Пересчёт среднего рейтинга
  SELECT reviews_count, rating INTO v_old_count, v_old_rating
  FROM public.profiles WHERE id = p_target_id;

  v_new_rating := round(
    ((COALESCE(v_old_rating, 0) * COALESCE(v_old_count, 0)) + p_rating)::numeric
    / (COALESCE(v_old_count, 0) + 1),
    2
  );

  UPDATE public.profiles
  SET rating = v_new_rating,
      reviews_count = COALESCE(v_old_count, 0) + 1
  WHERE id = p_target_id;

  RETURN v_review_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.submit_review(uuid, uuid, int, text) TO authenticated;
