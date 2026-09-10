BEGIN;
SELECT plan(6);

-- =============================================
-- Подготовка: 3 пользователя (client, porter, dispatcher)
-- =============================================
INSERT INTO auth.users (id, email, phone, encrypted_password, email_confirmed_at, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000000001', 'client@test.local', '+79990000001', '', now(), now(), now()),
  ('00000000-0000-0000-0000-000000000002', 'porter@test.local', '+79990000002', '', now(), now(), now()),
  ('00000000-0000-0000-0000-000000000003', 'disp@test.local',   '+79990000003', '', now(), now(), now());

UPDATE public.profiles SET role = 'client'     WHERE id = '00000000-0000-0000-0000-000000000001';
UPDATE public.profiles SET role = 'porter'     WHERE id = '00000000-0000-0000-0000-000000000002';
UPDATE public.profiles SET role = 'dispatcher' WHERE id = '00000000-0000-0000-0000-000000000003';

INSERT INTO public.orders (id, client_id, address_from, address_to, price, status)
VALUES
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'A', 'B', 1000, 'created'),
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'C', 'D', 2000, 'completed');

-- =============================================
-- Тест 1: грузчик видит свободные заказы
-- =============================================
SET LOCAL role TO authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}';
SELECT isnt_empty(
  $$ SELECT * FROM public.orders WHERE status = 'created' $$,
  'Porter sees free orders'
);

-- =============================================
-- Тест 2: грузчик не видит чужие завершенные
-- =============================================
SELECT is_empty(
  $$ SELECT * FROM public.orders WHERE status = 'completed' $$,
  'Porter cannot see others completed orders'
);

-- =============================================
-- Тест 3: заказчик видит только свои
-- =============================================
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';
SELECT isnt_empty(
  $$ SELECT * FROM public.orders WHERE client_id = '00000000-0000-0000-0000-000000000001' $$,
  'Client sees own orders'
);

-- =============================================
-- Тест 4: диспетчер видит все
-- =============================================
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000003","role":"authenticated"}';
SELECT isnt_empty(
  $$ SELECT * FROM public.orders $$,
  'Dispatcher sees all orders'
);

-- =============================================
-- Тест 5: заказчик не может создать заказ на другого
-- =============================================
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';
SELECT throws_ok(
  $$ INSERT INTO public.orders (client_id, address_from, address_to, price)
     VALUES ('00000000-0000-0000-0000-000000000002', 'X', 'Y', 100) $$,
  'new row violates row-level security policy for table "orders"',
  'Client cannot create order for another user'
);

-- =============================================
-- Тест 6: audit_log недоступен грузчику
-- =============================================
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}';
SELECT is_empty(
  $$ SELECT * FROM public.audit_log $$,
  'Porter cannot read audit_log'
);

SELECT * FROM finish();
ROLLBACK;
