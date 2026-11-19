-- pgTAP: чек-лист п. 3 — фото заказов приватные (миграция 20261119120000).
BEGIN;
SELECT plan(4);

INSERT INTO auth.users (id, email, phone, encrypted_password, email_confirmed_at, created_at, updated_at, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-0000000000b1', 's1@test.local', '+79990000021', '', now(), now(), now(), '{}');
INSERT INTO public.orders (id, client_id, address_from, address_to, price, status)
VALUES ('20000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b1', 'A', 'B', 1000, 'created');

SELECT is((SELECT public FROM storage.buckets WHERE id = 'orders'), false,
  'бакет orders приватный');

SELECT lives_ok($$
  INSERT INTO public.messages (order_id, author_id, text, attachment_url)
  VALUES ('20000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b1', 'ok',
          'storage://orders/20000000-0000-0000-0000-0000000000b1/1.jpg') $$,
  'вложение из папки своего заказа — можно');

SELECT throws_ok($$
  INSERT INTO public.messages (order_id, author_id, text, attachment_url)
  VALUES ('20000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b1', 'x',
          'https://evil.example/pixel.png') $$,
  '23514', NULL, 'внешняя ссылка во вложении — нельзя');

SELECT throws_ok($$
  INSERT INTO public.messages (order_id, author_id, text, attachment_url)
  VALUES ('20000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b1', 'x',
          'storage://orders/20000000-0000-0000-0000-0000000000ff/1.jpg') $$,
  '23514', NULL, 'фото чужого заказа — нельзя');

SELECT * FROM finish();
ROLLBACK;
