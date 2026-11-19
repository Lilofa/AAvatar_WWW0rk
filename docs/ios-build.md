# Сборка iOS-приложения

iOS собирается **только на macOS с Xcode** (ограничение Apple). С Windows/Linux — через
GitHub Actions (`.github/workflows/ios-build.yml`, раннер `macos-15`) или на любом Mac.

Что уже настроено в проекте (`avatar-front/ios`):

| Что | Значение |
|---|---|
| Bundle ID | `ru.avatar.avatarApp` |
| Минимальная iOS | 15.0 (проект Xcode) |
| Имя на экране | «Аватар» |
| Разрешения | фото (`NSPhotoLibraryUsageDescription`), камера — тексты на русском |
| Сеть | только HTTPS (ATS без исключений) |
| Экспорт-комплаенс | `ITSAppUsesNonExemptEncryption = false` (только стандартный HTTPS) |
| Privacy manifest | `Runner/PrivacyInfo.xcprivacy` (обязателен для App Store) |
| Сессия входа | Keychain (`flutter_secure_storage`), не SharedPreferences |
| Зависимости | Swift Package Manager (CocoaPods не нужен) |
| Ориентация | iPhone — портрет; iPad — все |

## Разово (нужен платный Apple Developer Program, $99/год)

1. **App ID.** developer.apple.com → Certificates, IDs → Identifiers → `ru.avatar.avatarApp`.
2. **Запись приложения.** appstoreconnect.apple.com → My Apps → «+» → New App
   (bundle ID из шага 1, язык — русский).
3. **Подпись.** Проще всего автоматическая: откройте `avatar-front/ios/Runner.xcworkspace`
   в Xcode → Runner → Signing & Capabilities → Team → ваш → «Automatically manage signing».
   Скопируйте `ios/ExportOptions.plist.example` → `ios/ExportOptions.plist`, впишите Team ID
   (Apple Developer → Membership).

## Сборка на Mac

```bash
export SUPABASE_ANON_KEY='<publishable-ключ прод-проекта>'
./BUILD-ios.sh
```

Скрипт прогоняет тесты и собирает `build/ios/ipa/*.ipa` с боевым
`SUPABASE_URL` (по умолчанию прод `qkcxfnfyjdesmaotsmya`; staging — `SUPABASE_URL=...`).
Без `SUPABASE_URL/ANON_KEY` release-сборка **не запустится** на mock-данных, а покажет экран
«Сборка не настроена» — так сделано специально (иначе вход принимал бы любой код).

Загрузка в TestFlight: приложение **Transporter** (перетащить `.ipa`) или
`xcrun altool --upload-app ...` (см. конец скрипта).

## Через GitHub Actions (без своего Mac)

PR в `main`/`develop` автоматически: тесты + сборка без подписи (проверка, что iOS собирается).
Подписанный `.ipa` — вручную: Actions → «iOS build» → Run workflow (или тег `ios-v1.0.0`).

Секреты репозитория (Settings → Secrets and variables → Actions):

| Секрет | Что это |
|---|---|
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | прод-адрес и publishable-ключ |
| `IOS_DIST_CERT_P12_BASE64`, `IOS_DIST_CERT_PASSWORD` | сертификат Apple Distribution (`base64 -i cert.p12`) |
| `IOS_PROVISION_PROFILE_BASE64`, `IOS_PROVISION_PROFILE_NAME` | App Store профиль для `ru.avatar.avatarApp` |
| `IOS_TEAM_ID`, `IOS_KEYCHAIN_PASSWORD` | Team ID; любой случайный пароль временной связки ключей |
| `APP_STORE_CONNECT_API_KEY_ID`, `…_ISSUER_ID`, `…_API_KEY_P8` | *необязательно*: автозагрузка в TestFlight |

Создайте окружение `ios-release` (Settings → Environments) и включите «Required reviewers» —
тогда подписанная сборка не стартует без вашего одобрения.

## Проверка перед релизом

- [ ] Вход по SMS, лента, отклик, чат с фото (проверяет доступ к фото) на **реальном iPhone**.
- [ ] Версия: `pubspec.yaml` → `version: 1.0.0+N`; номер сборки `N` растёт при каждой загрузке.
- [ ] Скриншоты и описание в App Store Connect; ссылки на политику и условия:
      `docs/legal/privacy-policy.md`, `docs/legal/terms-of-use.md` (нужен публичный URL —
      например страницы из `team-site/`).
- [ ] Вопросы анкеты «App Privacy» совпадают с `PrivacyInfo.xcprivacy`
      (телефон, имя, фото — для работы приложения; сбои — Sentry, без привязки к пользователю).

> Не проверялось в этой поставке: сборка на macOS (в среде разработки Xcode нет). Plist-файлы
> и `project.pbxproj` проверены на валидность, тесты Dart проходят; первую сборку на Mac
> стоит сделать до подачи в App Store и прислать лог, если Xcode что-то не примет.
