-- =============================================================================
-- SECURITY HARDENING, часть 2 (white-box пентест 16.11.2026)
--
--  P1  Заблокированный пользователь (profiles.is_blocked) продолжал работать:
--      откликался на заказы, проходил все проверки ролей.
--  P2  submit_review: заказчик мог поставить оценку ЛЮБОМУ грузчику платформы,
--      а не только своей бригаде (обвал рейтинга конкурента). Плюс рейтинг
--      пересчитывался дважды: триггером reviews_recalc_rating и вручную в RPC.
--  P3  respond_to_order принимал любой ETA (NULL, отрицательный, 10^9 минут).
-- =============================================================================

-- P1: заблокированный = без роли. Все RPC и RLS-политики, которые проверяют
-- current_user_role(), перестают его пропускать.
CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS public.user_role
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT role FROM public.profiles WHERE id = auth.uid() AND NOT is_blocked;
$$;

-- P2 + P3
CREATE OR REPLACE FUNCTION public.submit_review(
  p_order_id uuid,
  p_rating int,
  p_text text DEFAULT NULL,
  p_target_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders;
  v_review_id uuid;
BEGIN
  IF public.current_user_role() IS NULL THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: account blocked' USING ERRCODE = '42501';
  END IF;
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
  -- Оценивать можно только того, кто реально работал на этом заказе.
  IF p_target_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.order_takers t
    WHERE t.order_id = p_order_id AND t.porter_id = p_target_id
  ) THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: target did not work on this order' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.reviews (order_id, author_id, target_id, rating, text)
  VALUES (p_order_id, auth.uid(), p_target_id, p_rating, left(p_text, 2000))
  RETURNING id INTO v_review_id;
  -- Рейтинг пересчитывает триггер trg_reviews_recalc (среднее по всем отзывам).
  RETURN v_review_id;
END;
$$;
REVOKE ALL ON FUNCTION public.submit_review(uuid, int, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_review(uuid, int, text, uuid) TO authenticated;

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
  IF public.current_user_role() IS DISTINCT FROM 'porter' THEN
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
$$;
REVOKE ALL ON FUNCTION public.respond_to_order(uuid, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.respond_to_order(uuid, int) TO authenticated;
