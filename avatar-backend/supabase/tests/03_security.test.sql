-- pgTAP: регрессия на находки аудита 15.11.2026 (миграция 20261115120000).
BEGIN;
SELECT plan(12);

-- Пользователи: client, porter, второй client.
INSERT INTO auth.users (id, email, phone, encrypted_password, email_confirmed_at, created_at, updated_at, raw_user_meta_data)
VALUES
  ('00000000-0000-0000-0000-0000000000a1', 'c1@test.local', '+79990000011', '', now(), now(), now(), '{}'),
  ('00000000-0000-0000-0000-0000000000a2', 'p1@test.local', '+79990000012', '', now(), now(), now(), '{}'),
  -- C1: попытка зарегистрироваться админом через user_metadata
  ('00000000-0000-0000-0000-0000000000a3', 'evil@test.local', '+79990000013', '', now(), now(), now(), '{"role":"admin"}');

UPDATE public.profiles SET role = 'porter' WHERE id = '00000000-0000-0000-0000-0000000000a2';

INSERT INTO public.orders (id, client_id, address_from, address_to, price, status)
VALUES ('20000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a1', 'A', 'B', 1000, 'created');

-- C1
SELECT is(
  (SELECT role::text FROM public.profiles WHERE id = '00000000-0000-0000-0000-0000000000a3'),
  'client',
  'C1: role=admin из user_metadata игнорируется'
);

-- C3: anon не видит служебные таблицы
SET LOCAL role TO anon;
SELECT throws_ok($$ SELECT * FROM public.sms_codes $$, '42501', NULL, 'C3: anon не читает sms_codes');
SELECT throws_ok($$ SELECT * FROM public.orders $$,    '42501', NULL, 'C3: anon не читает orders');
RESET role;

-- C3: authenticated не читает sms_codes
SET LOCAL role TO authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';
SELECT throws_ok($$ SELECT * FROM public.sms_codes $$, '42501', NULL, 'C3: authenticated не читает sms_codes');

-- C2: самоповышение через add_role
SELECT throws_ok($$ SELECT public.add_role('admin') $$, '42501', NULL, 'C2: add_role(admin) запрещён');

-- C4: нельзя менять баланс/роль в своём профиле
SELECT throws_ok(
  $$ UPDATE public.profiles SET balance = 999999 WHERE id = '00000000-0000-0000-0000-0000000000a1' $$,
  '42501', NULL, 'C4: balance менять нельзя');
SELECT throws_ok(
  $$ UPDATE public.profiles SET role = 'admin' WHERE id = '00000000-0000-0000-0000-0000000000a1' $$,
  '42501', NULL, 'C4: role менять нельзя');
SELECT lives_ok(
  $$ UPDATE public.profiles SET full_name = 'Иван' WHERE id = '00000000-0000-0000-0000-0000000000a1' $$,
  'C4: full_name менять можно');

-- C5: заказчик не меняет цену, но может отменить
SELECT throws_ok(
  $$ UPDATE public.orders SET price = 1 WHERE id = '20000000-0000-0000-0000-0000000000a1' $$,
  '42501', NULL, 'C5: price менять нельзя');
SELECT lives_ok(
  $$ UPDATE public.orders SET status = 'cancelled' WHERE id = '20000000-0000-0000-0000-0000000000a1' $$,
  'C5: заказчик может отменить свой заказ');

-- H1: грузчик не может самозачислиться в бригаду
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-0000000000a2","role":"authenticated"}';
SELECT throws_ok(
  $$ INSERT INTO public.order_takers (order_id, porter_id) VALUES ('20000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a2') $$,
  NULL, NULL, 'H1: прямой INSERT в order_takers запрещён');

SELECT * FROM finish();
ROLLBACK;
