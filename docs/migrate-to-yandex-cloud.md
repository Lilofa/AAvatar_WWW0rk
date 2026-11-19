# Переезд с облачного Supabase на свой сервер в Yandex Cloud

Редакция 19.11.2026. Цель: база, вход, файлы и edge-функции работают на нашем VPS
в Yandex Cloud (регион `ru-central1`, серверы в России — так выполняется требование
152-ФЗ о хранении данных в РФ). За облачный Supabase больше не платим и не зависим от
того, что бесплатный проект засыпает через неделю без запросов.

**Как:** Supabase — открытый проект, его целиком (база, вход, файлы, realtime,
edge-функции, панель Studio) можно поднять на своём сервере через Docker. Приложение
менять не нужно: при сборке меняются только `SUPABASE_URL` и ключ.

⏱ Работа: 2–3 дня. Простой для пользователей: 30–60 минут в момент переключения.

---

## 0. Проверить сервер

| Что | Минимум | Лучше |
|---|---|---|
| Процессор | 2 ядра | 4 |
| Память | **4 ГБ** | 8 ГБ |
| Диск | 40 ГБ SSD | 80 ГБ |
| Система | Ubuntu 22.04/24.04 | — |
| Регион | `ru-central1` (Россия) | — |

Это официальный минимум Supabase для самостоятельного размещения. На 2 ГБ стек
стабильно не работает. Посмотрите в консоли Yandex Cloud, сколько памяти у нашего VPS
за 4 352,77 ₽, и при необходимости увеличьте его.

Ещё понадобится **домен** (например `api.avatar-app.ru`), направленный на IP сервера:
приложение должно ходить по HTTPS.

## 1. Подготовить VPS

```bash
# Docker и Compose
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER   # перелогиниться после этого

# Файрвол: наружу только SSH и HTTPS
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

В группе безопасности Yandex Cloud тоже оставьте открытыми только 22, 80 и 443.
**Порт базы 5432 и панель Studio наружу не открывать.**

## 2. Поднять Supabase на сервере

По официальной инструкции «Self-Hosting with Docker» (ссылка внизу; команды в ней
могут немного меняться между версиями — сверяйтесь с ней):

```bash
git clone --depth 1 https://github.com/supabase/supabase
mkdir ~/avatar-supabase
cp -rf supabase/docker/* ~/avatar-supabase/
cp supabase/docker/.env.example ~/avatar-supabase/.env
cd ~/avatar-supabase

# Сгенерировать пароли и ключи (НЕ оставлять значения из .env.example!)
sh utils/generate-keys.sh
```

В `.env` проверить и заполнить:

| Переменная | Значение |
|---|---|
| `POSTGRES_PASSWORD`, `JWT_SECRET`, `ANON_KEY`, `SERVICE_ROLE_KEY` | из `generate-keys.sh` |
| `DASHBOARD_USERNAME`, `DASHBOARD_PASSWORD` | свои, сложный пароль |
| `SITE_URL`, `API_EXTERNAL_URL`, `SUPABASE_PUBLIC_URL` | `https://api.avatar-app.ru` |
| `ENABLE_EMAIL_SIGNUP`, `ENABLE_PHONE_SIGNUP` | `false` (пользователей создаёт только `verify-sms`) |
| `ENABLE_ANONYMOUS_USERS` | `false` |

```bash
docker compose pull
docker compose up -d
docker compose ps        # все сервисы должны быть healthy
```

**HTTPS.** Поставить перед Supabase обратный прокси с сертификатом Let's Encrypt —
проще всего Caddy:

```
# /etc/caddy/Caddyfile
api.avatar-app.ru {
    reverse_proxy localhost:8000
}
```

`sudo apt install caddy && sudo systemctl reload caddy` — сертификат выпустится сам.
Студию открывать только через SSH-туннель:
`ssh -L 8000:localhost:8000 user@сервер` → http://localhost:8000.

## 3. Перенести базу (схема, пользователи, данные)

Нужна строка подключения к **облачной** базе: Supabase Dashboard → Project Settings →
Database → Connection string (режим Session). Дальше на своём компьютере с
установленным Supabase CLI:

```bash
OLD="postgresql://postgres.<ref>:<пароль>@<host>:5432/postgres"

supabase db dump --db-url "$OLD" -f roles.sql  --role-only
supabase db dump --db-url "$OLD" -f schema.sql
supabase db dump --db-url "$OLD" -f data.sql   --use-copy --data-only
```

`data.sql` содержит и пользователей (`auth.users`) — после переезда люди входят
по тому же номеру, их профили, заказы и чаты на месте.

Загрузка на новый сервер (через SSH-туннель к порту 5432 сервера):

```bash
NEW="postgresql://postgres:<POSTGRES_PASSWORD>@localhost:5432/postgres"

psql "$NEW" --single-transaction -v ON_ERROR_STOP=1 \
  -f roles.sql -f schema.sql \
  -c 'SET session_replication_role = replica' \
  -f data.sql
```

Если на облаке ещё **не накатаны** миграции безопасности (`20261115…`, `20261116…`),
накатите их на новом сервере сразу после загрузки:

```bash
supabase db push --db-url "$NEW"   # из папки avatar-backend/supabase
```

Проверка: `supabase test db --db-url "$NEW"` — все тесты зелёные, в том числе
`03_security.test.sql`.

## 4. Перенести файлы (фото заказов, аватары)

Бакеты `orders` и `avatars` создаются миграцией. Сами файлы скачать со старого
проекта и залить на новый (Supabase CLI, команды `storage`):

```bash
supabase storage cp -r ss:///orders  ./backup/orders  --experimental   # со старого (linked) проекта
supabase storage cp -r ss:///avatars ./backup/avatars --experimental
# затем переключить CLI на новый сервер и залить обратно:
supabase storage cp -r ./backup/orders  ss:///orders  --experimental
supabase storage cp -r ./backup/avatars ss:///avatars --experimental
```

Ссылки на фото в сообщениях чата содержат адрес старого проекта. После переноса
заменить его в базе:

```sql
UPDATE public.messages
SET attachment_url = replace(attachment_url,
      'https://<старый-ref>.supabase.co', 'https://api.avatar-app.ru')
WHERE attachment_url LIKE 'https://<старый-ref>.supabase.co%';
```

## 5. Перенести edge-функции

```bash
cp -r avatar-backend/supabase/functions/* ~/avatar-supabase/volumes/functions/
```

Секреты функций — в `.env` сервера (и прокинуть их в сервис `functions` в
`docker-compose.yml`, раздел `environment`):

| Секрет | Зачем |
|---|---|
| `SMSRU_API_KEY` | отправка SMS |
| `SMS_CODE_PEPPER` | хеш кодов входа (случайная строка 32+ символа) |
| `ALLOWED_ORIGINS` | пусто, если нет веб-версии |
| `TEST_LOGIN_PHONES`, `TEST_LOGIN_CODE` | только номер для ревьюеров магазинов |

`docker compose restart functions`, затем проверить:
`curl -X POST https://api.avatar-app.ru/functions/v1/send-sms -H "apikey: <ANON_KEY>" -d '{"phone":"123"}'`
→ ответ `Invalid phone format` (значит функция жива).

## 6. Переключить приложение

1. **Объявить окно** (например ночью), чтобы никто не создавал заказы.
2. Сделать финальный `data.sql` со старого проекта и загрузить (шаг 3) — данные
   свежие на момент переключения.
3. Собрать приложение с новыми адресом и ключом:
   ```bash
   flutter build apk --release -t lib/main_sentry.dart \
     --dart-define=SUPABASE_URL=https://api.avatar-app.ru \
     --dart-define=SUPABASE_ANON_KEY=<ANON_KEY с нового сервера>
   ```
   В `BUILD-release-apk.ps1` и `BUILD-ios.sh` заменить `SUPABASE_URL`/ключ, в GitHub →
   Settings → Secrets обновить `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
   `STAGING_SUPABASE_*`.
4. Проверить на телефоне: вход по SMS, лента, отклик, чат с фото, выход.
5. Старый облачный проект **не удалять** ещё 1–2 недели (откат), но поставить на паузу
   приём новых пользователей. Потом — удалить и вместе с ним данные за рубежом.

## 7. После переезда: бэкапы и обновления

- **Ежедневный бэкап** базы в Yandex Object Storage (тоже в России):
  ```bash
  # /etc/cron.daily/avatar-backup
  docker exec supabase-db pg_dump -U postgres -Fc postgres \
    > /backup/avatar-$(date +%F).dump
  # + загрузка в Object Storage через aws-cli/s3cmd и удаление копий старше 30 дней
  ```
  Раз в месяц пробовать восстановить бэкап на тестовую базу.
- **Обновления**: `docker compose pull && docker compose up -d` раз в месяц, после
  бэкапа; обновлять Ubuntu (`unattended-upgrades`).
- **Доступ**: SSH только по ключам, вход по паролю выключить; ключ
  `SERVICE_ROLE_KEY` и пароль базы — у 1–2 человек.
- **Мониторинг**: хотя бы оповещение Yandex Cloud о загрузке CPU/памяти/диска.

## Что обновить в документах после переезда

- `docs/legal/privacy-policy.md` и согласие (`consent_text.dart`): хостинг — Yandex
  Cloud, Россия.
- `docs/legal/compliance-checklist.md`: пункт «Хранение данных в России» — выполнен.
- Таблица бюджета: строка «Сервер — свой VPS» — подключён.

## Источники

- [Self-Hosting with Docker — документация Supabase](https://supabase.com/docs/guides/self-hosting/docker)
- [How to Self-Host Supabase: The Parts the Docker Compose Skips](https://learnwithhasan.com/guide/self-host-supabase/)
- [Self-host Supabase on Ubuntu VPS — MassiveGRID](https://massivegrid.com/blog/self-host-supabase-ubuntu-vps)
