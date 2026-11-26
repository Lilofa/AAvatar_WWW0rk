-- pgTAP: B2 — телефон и подъезд не видны всем грузчикам (миграция 20261126140000).
BEGIN;
SELECT plan(6);

INSERT INTO auth.users (id, email, phone, encrypted_password, email_confirmed_at, created_at, updated_at, raw_user_meta_data)
VALUES
  ('00000000-0000-0000-0000-0000000000b7', 'oc@test.local', '+79990000051', '', now(), now(), now(), '{}'),
  ('00000000-0000-0000-0000-0000000000b8', 'op@test.local', '+79990000052', '', now(), now(), now(), '{}'),
  ('00000000-0000-0000-0000-0000000000b9', 'ox@test.local', '+79990000053', '', now(), now(), now(), '{}');
UPDATE public.profiles SET role = 'porter', roles = ARRAY['porter'] WHERE id = '00000000-0000-0000-0000-0000000000b8';

SET LOCAL role TO authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-0000000000b7","role":"authenticated"}';
INSERT INTO public.orders (id, client_id, address_from, address_to, price, status, client_phone, entrance)
VALUES ('40000000-0000-0000-0000-0000000000b7', '00000000-0000-0000-0000-0000000000b7', 'A', 'B', 1000, 'created', '+79991112233', 4);
SELECT is(public.get_order_safe('40000000-0000-0000-0000-0000000000b7')->>'client_phone', '+79991112233',
  'заказчик видит свой телефон для связи');
SELECT throws_ok($$ SELECT * FROM public.order_private $$, '42501', NULL,
  'прямого доступа к order_private нет');

SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-0000000000b8","role":"authenticated"}';
SELECT is((SELECT client_phone FROM public.orders WHERE id = '40000000-0000-0000-0000-0000000000b7'), NULL,
  'в ленте грузчика телефона нет');
SELECT ok(NOT (public.get_order_safe('40000000-0000-0000-0000-0000000000b7') ? 'client_phone'),
  'грузчик не из бригады не получает телефон');
SELECT ok(NOT (public.get_order_safe('40000000-0000-0000-0000-0000000000b7') ? 'entrance'),
  'и подъезд');

SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-0000000000b9","role":"authenticated"}';
SELECT throws_ok($$ SELECT public.get_order_safe('40000000-0000-0000-0000-0000000000b7') $$,
  'P0001', NULL, 'чужой заказчик не открывает заказ по id');

SELECT * FROM finish();
ROLLBACK;
