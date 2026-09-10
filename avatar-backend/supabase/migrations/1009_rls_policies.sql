-- =============================================
-- Включаем RLS
-- =============================================
ALTER TABLE public.profiles  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reviews   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

-- =============================================
-- profiles
-- =============================================
DROP POLICY IF EXISTS "profiles_select_authenticated" ON public.profiles;
CREATE POLICY "profiles_select_authenticated"
ON public.profiles FOR SELECT
TO authenticated
USING (true);

DROP POLICY IF EXISTS "profiles_insert_self" ON public.profiles;
CREATE POLICY "profiles_insert_self"
ON public.profiles FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;
CREATE POLICY "profiles_update_own"
ON public.profiles FOR UPDATE
TO authenticated
USING (auth.uid() = id)
WITH CHECK (
  auth.uid() = id
  AND role       = (SELECT role       FROM public.profiles WHERE id = auth.uid())
  AND is_blocked = (SELECT is_blocked FROM public.profiles WHERE id = auth.uid())
);

-- =============================================
-- orders
-- =============================================
DROP POLICY IF EXISTS "orders_select_porter" ON public.orders;
CREATE POLICY "orders_select_porter"
ON public.orders FOR SELECT
TO authenticated
USING (
  public.current_user_role() = 'porter'
  AND (porter_id = auth.uid() OR status = 'created')
);

DROP POLICY IF EXISTS "orders_select_client" ON public.orders;
CREATE POLICY "orders_select_client"
ON public.orders FOR SELECT
TO authenticated
USING (
  public.current_user_role() = 'client'
  AND client_id = auth.uid()
);

DROP POLICY IF EXISTS "orders_select_admin" ON public.orders;
CREATE POLICY "orders_select_admin"
ON public.orders FOR SELECT
TO authenticated
USING (public.current_user_role() IN ('dispatcher', 'admin'));

DROP POLICY IF EXISTS "orders_insert_client" ON public.orders;
CREATE POLICY "orders_insert_client"
ON public.orders FOR INSERT
TO authenticated
WITH CHECK (
  public.current_user_role() = 'client'
  AND client_id = auth.uid()
  AND status = 'created'
  AND porter_id IS NULL
);

DROP POLICY IF EXISTS "orders_accept_porter" ON public.orders;
CREATE POLICY "orders_accept_porter"
ON public.orders FOR UPDATE
TO authenticated
USING (
  public.current_user_role() = 'porter'
  AND status = 'created'
  AND porter_id IS NULL
)
WITH CHECK (
  porter_id = auth.uid()
  AND status IN ('accepted', 'cancelled')
);

DROP POLICY IF EXISTS "orders_update_own_porter" ON public.orders;
CREATE POLICY "orders_update_own_porter"
ON public.orders FOR UPDATE
TO authenticated
USING (
  public.current_user_role() = 'porter'
  AND porter_id = auth.uid()
)
WITH CHECK (porter_id = auth.uid());

DROP POLICY IF EXISTS "orders_cancel_own_client" ON public.orders;
CREATE POLICY "orders_cancel_own_client"
ON public.orders FOR UPDATE
TO authenticated
USING (
  public.current_user_role() = 'client'
  AND client_id = auth.uid()
  AND status IN ('created', 'accepted')
)
WITH CHECK (client_id = auth.uid());

-- =============================================
-- reviews
-- =============================================
DROP POLICY IF EXISTS "reviews_select_all" ON public.reviews;
CREATE POLICY "reviews_select_all"
ON public.reviews FOR SELECT
TO authenticated
USING (true);

DROP POLICY IF EXISTS "reviews_insert_client" ON public.reviews;
CREATE POLICY "reviews_insert_client"
ON public.reviews FOR INSERT
TO authenticated
WITH CHECK (
  auth.uid() = author_id
  AND EXISTS (
    SELECT 1 FROM public.orders o
    WHERE o.id = order_id
      AND o.client_id = auth.uid()
      AND o.status = 'completed'
  )
);

-- =============================================
-- audit_log
-- =============================================
DROP POLICY IF EXISTS "audit_select_admin" ON public.audit_log;
CREATE POLICY "audit_select_admin"
ON public.audit_log FOR SELECT
TO authenticated
USING (public.current_user_role() = 'admin');
