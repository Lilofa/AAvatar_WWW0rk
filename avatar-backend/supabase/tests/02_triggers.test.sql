BEGIN;
SELECT plan(3);

INSERT INTO auth.users (id, email, phone, encrypted_password, email_confirmed_at, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000000010', 'c2@test.local', '+79990000010', '', now(), now(), now()),
  ('00000000-0000-0000-0000-000000000011', 'p2@test.local', '+79990000011', '', now(), now(), now());

UPDATE public.profiles SET role = 'client' WHERE id = '00000000-0000-0000-0000-000000000010';
UPDATE public.profiles SET role = 'porter' WHERE id = '00000000-0000-0000-0000-000000000011';

-- =============================================
-- Тест 1: referral_code генерируется автоматически
-- =============================================
SELECT isnt_empty(
  $$ SELECT referral_code FROM public.profiles WHERE id = '00000000-0000-0000-0000-000000000010' $$,
  'Referral code generated'
);

-- =============================================
-- Тест 2: смена статуса пишется в audit_log
-- =============================================
INSERT INTO public.orders (id, client_id, address_from, address_to, price, status)
VALUES ('20000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000010', 'A', 'B', 1000, 'created');

UPDATE public.orders
SET porter_id = '00000000-0000-0000-0000-000000000011', status = 'accepted'
WHERE id = '20000000-0000-0000-0000-000000000001';

SELECT isnt_empty(
  $$ SELECT * FROM public.audit_log WHERE entity_id = '20000000-0000-0000-0000-000000000001' $$,
  'Status change logged in audit_log'
);

-- =============================================
-- Тест 3: рейтинг пересчитывается при отзыве
-- =============================================
INSERT INTO public.reviews (order_id, author_id, target_id, rating, text)
VALUES ('20000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000010',
        '00000000-0000-0000-0000-000000000011',
        5, 'Отлично');

SELECT is(
  (SELECT rating FROM public.profiles WHERE id = '00000000-0000-0000-0000-000000000011')::text,
  '5.00',
  'Porter rating updated after review'
);

SELECT * FROM finish();
ROLLBACK;
