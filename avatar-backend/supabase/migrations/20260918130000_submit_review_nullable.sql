-- =============================================
-- 1. target_id в reviews → nullable (отзыв о заказе)
-- =============================================
ALTER TABLE public.reviews
  ALTER COLUMN target_id DROP NOT NULL;

-- =============================================
-- 2. submit_review: target_id опциональный
-- =============================================
DROP FUNCTION IF EXISTS public.submit_review(uuid, uuid, int, text);
DROP FUNCTION IF EXISTS public.submit_review(uuid, int, text, uuid);

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

  -- Пересчёт рейтинга — только если target_id задан (v2)
  IF p_target_id IS NOT NULL THEN
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
  END IF;

  RETURN v_review_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.submit_review(uuid, int, text, uuid) TO authenticated;

-- =============================================
-- 3. accept_order → DEPRECATED
-- =============================================
COMMENT ON FUNCTION public.accept_order(uuid) IS
  'DEPRECATED: используйте respond_to_order + approve_response. Оставлено для QA и отладки.';
