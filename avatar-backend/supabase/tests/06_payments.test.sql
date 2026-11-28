-- pgTAP: оплата заказа (миграция 20261126130000_order_payments).
BEGIN;
SELECT plan(5);

INSERT INTO auth.users (id, email, phone, encrypted_password, email_confirmed_at, created_at, updated_at, raw_user_meta_data)
VALUES
  ('00000000-0000-0000-0000-0000000000f1', 'pc@test.local', '+79990000041', '', now(), now(), now(), '{}'),
  ('00000000-0000-0000-0000-0000000000f2', 'pd@test.local', '+79990000042', '', now(), now(), now(), '{}');
UPDATE public.profiles SET role = 'dispatcher' WHERE id = '00000000-0000-0000-0000-0000000000f2';

SET LOCAL role TO authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-0000000000f1","role":"authenticated"}';

INSERT INTO public.orders (id, client_id, address_from, address_to, price, status, payment_method, payment_status)
VALUES ('30000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000f1', 'A', 'B', 1500, 'created', 'transfer', 'paid');
SELECT is((SELECT payment_status FROM public.orders WHERE id = '30000000-0000-0000-0000-0000000000f1'),
  'unpaid', 'заказчик не может создать заказ сразу оплаченным');
SELECT throws_ok($$ INSERT INTO public.orders (client_id, address_from, address_to, price, status, payment_method)
                    VALUES ('00000000-0000-0000-0000-0000000000f1', 'A', 'B', 1, 'created', 'online') $$,
  'P0001', NULL, 'онлайн-оплата до подключения эквайринга недоступна');
SELECT throws_ok($$ UPDATE public.orders SET payment_status = 'paid'
                    WHERE id = '30000000-0000-0000-0000-0000000000f1' $$,
  '42501', NULL, 'заказчик не меняет статус оплаты напрямую');
SELECT throws_ok($$ SELECT public.set_order_payment('30000000-0000-0000-0000-0000000000f1', 'paid') $$,
  '42501', NULL, 'отметка оплаты — только диспетчер/админ');

SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-0000000000f2","role":"authenticated"}';
SELECT public.set_order_payment('30000000-0000-0000-0000-0000000000f1', 'paid');
SELECT is((SELECT payment_status || '/' || paid_amount FROM public.orders
           WHERE id = '30000000-0000-0000-0000-0000000000f1'),
  'paid/1500.00', 'диспетчер отмечает оплату, сумма по умолчанию = цена');

SELECT * FROM finish();
ROLLBACK;
