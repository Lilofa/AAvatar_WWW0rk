-- =============================================
-- Storage buckets для Avatar
-- =============================================

-- Создаём бакеты (публичные для чтения, чтобы фронт мог отображать без токена)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  ('avatars', 'avatars', true, 5242880,
   ARRAY['image/jpeg','image/png','image/webp']),
  ('orders', 'orders', true, 10485760,
   ARRAY['image/jpeg','image/png','image/webp'])
ON CONFLICT (id) DO NOTHING;

-- =============================================
-- RLS на storage.objects для avatars
-- =============================================
DROP POLICY IF EXISTS "avatars_public_read" ON storage.objects;
CREATE POLICY "avatars_public_read"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'avatars');

DROP POLICY IF EXISTS "avatars_insert_own" ON storage.objects;
CREATE POLICY "avatars_insert_own"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'avatars'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

DROP POLICY IF EXISTS "avatars_update_own" ON storage.objects;
CREATE POLICY "avatars_update_own"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'avatars'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

DROP POLICY IF EXISTS "avatars_delete_own" ON storage.objects;
CREATE POLICY "avatars_delete_own"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'avatars'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- =============================================
-- RLS на storage.objects для orders
-- Путь: orders/<order_id>/<filename>
-- =============================================
DROP POLICY IF EXISTS "orders_public_read" ON storage.objects;
CREATE POLICY "orders_public_read"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'orders');

DROP POLICY IF EXISTS "orders_insert_participants" ON storage.objects;
CREATE POLICY "orders_insert_participants"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'orders'
  AND (
    -- Заказчик своего заказа
    EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id::text = (storage.foldername(name))[1]
        AND o.client_id = auth.uid()
    )
    OR
    -- Грузчик в бригаде
    EXISTS (
      SELECT 1 FROM public.order_takers ot
      WHERE ot.order_id::text = (storage.foldername(name))[1]
        AND ot.porter_id = auth.uid()
    )
    OR
    -- Диспетчер/админ
    public.current_user_role() IN ('dispatcher', 'admin')
  )
);

DROP POLICY IF EXISTS "orders_delete_own" ON storage.objects;
CREATE POLICY "orders_delete_own"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'orders'
  AND (
    EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id::text = (storage.foldername(name))[1]
        AND o.client_id = auth.uid()
    )
    OR public.current_user_role() IN ('dispatcher', 'admin')
  )
);
