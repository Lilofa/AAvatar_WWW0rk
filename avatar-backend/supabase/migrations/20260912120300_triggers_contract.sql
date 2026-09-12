-- =============================================
-- Автоотклонение просроченных откликов (15 мин)
-- =============================================
CREATE OR REPLACE FUNCTION public.auto_decline_stale_responses()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.order_responses
  SET status = 'declined'
  WHERE status = 'pending'
    AND created_at < now() - interval '15 minutes';
END;
$$;

-- =============================================
-- Автоперевод заказа в accepted при N одобренных
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
BEGIN
  IF NEW.status <> 'approved' THEN
    RETURN NEW;
  END IF;

  SELECT people_count, status INTO v_needed, v_status
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
        porter_id   = (
          SELECT porter_id FROM public.order_takers
          WHERE order_id = NEW.order_id LIMIT 1
        ),
        accepted_at = now()
    WHERE id = NEW.order_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_check_order_filled ON public.order_responses;
CREATE TRIGGER trg_check_order_filled
AFTER UPDATE ON public.order_responses
FOR EACH ROW EXECUTE FUNCTION public.check_order_filled();

-- =============================================
-- Добавление в order_takers при одобрении отклика
-- =============================================
CREATE OR REPLACE FUNCTION public.add_taker_on_approve()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'approved' AND (OLD.status IS NULL OR OLD.status <> 'approved') THEN
    INSERT INTO public.order_takers (order_id, porter_id, is_lead)
    VALUES (NEW.order_id, NEW.porter_id, false)
    ON CONFLICT (order_id, porter_id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_add_taker_on_approve ON public.order_responses;
CREATE TRIGGER trg_add_taker_on_approve
AFTER UPDATE ON public.order_responses
FOR EACH ROW EXECUTE FUNCTION public.add_taker_on_approve();

-- =============================================
-- Автозаполнение editable_until при вставке отзыва
-- =============================================
CREATE OR REPLACE FUNCTION public.set_review_editable_until()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.editable_until IS NULL THEN
    NEW.editable_until := now() + interval '24 hours';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_reviews_editable_until ON public.reviews;
CREATE TRIGGER trg_reviews_editable_until
BEFORE INSERT ON public.reviews
FOR EACH ROW EXECUTE FUNCTION public.set_review_editable_until();

-- =============================================
-- Скрытие entrance до started
-- =============================================
CREATE OR REPLACE FUNCTION public.hide_entrance_before_started()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders;
  v_result jsonb;
  v_can_see boolean := false;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = (current_setting('request.jwt.claims', true)::jsonb->>'order_id')::uuid;

  RETURN '{}'::jsonb;
END;
$$;

-- Обёртка над getOrder, чтобы не палить entrance:
CREATE OR REPLACE FUNCTION public.get_order_safe(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
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
  IF v_role = 'client' AND v_order.client_id = v_user_id THEN
    v_can_see_entrance := true;
  END IF;

  -- Диспетчер/админ видят всегда
  IF v_role IN ('dispatcher', 'admin') THEN
    v_can_see_entrance := true;
  END IF;

  -- Грузчик видит, если он старший и статус started/in_progress/completed
  IF v_role = 'porter' THEN
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
$$;

GRANT EXECUTE ON FUNCTION public.get_order_safe(uuid) TO authenticated;
