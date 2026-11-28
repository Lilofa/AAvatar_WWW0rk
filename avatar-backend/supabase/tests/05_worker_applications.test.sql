-- pgTAP: регистрация только заказчиком, грузчик — через заявку (миграция 20261126120000).
BEGIN;
SELECT plan(9);

INSERT INTO auth.users (id, email, phone, encrypted_password, email_confirmed_at, created_at, updated_at, raw_user_meta_data)
VALUES
  ('00000000-0000-0000-0000-0000000000c1', 'w1@test.local', '+79990000031', '', now(), now(), now(), '{"role":"porter"}'),
  ('00000000-0000-0000-0000-0000000000c2', 'd1@test.local', '+79990000032', '', now(), now(), now(), '{}');
UPDATE public.profiles SET role = 'dispatcher' WHERE id = '00000000-0000-0000-0000-0000000000c2';

SELECT is((SELECT role::text FROM public.profiles WHERE id = '00000000-0000-0000-0000-0000000000c1'),
  'client', 'role=porter из user_metadata игнорируется: регистрация только заказчиком');

SET LOCAL role TO authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}';

SELECT throws_ok($$ SELECT public.add_role('porter') $$, '42501', NULL,
  'add_role(porter) запрещён');
SELECT throws_ok($$ INSERT INTO public.worker_applications(user_id, full_name, city)
                    VALUES ('00000000-0000-0000-0000-0000000000c1', 'X', 'Томск') $$,
  '42501', NULL, 'прямая запись заявки запрещена');
SELECT lives_ok($$ SELECT public.submit_worker_application('Иван Петров', 'Томск', '2 года') $$,
  'заявка через RPC');
SELECT throws_ok($$ SELECT public.submit_worker_application('Иван Петров', 'Томск') $$,
  'P0001', NULL, 'вторая заявка, пока первая на рассмотрении, — нельзя');
SELECT throws_ok($$ SELECT public.review_worker_application(
                      (SELECT id FROM public.worker_applications LIMIT 1), true) $$,
  '42501', NULL, 'одобрить свою заявку нельзя');
SELECT is(public.has_role('porter'), false, 'до одобрения — не грузчик');

SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-0000000000c2","role":"authenticated"}';
SELECT lives_ok($$ SELECT public.review_worker_application(
                     (SELECT id FROM public.worker_applications
                      WHERE user_id = '00000000-0000-0000-0000-0000000000c1'), true) $$,
  'диспетчер одобряет');

SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}';
SELECT ok(public.has_role('porter') AND public.has_role('client'),
  'после одобрения — и заказчик, и грузчик');

SELECT * FROM finish();
ROLLBACK;
