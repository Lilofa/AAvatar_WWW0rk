# Безопасность — отчёт аудита и чек-лист (15.11.2026)

Аудит кода репозитория: SQL-миграции и RLS, edge-функции, Flutter-клиент (Android/iOS), CI.
Исправления — в ветке `claude/security-ios`. **Живой прод я не трогал** — миграцию нужно
накатить вам (сначала на staging).

## Что было найдено и исправлено

| # | Серьёзность | Находка | Исправление |
|---|---|---|---|
| C1 | 🔴 Критично | Любой мог зарегистрироваться `admin`/`dispatcher`: `verify-sms` клал `role` из запроса в `user_metadata`, `handle_new_user` слепо кастовал | Роль из запроса — только `client`/`porter` (и в edge-функции, и в триггере БД) |
| C2 | 🔴 Критично | `add_role('admin')` + `switch_role('admin')` — самоповышение до админа | `add_role` принимает только `client`/`porter` |
| C3 | 🔴 Критично | RLS не включён на 7 таблицах (в т.ч. `sms_codes`), `anon` имел `GRANT ALL` ⇒ публичный ключ из APK читал **коды входа** и мог войти за любого | RLS на всех таблицах, `anon` лишён прав в `public`, `sms_codes` только `service_role` |
| C4 | 🔴 Критично | Пользователь мог напрямую поменять в профиле `balance`, `rating`, `roles`, `pool`, `phone` | Триггер `guard_profile_update` |
| C5 | 🔴 Критично | Клиент/грузчик могли напрямую менять `price`, `status`, `porter_id` заказа | Триггер `guard_order_update`, лишние политики удалены |
| H1 | 🟠 Высоко | Прямые INSERT в `order_takers`/`order_stages`/`order_responses`/`reviews` обходили RPC (самозачисление в бригаду, накрутка рейтинга) | Политики удалены; запись только через RPC/триггеры |
| H2 | 🟠 Высоко | `anon` вызывал любые функции; кроновые/триггерные доступны клиентам | `REVOKE` с `anon`/`PUBLIC`, служебные функции закрыты |
| H3 | 🟠 Высоко | Любой вошедший читал **все** профили (телефоны, баланс) | Видны: свой, персонал, участники общих заказов, приглашённые (`can_view_profile`) |
| H4 | 🟠 Высоко | SMS: нет rate-limit (SMS-бомбинг, счёт за SMS), перебор кода сбросом через повторную отправку, `Math.random` | Кулдаун 60 с, 5/час на номер, 20/час на IP; атомарный счётчик попыток; CSPRNG; в БД хранится **хеш** кода |
| H5 | 🟠 Высоко | `listUsers()` — только первая страница: после ~50 пользователей вход ломался | Поиск по `profiles` |
| M1 | 🟡 Средне | Листинг всех фото заказов любым пользователем | `SELECT` по `storage.objects` — только участникам |
| M2 | 🟡 Средне | CORS `*`, тексты внутренних ошибок уходили клиенту; `search-address` — открытый прокси | CORS по allowlist, обезличенные ошибки, `search-address` только для вошедших, лимит длины |
| M3 | 🟡 Средне | Токены сессии в открытых SharedPreferences | Keychain / Android Keystore |
| M4 | 🟡 Средне | Release без `--dart-define` стартовал на mock («вход любым кодом»); release мог подписаться debug-ключом | Релиз без конфига показывает ошибку; Gradle прерывает release без `key.properties` |
| M5 | 🟡 Средне | Android: бэкап данных, cleartext, пользовательские CA | `allowBackup=false`, только HTTPS, system CA |
| L1 | 🟢 Низко | Sentry мог слать PII; вложения чата по любым схемам; шаблон `.env.migration` в git; workflows без `permissions` | `sendDefaultPii=false`, только `https`, шаблон → `.env.migration.example`, `permissions: contents: read` |

## Что нужно сделать вам (не делается кодом)

1. **Накатить на staging, прогнать сквозной тест (R6), потом на прод:**
   `supabase db push` и `supabase functions deploy`. Проверка: `supabase test db`
   (добавлен `03_security.test.sql`).
2. **Задать секреты edge-функций:** `supabase secrets set SMS_CODE_PEPPER=<случайные 32+ символа>`
   и `ALLOWED_ORIGINS=` (пусто — если веб-версии нет). Мобильным приложениям CORS не нужен.
3. **Dashboard → Authentication:** выключить *Allow new users to sign up*, *Anonymous sign-ins*,
   *Email provider → Enable Email Signup*; включить *Refresh token rotation*. (В `config.toml`
   это уже стоит, но прод-проект на Supabase Cloud настраивается в Dashboard.)
4. **Проверить, не эксплуатировали ли дыры на проде** (миграция лечит, но не откатывает ущерб):
   ```sql
   -- посторонние админы/диспетчеры:
   SELECT id, phone, role, roles, created_at FROM profiles
   WHERE role IN ('admin','dispatcher') OR roles && ARRAY['admin','dispatcher'] ORDER BY created_at;
   -- подозрительные балансы/рейтинги:
   SELECT id, phone, balance, rating FROM profiles WHERE balance > 0 ORDER BY balance DESC LIMIT 20;
   ```
5. **Ротация ключей**, если репозиторий когда-либо был публичным: `service_role`/secret-ключ,
   ключ SMS.ru, ключ Google-сервис-аккаунта. (В README уже упоминалась — сделайте раньше всего.)
   Репозиторий — Private.
6. **GitHub:** защита ветки `main` (PR + review), включить Dependabot и Secret scanning.

## Остаточные риски (осознанно не менял)

- **`price` при создании заявки задаёт клиент**; итог пересчитывает триггер `check_order_filled`
  при одобрении — убедитесь, что пересчёт покрывает все пути (проверить с Матвеем).
- **Вход по SMS** — слабое звено по определению (перехват SIM). Следующий шаг — лимиты по
  устройству/капча на отправку и уведомление о входе с нового устройства.
- **Фото заказов**: бакет `orders` публичный (прямые ссылки по неугадываемому пути работают).
  Для полной приватности — приватный бакет и подписанные URL (потребует правок клиента).
- **`pubspec.lock` не в git** (`*.lock` в `.gitignore`): версии зависимостей плавают между
  сборками. Для воспроизводимых релизов закоммитьте lock-файл после `flutter pub get`.
- **Obfuscation**: `--obfuscate --split-debug-info=...` не включал (ломает читаемость
  Sentry-стектрейсов без загрузки символов). Включайте вместе с загрузкой символов.
- `profiles_gen_referral_code` — триггерная функция, а клиент вызывает её как RPC
  (`ensureReferralCode`): это не уязвимость, но кнопка «Получить код» упадёт — к Матвею.
