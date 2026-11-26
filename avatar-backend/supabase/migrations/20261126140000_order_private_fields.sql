-- B2 из docs/pentest-2026-11-16.md: любой грузчик видел телефон заказчика и
-- подъезд во всех открытых заказах (прямой select из orders, realtime-лента).
-- Политика конфиденциальности обещает: телефон — только назначенной бригаде,
-- подъезд — старшему после «Начали».
--
-- Решение без переделки всего приложения:
--   * client_phone и entrance переезжают в public.order_private (RLS, прямого
--     доступа нет ни у кого из клиентов);
--   * триггер на orders перекладывает их туда при INSERT/UPDATE и обнуляет в
--     самой строке заказа — лента, realtime и select их больше не видят;
--   * get_order_safe возвращает их только тем, кому можно.
-- Заодно: get_order_safe (SECURITY DEFINER) отдавал ЛЮБОЙ заказ по id любому
-- вошедшему пользователю. Теперь — только участникам, персоналу и грузчикам
-- для открытых заказов из ленты.

CREATE TABLE IF NOT EXISTS public.order_private (
  order_id     uuid PRIMARY KEY
               REFERENCES public.orders(id) ON DELETE CASCADE
               DEFERRABLE INITIALLY DEFERRED,
  client_phone text,
  entrance     integer
);
ALTER TABLE public.order_private ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.order_private FROM anon, authenticated;
-- Политик нет: читать можно только через get_order_safe.

-- Перенос уже существующих данных.
INSERT INTO public.order_private (order_id, client_phone, entrance)
SELECT id, client_phone, entrance FROM public.orders
WHERE client_phone IS NOT NULL OR entrance IS NOT NULL
ON CONFLICT (order_id) DO UPDATE
  SET client_phone = COALESCE(EXCLUDED.client_phone, public.order_private.client_phone),
      entrance     = COALESCE(EXCLUDED.entrance, public.order_private.entrance);
UPDATE public.orders SET client_phone = NULL, entrance = NULL
WHERE client_phone IS NOT NULL OR entrance IS NOT NULL;

CREATE OR REPLACE FUNCTION public.split_order_private()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.client_phone IS NOT NULL OR NEW.entrance IS NOT NULL THEN
    INSERT INTO public.order_private (order_id, client_phone, entrance)
    VALUES (NEW.id, NEW.client_phone, NEW.entrance)
    ON CONFLICT (order_id) DO UPDATE
      SET client_phone = COALESCE(EXCLUDED.client_phone, public.order_private.client_phone),
          entrance     = COALESCE(EXCLUDED.entrance, public.order_private.entrance);
    NEW.client_phone := NULL;
    NEW.entrance := NULL;
  END IF;
  RETURN NEW;
END;
$$;

-- Имя на «b_»: после a_guard_* (те проверяют права до переноса).
DROP TRIGGER IF EXISTS b_split_order_private ON public.orders;
CREATE TRIGGER b_split_order_private
BEFORE INSERT OR UPDATE ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.split_order_private();

CREATE OR REPLACE FUNCTION public.get_order_safe(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order   public.orders;
  v_private public.order_private;
  v_uid     uuid := auth.uid();
  v_client  boolean;
  v_staff   boolean;
  v_crew    boolean;
  v_lead    boolean;
  v_result  jsonb;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id;
  IF v_order.id IS NULL OR v_uid IS NULL THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND';
  END IF;

  v_client := public.has_role('client') AND v_order.client_id = v_uid;
  v_staff  := COALESCE(public.current_user_role()::text, '') IN ('dispatcher', 'admin');
  v_crew   := EXISTS (SELECT 1 FROM public.order_takers
                      WHERE order_id = p_order_id AND porter_id = v_uid);
  v_lead   := EXISTS (SELECT 1 FROM public.order_takers
                      WHERE order_id = p_order_id AND porter_id = v_uid AND is_lead);

  -- Кто вообще может видеть заказ: участники, персонал, грузчики — открытые из ленты.
  IF NOT (v_client OR v_staff OR v_crew
          OR (public.has_role('porter') AND v_order.status = 'created')) THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND';
  END IF;

  SELECT * INTO v_private FROM public.order_private WHERE order_id = p_order_id;
  v_result := to_jsonb(v_order) - 'client_phone' - 'entrance';

  -- Телефон для связи: заказчик, персонал, назначенная бригада.
  IF v_client OR v_staff OR v_crew THEN
    v_result := v_result || jsonb_build_object('client_phone', v_private.client_phone);
  END IF;
  -- Подъезд: заказчик, персонал, старший — после «Начали».
  IF v_client OR v_staff
     OR (v_lead AND v_order.status IN ('in_progress', 'completed')) THEN
    v_result := v_result || jsonb_build_object('entrance', v_private.entrance);
  END IF;

  RETURN v_result;
END;
$$;
REVOKE ALL ON FUNCTION public.get_order_safe(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_order_safe(uuid) TO authenticated;
