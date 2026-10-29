# ЗАПУСК MVP С ЖИВОЙ БД — РАНБЭК ДЛЯ МАТВЕЯ (20.09.2026)

Ветка: `artem/flutter-app` (коммит `7b34eaf` и новее). Фронт готов полностью:
логин по SMS, лента, отклик с ETA, пульт диспетчера, этапы, чат, закрытие,
отзыв, визард заявки. Твоя часть: поднять бэкенд и verifying по SQL на каждом шаге.

## 0. Предпосылки
- Docker Desktop запущен; Supabase CLI: `supabase -v` (нет — `npm i -g supabase`).
- Flutter 3.47+ (`flutter --version`).

## 1. Бэкенд (локально)
```powershell
cd <repo>\avatar-backend\supabase
supabase start
supabase status
```
Из `supabase status` нужны: **API URL** (`http://127.0.0.1:54321`) и **anon key**.

Контроль миграций (последняя — `20260920120000_fixes_for_artem`):
```powershell
supabase migration list
```

Edge-функции деплоим БЕЗ проверки JWT (их зовёт аноним: логин, адрес):
```powershell
supabase functions deploy send-sms --no-verify-jwt
supabase functions deploy verify-sms --no-verify-jwt
supabase functions deploy search-address --no-verify-jwt
```

SMS.ru не обязательна: `send-sms` сначала кладёт код в `public.sms_codes`
и только потом стучится в sms.ru. Без `SMSRU_API_KEY` отправка падает, код остаётся в БД.

Realtime-публикация (лента/этапы/чат едут на ней):
```sql
select tablename from pg_publication_tables where pubname = 'supabase_realtime';
-- ожидаем: orders, order_responses, order_stages, order_takers, messages, ...
```

## 2. Роли для прогона
Роль ставится чипом при ПЕРВОЙ регистрации в приложении («Я заказчик» / «Я грузчик»).
Диспетчера навешиваем SQL-ом (Studio `http://127.0.0.1:54323` → SQL Editor):
```sql
update public.profiles set roles = roles || '{dispatcher}' where phone = '+7999...';
```
После этого у пользователя появляется вкладка «Диспетчер» (перезапустить приложение).

## 3. Приложения (по окну на роль)
```powershell
cd <repo>\avatar-front
# грузчик
flutter run -d windows --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_ANON_KEY=<anon key>
# заказчик
flutter run -d chrome --web-port=5555 --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_ANON_KEY=<anon key>
```
Вход: телефон → «Получить код» (ошибка на экране = норма, sms.ru нет) →
Studio → Table Editor → `sms_codes` → взять `code` своего номера → ввести.

## 4. Сценарий + SQL-проверка каждого шага
| Шаг в UI | Что проверить в SQL |
|---|---|
| Заказчик: визард → «Создать заявку» | `select id, status, price, urgency, transport, people_count, planned_duration_min from public.orders order by created_at desc limit 1;` → status=`created`, price=0 |
| Грузчик: «Откликнуться · указать ETA» | `select porter_id, eta_minutes, status from public.order_responses order by created_at desc limit 1;` → `pending` |
| Диспетчер: ✔ одобрить | `select status from public.orders where id=...;` → `accepted`; `select porter_id, is_lead from public.order_takers where order_id=...;` → грузчик стал старшим; **триггер пересчитал цену**: `select price from public.orders where id=...;` → > 0 (quote_order) |
| Грузчик: этапы departed→arrived→started→finished | `select stage, created_at from public.order_stages where order_id=... order by created_at;` |
| Грузчик: чат по заказу | `select author_id, text, created_at from public.messages where order_id=...;` |
| Грузчик: finished + обратная связь | `select status, result_comment, went_well from public.orders where id=...;` → `completed` |
| Заказчик: «Оценить» → 5 звёзд | `select rating, text from public.reviews where order_id=...;` и `select rating, completed_count from public.profiles where id=<грузчик>;` → рейтинг пересчитан |
| Диспетчер: «Закрыть принудительно» | `select status, force_closed, result_comment from public.orders where id=...;` → `completed`, `true` |

Нюансы бизнес-правил (не баги):
- `woke` доступен только утренним заказам (старт 4:00–12:00 НСК);
- `started`/`finished`/`feedback` жмёт только старший (при одном грузчике он старший);
- ориентир «Номер подъ-да» скрыт RLS до этапа `started`;
- обратная связь старшего — окно 5 минут после `finished` (pg_cron ставит `feedback_missed`).

## 5. Если что-то не так
- `403 / PERMISSION_DENIED` → `select phone, role, roles from public.profiles;`
- Ошибка RPC в снакбаре → текст = машинный код из RAISE EXCEPTION Матвея.
- Логи функций: `supabase functions logs send-sms` / `verify-sms`.
- Лента не обновляется без pull-to-refresh → проверка публикации realtime (п.1).
- Всё время в Asia/Novosibirsk; часовой пояс машины не важен (конвертация в мапперах).

## 6. Staging (когда локальный прогон зелёный)
```powershell
supabase link --project-ref <ref staging>
supabase db push
supabase functions deploy send-sms --no-verify-jwt   # и остальные две
```
Дальше те же команды запуска, но с URL/ключом staging — так можно дать
потыкать команде и начальнику вне локальной сети (см. docs/boss-demo.md).

---

## 7. SENTRY (прод-QA, добавил Артём 30.09)
1. DSN: sentry.io → Create Project → Flutter → скопировать DSN
   (вида https://...@o....ingest.sentry.io/...). Храним как секрет:
   GitHub Actions secrets SENTRY_DSN + локально НЕ в репо.
2. Прод-сборки идут через ОТДЕЛЬНУЮ точку входа с мониторингом:
   flutter build apk --release -t lib/main_sentry.dart \
     --dart-define=SUPABASE_URL=<prod url> \
     --dart-define=SUPABASE_ANON_KEY=<prod publishable> \
     --dart-define=SENTRY_DSN=<dsn>
   flutter build web -t lib/main_sentry.dart --dart-define=... (аналогично)
3. Без SENTRY_DSN main_sentry.dart ведёт себя как обычный main.dart;
   тесты, mock-стенд и dev-сборки мониторинг не тянут ВООБЩЕ
   (sentry изолирован в main_sentry.dart + sentry_sink.dart).
4. Что прилетает в Sentry: краши виджетов (SentryWidget), ошибки слоя
   данных с тегом layer=data/data-stream; validation и unauthorized —
   только breadcrumbs (не шумим пользовательскими ошибками).
5. Примечание по железу: на машинах с 1 ГБ RAM flutter analyze падает
   с OOM на графе sentry — analyze гоняем на дев-машинах, в CI и в
   песочнице агента тесты идут с --concurrency=1.
