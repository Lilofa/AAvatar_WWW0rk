-- =============================================
-- RLS-политики для order_responses, order_takers, order_stages,
-- messages, order_locations, device_tokens.
-- =============================================

-- order_responses
DROP POLICY IF EXISTS "responses_select_porter_own" ON public.order_responses;
CREATE POLICY "responses_select_porter_own"
ON public.order_responses FOR SELECT TO authenticated
USING (
  porter_id = auth.uid()
  OR EXISTS (SELECT 1 FROM public.orders o WHERE o.id = order_id AND o.client_id = auth.uid())
  OR public.current_user_role() IN ('dispatcher', 'admin')
);

DROP POLICY IF EXISTS "responses_insert_porter" ON public.order_responses;
CREATE POLICY "responses_insert_porter"
ON public.order_responses FOR INSERT TO authenticated
WITH CHECK (
  porter_id = auth.uid()
  AND public.current_user_role() = 'porter'
  AND EXISTS (SELECT 1 FROM public.orders o WHERE o.id = order_id AND o.status = 'created')
);

DROP POLICY IF EXISTS "responses_delete_own" ON public.order_responses;
CREATE POLICY "responses_delete_own"
ON public.order_responses FOR DELETE TO authenticated
USING (porter_id = auth.uid() AND status = 'pending');

DROP POLICY IF EXISTS "responses_update_dispatcher" ON public.order_responses;
CREATE POLICY "responses_update_dispatcher"
ON public.order_responses FOR UPDATE TO authenticated
USING (public.current_user_role() IN ('dispatcher', 'admin'))
WITH CHECK (public.current_user_role() IN ('dispatcher', 'admin'));

-- order_takers
DROP POLICY IF EXISTS "takers_select_participants" ON public.order_takers;
CREATE POLICY "takers_select_participants"
ON public.order_takers FOR SELECT TO authenticated
USING (
  porter_id = auth.uid()
  OR EXISTS (SELECT 1 FROM public.orders o WHERE o.id = order_id AND o.client_id = auth.uid())
  OR public.current_user_role() IN ('dispatcher', 'admin')
);

DROP POLICY IF EXISTS "takers_insert_system" ON public.order_takers;
CREATE POLICY "takers_insert_system"
ON public.order_takers FOR INSERT TO authenticated
WITH CHECK (
  porter_id = auth.uid()
  OR public.current_user_role() IN ('dispatcher', 'admin')
);

-- order_stages
DROP POLICY IF EXISTS "stages_select_participants" ON public.order_stages;
CREATE POLICY "stages_select_participants"
ON public.order_stages FOR SELECT TO authenticated
USING (
  porter_id = auth.uid()
  OR EXISTS (SELECT 1 FROM public.orders o WHERE o.id = order_id AND o.client_id = auth.uid())
  OR public.current_user_role() IN ('dispatcher', 'admin')
);

DROP POLICY IF EXISTS "stages_insert_own" ON public.order_stages;
CREATE POLICY "stages_insert_own"
ON public.order_stages FOR INSERT TO authenticated
WITH CHECK (porter_id = auth.uid());

-- messages
DROP POLICY IF EXISTS "messages_select_participants" ON public.messages;
CREATE POLICY "messages_select_participants"
ON public.messages FOR SELECT TO authenticated
USING (
  EXISTS (SELECT 1 FROM public.order_takers WHERE order_id = messages.order_id AND porter_id = auth.uid())
  OR public.current_user_role() IN ('dispatcher', 'admin')
);

DROP POLICY IF EXISTS "messages_insert_participants" ON public.messages;
CREATE POLICY "messages_insert_participants"
ON public.messages FOR INSERT TO authenticated
WITH CHECK (
  auth.uid() = author_id
  AND (
    EXISTS (SELECT 1 FROM public.order_takers WHERE order_id = messages.order_id AND porter_id = auth.uid())
    OR public.current_user_role() IN ('dispatcher', 'admin')
  )
);

-- order_locations
DROP POLICY IF EXISTS "locations_select_participants" ON public.order_locations;
CREATE POLICY "locations_select_participants"
ON public.order_locations FOR SELECT TO authenticated
USING (
  public.current_user_role() IN ('dispatcher', 'admin')
  OR porter_id = auth.uid()
);

DROP POLICY IF EXISTS "locations_insert_own" ON public.order_locations;
CREATE POLICY "locations_insert_own"
ON public.order_locations FOR INSERT TO authenticated
WITH CHECK (auth.uid() = porter_id);

-- device_tokens
DROP POLICY IF EXISTS "device_tokens_select_own" ON public.device_tokens;
CREATE POLICY "device_tokens_select_own"
ON public.device_tokens FOR SELECT TO authenticated
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "device_tokens_insert_own" ON public.device_tokens;
CREATE POLICY "device_tokens_insert_own"
ON public.device_tokens FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "device_tokens_delete_own" ON public.device_tokens;
CREATE POLICY "device_tokens_delete_own"
ON public.device_tokens FOR DELETE TO authenticated
USING (auth.uid() = user_id);

-- Realtime publication
DO $$
DECLARE
  v_table text;
  v_tables text[] := ARRAY[
    'orders', 'order_responses', 'order_takers', 'order_stages',
    'messages', 'reviews', 'profiles', 'order_locations'
  ];
BEGIN
  FOREACH v_table IN ARRAY v_tables LOOP
    BEGIN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', v_table);
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;
  END LOOP;
END $$;
