-- respond_to_order
CREATE OR REPLACE FUNCTION public.respond_to_order(
  p_order_id uuid,
  p_eta_minutes int DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders;
  v_response_id uuid;
  v_user_id uuid := auth.uid();
BEGIN
  IF public.current_user_role() <> 'porter' THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: only porters';
  END IF;

  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id;
  IF v_order.id IS NULL THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND';
  END IF;

  IF v_order.status <> 'created' THEN
    RAISE EXCEPTION 'ORDER_ALREADY_TAKEN: order is %', v_order.status;
  END IF;

  INSERT INTO public.order_responses (order_id, porter_id, eta_minutes, status)
  VALUES (p_order_id, v_user_id, p_eta_minutes, 'pending')
  ON CONFLICT (order_id, porter_id) DO UPDATE
    SET eta_minutes = EXCLUDED.eta_minutes,
        status = 'pending'
  RETURNING id INTO v_response_id;

  RETURN v_response_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.respond_to_order(uuid, int) TO authenticated;

-- approve_response
CREATE OR REPLACE FUNCTION public.approve_response(p_response_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF public.current_user_role() NOT IN ('dispatcher', 'admin') THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: only dispatcher or admin';
  END IF;

  UPDATE public.order_responses
  SET status = 'approved'
  WHERE id = p_response_id AND status = 'pending';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_FAILED: response not found or not pending';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.approve_response(uuid) TO authenticated;

-- decline_response
CREATE OR REPLACE FUNCTION public.decline_response(
  p_response_id uuid,
  p_reason text DEFAULT NULL
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

  UPDATE public.order_responses
  SET status = 'declined'
  WHERE id = p_response_id AND status = 'pending';

  INSERT INTO public.audit_log (user_id, action, entity, entity_id, payload)
  VALUES (auth.uid(), 'response_declined', 'order_response', p_response_id,
          jsonb_build_object('reason', p_reason));
END;
$$;

GRANT EXECUTE ON FUNCTION public.decline_response(uuid, text) TO authenticated;

-- cancel_response (своя отмена)
CREATE OR REPLACE FUNCTION public.cancel_response(p_response_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.order_responses
  WHERE id = p_response_id
    AND porter_id = auth.uid()
    AND status = 'pending';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: not your response or already processed';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.cancel_response(uuid) TO authenticated;
