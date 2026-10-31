README МАТВЕЮ — прод qkcxfnfyjdesmaotsmya (31.10.2026)
========================================================

Спасибо, контур поднят. Я прощупал прод снаружи (только publishable-ключ,
service_role не нужен) — и нашёл блокеры, из-за которых сквозной тест (R6)
не пройдёт. Ниже факты, потом что делать.

ЧТО УЖЕ РАБОТАЕТ ✅
-------------------
1. GoTrue жив: /auth/v1/health → v2.197.0.
2. Все 11 таблиц на месте и доступны по RLS (profiles, orders, order_responses,
   order_takers, order_stages, reviews, messages, order_locations,
   device_tokens, audit_log, sms_codes) — под анонимом возвращают [] (RLS держит).
3. Все 3 edge-функции задеплоены и отвечают:
     send-sms      {"phone":"123"}                    → 400 Invalid phone format
     verify-sms    {"phone":"+79000000000","code":..}  → 400 Code not found
     search-address{"query":"Новосибирск"}             → 200 + results (Nominatim/OSM)
4. Storage: бакеты order-photos / avatars / public отвечают (list → []).

ЧТО СЛОМАНО ❌ (блокер R6)
--------------------------
A. Функций public видно 6 из 35. Через publishable-ключ PostgREST отвечает
   PGRST202 «Could not find the function public.X» на:
     respond_to_order, quote_order_detailed, quote_order, get_stage_availability,
     mark_stage, submit_delay_reason, approve_response, decline_response,
     cancel_response, assign_lead, find_replacement, force_close_order,
     submit_review, finish_order, accept_order, advance_order_status,
     get_order_safe, switch_role, add_role, add_taker_on_approve,
     check_order_filled, orders_status_timestamps, reviews_recalc_rating,
     set_review_editable_until, set_updated_at, register_device_token,
     update_porter_location, profiles_gen_referral_code, handle_new_user.
   Видны только: get_pending_review_count, current_user_role,
   hide_entrance_before_started, auto_decline_stale_responses,
   cleanup_expired_sms_codes, process_order_deadlines.

   Из этого 14 функций зовёт клиент напрямую — то есть в приложении сейчас не
   работает расчёт стоимости, отклик грузчика, пульт диспетчера, этапы, отзыв.

B. handle_new_user — это функция триггера on_auth_user_created. Если её нет,
   admin.createUser внутри verify-sms падает → ЛОГИН НЕ РАБОТАЕТ ВООБЩЕ.
   Это первое, что упрётся в смоуке.

ДВЕ ВЕРОЯТНЫЕ ПРИЧИНЫ (проверяются одним запросом)
--------------------------------------------------
1. ГРАНТЫ. Миграции делают REVOKE ... FROM PUBLIC + GRANT ... TO authenticated,
   но часть функций гранта не получила; PostgREST не показывает роль функцию без
   EXECUTE — снаружи это выглядит ровно как PGRST202. Косвенное подтверждение:
   get_pending_review_count (грант TO authenticated в той же миграции
   20260912120200) — виден, а quote_order из ТОГО ЖЕ файла — нет.
2. MIGRATIONS ВСТАЛИ НЕ ДО КОНЦА. Тогда функций физически нет.

Что сделать (10 минут, SQL Editor):
  1) avatar-backend/sql/01_prod_rpc_diag.sql — покажет по каждой функции:
     есть ли она в pg_proc и есть ли EXECUTE у authenticated. Приложи вывод в чат.
  2) avatar-backend/sql/02_fix_grants_and_reload.sql — шаг B (массовый грант
     authenticated) + шаг C (notify pgrst, 'reload schema').
  3) ещё раз 01_. Если всё зелено — причина была в грантах/кэше.
  4) Если функций физически нет — `supabase link --project-ref
     qkcxfnfyjdesmaotsmya` + `supabase db push` и ПРИЛОЖИ ТЕКСТ ОШИБКИ:
     значит какая-то миграция падает на середине (тогда чиним её, а не гоним вслепую).
  5) avatar-backend/sql/03_auth_smoke.sql — вложить тестовый код в sms_codes
     и проверить создание профиля (не жжём sms.ru).

СО СВОЕЙ СТОРОНЫ Я ПОЧИНИЛ (уже в zip у Артёма)
-----------------------------------------------
GoTrue прода на POST /auth/v1/verify с телом {type, phone, token_hash} отвечает:
  400 {"error_code":"validation_failed",
       "msg":"Only the token_hash and type should be provided"}
Проверено вживую: {type, token_hash} → 403 otp_expired (формат принят),
добавил phone → 400. Фронт раньше слал phone вместе с tokenHash — вход по SMS
падал бы на первом шаге. Убрал phone из verifyOTP.

ВОПРОСЫ ТЕБЕ (не блокируют сборку APK)
--------------------------------------
1. Sentry DSN для прод-сборок? Пока собираем без него (main_sentry.dart без DSN
   = обычный main.dart), но для сторов (R4/R5) DSN нужен.
2. Крон на проде заведён (cron.job)? В диагностике ШАГ 5 — проверь, что
   process_order_deadlines / auto_decline_stale_responses / cleanup_expired_sms_codes
   в расписании, иначе дедлайны и авто-отклонение откликов не сработают.
3. Realtime-публикация: pg_publication_tables для supabase_realtime должна
   включать orders, order_responses, order_stages, order_takers, messages,
   profiles (лента/этапы/чат едут на ней). Диаagnostics ШАГ 3.
4. Бэкапы (R2.4): план включён? Провели учение восстановления на staging?
5. Данные из Google Sheets (R2.5) переносим на прод или стартуем чистыми?
   20.09 договаривались: старт чистыми, первый живой заказ = R6.
6. ЮРИДИКА. Прод встал на Supabase Cloud, а не на Яндекс-ВМ (решение от 20.09
   было «всё в РФ» из-за 152-ФЗ). docs/legal/privacy-policy.md и
   team-site/privacy.html сейчас обещают хранение в РФ — перед подачей в сторы
   текст надо привести в соответствие с фактом (или всё-таки поднять ВМ).
   Это решение бизнесмена, но в листинге Play/RuStore privacy policy проверяют.
7. Ключ, который ты кинул в чат, — publishable, он по природе публичный (и так
   будет лежать в APK), ротация не обязательна. А вот service_role и пароль БД —
   только офлайн/в менеджере паролей, в чат не кидаем (урок 20.09).
