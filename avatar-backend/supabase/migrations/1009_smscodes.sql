-- =============================================
-- Временное хранилище SMS-кодов
-- =============================================
CREATE TABLE public.sms_codes (
  phone       text PRIMARY KEY,
  code        text NOT NULL,
  attempts    int  NOT NULL DEFAULT 0,
  expires_at  timestamptz NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.sms_codes ENABLE ROW LEVEL SECURITY;
-- Политик нет → доступ только через service_role (Edge Functions).

-- Функция очистки старых кодов
CREATE OR REPLACE FUNCTION public.cleanup_expired_sms_codes()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  DELETE FROM public.sms_codes WHERE expires_at < now();
$$;

-- =============================================
-- RPC: принять заказ (защита от race condition)
-- =============================================
CREATE OR REPLACE FUNCTION public.accept_order(p_order_id uuid)
RETURNS public.orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders;
BEGIN
  IF public.current_user_role() <> 'porter' THEN
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

  RETURN v_order;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.accept_order(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.accept_order(uuid) TO authenticated;

-- =============================================
-- RPC: сменить статус заказа (только для своих)
-- =============================================
CREATE OR REPLACE FUNCTION public.advance_order_status(
  p_order_id uuid,
  p_new_status public.order_status
)
RETURNS public.orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF v_order.id IS NULL THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  -- Грузчик может двигать только свои заказы
  IF public.current_user_role() = 'porter' AND v_order.porter_id <> auth.uid() THEN
    RAISE EXCEPTION 'Not your order';
  END IF;

  -- Заказчик может только отменить свой
  IF public.current_user_role() = 'client' AND v_order.client_id <> auth.uid() THEN
    RAISE EXCEPTION 'Not your order';
  END IF;

  -- Разрешенные переходы
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
$$;

REVOKE EXECUTE ON FUNCTION public.advance_order_status(uuid, public.order_status) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.advance_order_status(uuid, public.order_status) TO authenticated;
