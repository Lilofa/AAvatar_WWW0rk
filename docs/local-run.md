# ЛОКАЛЬНЫЙ ЗАПУСК MVP «АВАТАР» (Артём + Матвей, 20.09.2026)

Цель: поднять приложение с живым бэкендом и пройти MVP-цикл руками:
заявка → отклик с ETA → одобрение → этапы → чат → закрытие → отзыв.

Приложение: `avatar-front`. Бэкенд: `avatar-backend/supabase` (Матвей).
Три варианта запуска, от простого к полному.

---

## Вариант A. MOCK-режим (без бэкенда, 1 минута) — посмотреть UI

```powershell
cd D:\dev\projects\avatar-repo\avatar-front
flutter run -d windows        # или: -d chrome
```

Без `--dart-define` приложение стартует на `MockOrdersRepository`.
Вход: любой телефон, любой код КРОМЕ `0000` (0000 = ошибка для теста error-состояний).
Mock-профиль = грузчик + диспетчер → вкладки «Лента» и «Диспетчер».

Что тыкается: лента, отклик с ETA, одобрение/отклонение откликов в пульте,
форс-закрытие с комментарием, чат по заказу, отзыв, визард создания заявки.
Данные не сохраняются между перезапусками. Годится для демо UI и ревью экранов.

---

## Вариант B. ЛОКАЛЬНЫЙ SUPABASE (полноценный прогон с БД)

Нужно: Docker Desktop (запущен) + Supabase CLI (`supabase -v`; ставится:
`npm i -g supabase` или `scoop install supabase`).

### 1. Поднять бэкенд
```powershell
cd D:\dev\projects\avatar-repo\avatar-backend\supabase
supabase start
```
Ждать 1–3 минуты: поднимутся PostgREST, GoTrue, Storage, Edge-рантайм;
ВСЕ миграции (включая `20260920120000_fixes_for_artem.sql`) накатятся сами.

```powershell
supabase status
```
Скопировать: **API URL** (`http://127.0.0.1:54321`) и **anon key** (длинный JWT).

### 2. Задеплоить edge-функции БЕЗ проверки JWT
(их вызывает анонимный клиент: логин и поиск адреса)
```powershell
supabase functions deploy send-sms --no-verify-jwt
supabase functions deploy verify-sms --no-verify-jwt
supabase functions deploy search-address --no-verify-jwt
```

### 3. СМС без ключа sms.ru
`send-sms` сначала кладёт код в таблицу `public.sms_codes`, и только потом
пытается отправить через sms.ru. Без ключа `SMSRU_API_KEY` отправка падает,
НО код уже лежит в БД. Поэтому:

1. В приложении нажать «Получить код» (получим ошибку — это нормально).
2. Открыть Supabase Studio: `http://127.0.0.1:54323` → Table Editor → `sms_codes`.
3. Скопировать `code` для своего телефона и ввести в приложении.

Альтернатива (без нажатия «Получить код»): вставить код самому:
```sql
insert into public.sms_codes (phone, code, attempts, expires_at)
values ('+79990001111', '1234', 0, now() + interval '10 minutes')
on conflict (phone) do update
  set code = '1234', attempts = 0, expires_at = now() + interval '10 minutes';
```
(тогда в приложении НЕ нажимать «Получить код» — он удаляет старые коды.)

### 4. Запустить приложения (по окну на роль)
```powershell
# грузчик
flutter run -d windows --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_ANON_KEY=<anon key>
# заказчик (второе окно, chrome на своём порту)
flutter run -d chrome --web-port=5555 --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_ANON_KEY=<anon key>
```
Роль выбирается ЧИПОМ при первой регистрации («Я заказчик» / «Я грузчик»).
Диспетчера проще сделать из своего же грузчика через SQL (Studio → SQL Editor):
```sql
update public.profiles set roles = roles || '{dispatcher}' where phone = '+7999...';
```
После этого в том же окне появится вкладка «Диспетчер» (перезайти в приложение).

### 5. Сценарий прогона (чек-лист)
1. **Заказчик**: вход → «Мои заказы» → FAB «+» → визард: адрес (начать вводить
   «Ленина» — подскажет Nominatim), время (будущее!), люди, длительность ≥30,
   наименование, срочность, транспорт → «Рассчитать тариф» (строки из
   `quote_order_detailed`) → «Создать заявку» → экран «Заявка создана».
2. **Грузчик**: в ленте появилась заявка → «Откликнуться · указать ETA» →
   ETA 15 → на карточке чип «Отклик отправлен».
3. **Диспетчер**: вкладка «Диспетчер» → карточка заказа → отклик с ETA →
   ✔ (одобрить). Заказ перейдёт в `accepted`, грузчик попадёт в бригаду.
4. **Грузчик**: заказ в ленте ведёт на активный заказ (тап по карточке):
   этапы `departed → arrived → started → finished` (woke — только для утренних
   заказов 4:00–12:00 НСК; started/finished жмёт старший — при одном грузчике
   он старший автоматически). Кнопка чата в шапке — чат по заказу.
   После `finished` — обратная связь (Да/Нет + комментарий, окно 5 минут).
5. **Заказчик**: «Мои заказы» → завершённый → «Оценить» → 5 звёзд + текст →
   «Отправить отзыв».
6. **Проверка в БД** (Studio → SQL Editor):
```sql
select status, price, force_closed, result_comment from public.orders;
select stage, created_at from public.order_stages order by created_at;
select rating, text from public.reviews;
select rating, completed_count from public.profiles;   -- рейтинг пересчитан
select * from public.messages;                          -- чат
```

### 6. Если что-то сломалось
- Ошибка в приложении — снакбар/баннер с русским текстом (AppFailure): по нему
  обычно понятно, RPC это или RLS.
- `403 / PERMISSION_DENIED` → смотри роль в `profiles.roles` и `active_role`.
- Функции: `supabase functions logs send-sms` / `verify-sms`.
- Реалтайм не ездит (лента не обновляется) → проверь, что публикация
  `supabase_realtime` включает таблицы (миграция 20260912120100 это делает).
- Часы/дедлайны: всё считается в Asia/Novosibirsk; на машине грузчика часовой
  пояс может быть любой — конвертация в мапперах.

---

## Вариант C. ОБЛАЧНЫЙ STAGING (если у Матвея накатано)
Если Матвей подтвердит, что staging-проект (`djbtzyezhfnxberzliwc`) содержит
миграции и задеплоенные функции — то же самое, но с облачными URL/ключом:
```powershell
flutter run -d windows --dart-define=SUPABASE_URL=https://djbtzyezhfnxberzliwc.supabase.co --dart-define=SUPABASE_ANON_KEY=<publishable key из Dashboard>
```
Код в СМС придёт по-настоящему (если на staging зашит `SMSRU_API_KEY`),
иначе — смотреть в `sms_codes` через Dashboard.

---

## Регрессия перед прогоном (2 минуты)
```powershell
cd avatar-front
flutter pub get
flutter test        # ждём +134: All tests passed
flutter analyze     # 0 замечаний
```
