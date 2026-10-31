-- =====================================================================
-- ПРОД — СКВОЗНОЙ СМОУК АВТОРИЗАЦИИ (R6-0, шаг 1) без расходов на sms.ru
-- Делаем до того, как Артём поставит APK на телефон.
-- =====================================================================

-- 1. Вложить тестовый код для своего номера (5 минут жизни).
--    Колонки по миграции 20260910120400: phone, code, expires_at, attempts.
insert into public.sms_codes (phone, code, expires_at, attempts)
values ('+79XXXXXXXXX', '246810', now() + interval '5 minutes', 0)
on conflict (phone) do update
  set code = excluded.code,
      expires_at = excluded.expires_at,
      attempts = 0;

-- 2. В приложении: экран входа → этот номер → «Получить код».
--    ЭКРАН МОЖЕТ ПОКАЗАТЬ ОШИБКУ ОТПРАВКИ — это норма, если sms.ru не достучалась:
--    send-sms сначала пишет код в sms_codes и только потом дёргает sms.ru.
--    Код уже лежит в таблице (проверить: select * from public.sms_codes;).
--    Вводим 246810 → роль «Я заказчик» → должны попасть в ленту.

-- 3. Контроль, что пользователь и профиль создались (профиль делает триггер
--    on_auth_user_created → public.handle_new_user):
select id, phone, role, full_name, created_at
from public.profiles
order by created_at desc
limit 5;

-- 4. Если в приложении ошибка «не удалось войти» / 500 — смотрим, что именно:
--    Dashboard → Logs → Edge Functions (verify-sms) и Logs → Auth.
--    Варианты: (а) нет триггера/функции handle_new_user → createUser падает;
--              (б) нет грантов на профиля → select после логина пустой;
--              (в) клиент шлёт phone вместе с token_hash → 400 validation_failed
--                  (исправлено в этой поставке фронта, нужен APK из фикса).

-- 5. Роль диспетчера для прогона пульта (после первого входа):
update public.profiles
set roles = roles || '{dispatcher}'
where phone = '+79XXXXXXXXX';
-- (если в проде колонка role, а не roles — см. ШАГ 4 диагностики и правь под факт)

-- 6. Уборка после смоука:
delete from public.sms_codes where code = '246810';
-- тестового юзера удаляем в Dashboard → Authentication → Users (или оставляем
-- как боевой аккаунт команды — тогда шаг 6 не нужен).

-- 7. Реальные SMS: проверить баланс sms.ru и имя отправителя ДО того, как
--    приложение начнут ставить живые заказчики (R2.6 ранбука).
