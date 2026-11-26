-- Оплата заказов — как компания работает сейчас (avagruz.ru, «Ответы на вопросы»):
-- наличными, переводом (100% предоплата) или безналом по счёту для организаций.
-- Онлайн-эквайринга пока нет: значение 'online' зарезервировано под ЮKassa
-- (docs/payments.md) и до подключения недоступно для выбора.
--
-- Заказчик выбирает способ при создании заказа. Отметку «оплачено» ставит только
-- диспетчер/админ (RPC set_order_payment). Заказчик не может создать заказ сразу
-- «оплаченным», а менять поля оплаты прямым UPDATE ему не даёт guard_order_update
-- (белый список полей — новые колонки защищены автоматически).

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS payment_method text NOT NULL DEFAULT 'cash'
    CHECK (payment_method IN ('cash', 'transfer', 'invoice', 'online')),
  ADD COLUMN IF NOT EXISTS payment_status text NOT NULL DEFAULT 'unpaid'
    CHECK (payment_status IN ('unpaid', 'paid', 'refunded')),
  ADD COLUMN IF NOT EXISTS paid_amount numeric(10, 2)
    CHECK (paid_amount IS NULL OR paid_amount >= 0),
  ADD COLUMN IF NOT EXISTS paid_at timestamptz,
  ADD COLUMN IF NOT EXISTS payment_marked_by uuid
    REFERENCES public.profiles(id) ON DELETE SET NULL;

CREATE OR REPLACE FUNCTION public.guard_order_insert_payment()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF current_user IN ('authenticated', 'anon')
     AND COALESCE(public.current_user_role()::text, '') NOT IN ('dispatcher', 'admin') THEN
    IF NEW.payment_method = 'online' THEN
      RAISE EXCEPTION 'VALIDATION_FAILED: Онлайн-оплата пока недоступна.';
    END IF;
    NEW.payment_status    := 'unpaid';
    NEW.paid_amount       := NULL;
    NEW.paid_at           := NULL;
    NEW.payment_marked_by := NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS a_guard_order_insert_payment ON public.orders;
CREATE TRIGGER a_guard_order_insert_payment
BEFORE INSERT ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.guard_order_insert_payment();

CREATE OR REPLACE FUNCTION public.set_order_payment(
  p_order_id uuid,
  p_status   text,
  p_amount   numeric DEFAULT NULL,
  p_method   text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF public.current_user_role() IS NULL
     OR public.current_user_role() NOT IN ('dispatcher', 'admin') THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: dispatcher or admin only' USING ERRCODE = '42501';
  END IF;
  IF p_status NOT IN ('unpaid', 'paid', 'refunded') THEN
    RAISE EXCEPTION 'VALIDATION_FAILED: Неизвестный статус оплаты.';
  END IF;
  IF p_method IS NOT NULL AND p_method NOT IN ('cash', 'transfer', 'invoice') THEN
    RAISE EXCEPTION 'VALIDATION_FAILED: Неизвестный способ оплаты.';
  END IF;
  IF p_amount IS NOT NULL AND (p_amount < 0 OR p_amount > 10000000) THEN
    RAISE EXCEPTION 'VALIDATION_FAILED: Проверьте сумму.';
  END IF;

  UPDATE public.orders
  SET payment_status    = p_status,
      payment_method    = COALESCE(p_method, payment_method),
      paid_amount       = CASE WHEN p_status = 'paid' THEN COALESCE(p_amount, price) END,
      paid_at           = CASE WHEN p_status = 'paid' THEN now() END,
      payment_marked_by = auth.uid()
  WHERE id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.set_order_payment(uuid, text, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_order_payment(uuid, text, numeric, text) TO authenticated;
