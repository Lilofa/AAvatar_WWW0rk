# R3/R6 — финальная сборка 1.0.0 под прод (31.10.2026)

Прод-контур Матвея: Supabase Cloud, проект `qkcxfnfyjdesmaotsmya`.
Код приложения не знает, где живёт бэкенд: меняются только два `--dart-define`.

## 1. Что поправлено в этой поставке (обязательно до сборки)

| Файл | Проблема | Фикс |
|---|---|---|
| `avatar-front/lib/data/supabase/supabase_orders_repository.dart` | GoTrue прода (v2.197.0) на `POST /auth/v1/verify` с `{type, phone, token_hash}` отвечает **400 `validation_failed: Only the token_hash and type should be provided`** → вход по SMS падал бы на первом же шаге | `verifyOTP(type: magiclink, tokenHash: ...)` — **без `phone`** |
| `avatar-front/android/app/src/main/AndroidManifest.xml` | В main-манифесте не было `INTERNET` (он был только в debug/profile) → **release-APK не делает ни одного сетевого запроса**; плюс label «avatar_app» | Добавлены `INTERNET`, `ACCESS_NETWORK_STATE`; label = «Аватар» |

Проверено агентом на живом проде (без ключа сервис-роли, только publishable):
`/auth/v1/verify` с `phone+token_hash` → 400; только `token_hash+type` → 403 `otp_expired`
(т.е. формат принят, ошибка уже про сам токен). Отсюда и фикс.

## 2. Сборка APK (PowerShell, машина Артёма)

```powershell
cd D:\dev\projects\avatar-repo\avatar-front
flutter pub get
flutter test --concurrency=1

$env:SUP_URL = "https://qkcxfnfyjdesmaotsmya.supabase.co"
$env:SUP_KEY = "sb_publishable_0_qZm0Tiucge5W6vSnNBgA_4cHP4eve"

# keystore — ОДИН РАЗ, ДО первой release-сборки (иначе APK подписан debug-ключом
# и в сторы его нельзя; gradle молча падает на debug-подпись, если key.properties нет)
# keytool -genkeypair -v -keystore D:\keys\avatar-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias avatar
# copy android\key.properties.example android\key.properties  → заполнить (путь без пробелов)

flutter build apk --release -t lib/main_sentry.dart `
  --dart-define=SUPABASE_URL=$env:SUP_URL `
  --dart-define=SUPABASE_ANON_KEY=$env:SUP_KEY
# Sentry DSN не передаём, пока Матвей/Коля не создадут проект (R5):
# main_sentry.dart без SENTRY_DSN работает как обычный main.dart.
# Для Play Console/RuStore тем же составом: flutter build appbundle --release -t lib/main_sentry.dart ...
```

Контроль подписи и версии:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\build-tools\<версия>\apksigner.bat" verify --print-certs build\app\outputs\flutter-apk\app-release.apk
# ожидаем: CN=..., OU=... — НЕ «CN=Android Debug»
Get-Item build\app\outputs\flutter-apk\app-release.apk | Select-Object Name,Length,LastWriteTime
```

Проверка, что в бинарник зашит именно ПРОД (а не staging `djbtzyezhfnxberzliwc`):

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
$z=[IO.Compression.ZipFile]::OpenRead("build\app\outputs\flutter-apk\app-release.apk")
$e=$z.Entries | Where-Object {$_.FullName -like "*libapp.so"} | Select-Object -First 1
$ms=New-Object IO.MemoryStream; $s=$e.Open(); $s.CopyTo($ms); $s.Close()
$txt=[Text.Encoding]::ASCII.GetString($ms.ToArray()); $z.Dispose()
if ($txt -match "qkcxfnfyjdesmaotsmya") { "OK: прод-URL в бинарнике" } else { "НЕТ ПРОД-URL — dart-define не доехал!" }
if ($txt -match "djbtzyezhfnxberzliwc") { "ВНИМАНИЕ: внутри staging-URL" } else { "OK: staging-URL отсутствует" }
```

## 3. Порядок действий (R6-0 сквозной тест)

1. **Матвей**: прогнать `avatar-backend/sql/01_prod_rpc_diag.sql` → на проде не хватает
   14 RPC и 9 триггерных функций (см. README Матвею в zip). Пока это не закрыто,
   в приложении не работает НИЧЕГО, кроме экрана входа: логин падает на триггере
   `handle_new_user`, расчёт стоимости — на `quote_order_detailed`, отклик — на
   `respond_to_order`.
2. **Матвей**: `02_auth_smoke.sql` — вложить тестовый код в `sms_codes` (не жжём sms.ru)
   и убедиться, что пользователь + профиль создаются.
3. **Артём**: собрать APK по п.2, поставить на телефон, прогнать заказ целиком:
   заявка → расчёт → отклик грузчика → одобрение диспетчера → этапы → чат с фото →
   закрытие → отзыв. Каждый шаг сверять SQL-ом по `docs/matvey-live-run.md` §4.
4. Только после зелёного R6-0 — AAB в сторы (R4) и отключение VK-ботов (решение бизнесмена).

## 4. Открытые блокеры (не моя зона, но держу на виду)

- **152-ФЗ**: прод встал на Supabase Cloud (Ирландия/ЕС), а не на Яндекс-ВМ, как
  решали 20.09. `docs/legal/privacy-policy.md` и `team-site/privacy.html` сейчас
  утверждают хранение в РФ → перед подачей в сторы текст надо привести в
  соответствие с фактом (или всё-таки поднять ВМ). Решение — за бизнесменом.
- **Иконка приложения** — дефолтная Flutter (`mipmap-*/ic_launcher.png`), label был
  «avatar_app». Label починен, иконки из `store/` в android-ресурсы не переложены:
  для сторов нужен `flutter_launcher_icons` или ручная раскладка 5 dpi.
- **Sentry DSN** для R5/R3-сборок в сторы.
- Секреты в чат не кидаем: publishable-ключ — публичный по природе (он и так в APK),
  но `service_role` и пароль БД — только офлайн/в менеджере паролей.
