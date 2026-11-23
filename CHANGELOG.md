# Changelog

What changed in the app, newest first. Each entry says what you will notice,
then what changed underneath. Updated with every new piece of work.

Try the latest demo in the browser (no install): see the "Аватар демо" artifact
link in the chat, or download the APK from GitHub → Actions → **Android beta APK**
→ latest green run → Artifacts.

## 2026-11-23

### Privacy policy: final text
- `docs/legal/privacy-policy.md` rewritten as a complete policy under 152-ФЗ
  art. 18.1: who we are, whose data, what exactly we collect (and what we
  don't), purposes with legal bases, who sees what inside the app, outside
  services with countries (SMS.ru, Yandex Cloud, Nominatim, Sentry, Netlify),
  cross-border transfer, security, retention periods, rights, account deletion.
- Checked against the code: the app has **no** push notifications or
  geolocation, so they are removed from the policy and the consent. Added what
  was missing: IP address for SMS limits, address search via OpenStreetMap,
  the website form on Netlify (USA).
- Login consent updated to match (version `2026-11-23`; users accept it again on
  the next login).
- Website page `team-site/privacy.html` regenerated from the new text (it still
  showed the September draft).
- Retention promise made true: expired SMS codes and the 30-day SMS log are now
  deleted automatically every hour (migration `20261123120000`).
- Only blanks left: operator name, INN/OGRN, address, e-mail, Roskomnadzor
  number. The comment at the top of the policy lists what must be done before
  it is published (move to the VPS, fix pentest issue B2, Sentry IP setting,
  account deletion in the app).

## 2026-11-19

### iPhone build works again in GitHub Actions
- GitHub retired the `macos-14` build machine, so the iOS build was cancelled
  in 1 second on every run. Switched to `macos-15`.
- Removed the unused CocoaPods `Podfile`: current Flutter gets all iPhone
  libraries via Swift Package Manager, and the leftover Podfile broke the build.

### Security checklist (12 items) — `docs/security-12-checklist.md`
- **Order photos are private now.** Before, anyone with a photo link could open
  it without logging in. Now the chat shows photos through 1-hour links that the
  server gives only to people in that order. A message can only attach a photo
  of its own order.
- **SMS spending cap**: at most `SMS_DAILY_LIMIT` SMS a day for the whole app
  (default 500), so bots can't drain the SMS.ru balance.
- Dependabot opens update PRs for Flutter, npm, Gradle and Actions; 3 Flutter
  packages patched; npm audit clean; all packages verified to exist.
- ⚠️ **Found: the repo is public and its old history contains the staging
  secret (`service_role`) key.** It must be revoked in Supabase now.

### Guide: move from Supabase cloud to our VPS in Yandex Cloud
- `docs/migrate-to-yandex-cloud.md`: self-hosted Supabase in Docker on the VPS,
  HTTPS, moving the database with users, files and edge functions, switching
  the app, backups. Satisfies the 152-ФЗ data-in-Russia requirement.

### Budget: own VPS, no Supabase bill
- We already have our own VPS (4 352,77 ₽ a month) and don't pay for
  Supabase, so the paid Supabase plan is gone from the budget and the server
  row shows the real VPS price (sheet, plan doc, `docs/release-plan.md`).
  Monthly cost is about 8 400–11 400 ₽: VPS plus SMS. To do: move the
  database to the VPS and check that it is located in Russia.

## 2026-11-18

### Budget spreadsheet for the client
- New Russian spreadsheet «Аватар — бюджет запуска» (Claude Sheets): costs by
  item with formulas — change the dollar rate, the intermediary fee or SMS
  logins per month and every total updates; second tab with the dates.

### Release plan and budget updated
- Budget now includes a **server in Russia** (required by the personal-data
  law, ~2 000–3 500 ₽/month) instead of Supabase Pro long-term, a lawyer, and
  the free Roskomnadzor notification. Copy in `docs/release-plan.md`.

### Demo you can open in the browser
- The demo app now runs on a web page in a phone frame, next to a short guide
  (how to log in, how to switch roles, what's new). No APK download needed.

### Demo role switcher
- Tap the red **«ДЕМО · роль»** strip at the top to become: all roles, client,
  porter, dispatcher or admin. Tabs change at once.
- Fixed: a real user with only one role (a plain client or dispatcher) crashed
  the main screen, because the bottom tab bar needs two tabs. One tab now shows
  without the bar; a user with no role sees a message.
- Fixed: cabinet cards overflowed on narrow phones.

### Logout, chat, consent (owner's bug reports)
- Fixed: in the demo the corner «ДЕМО» ribbon covered the **logout** and **chat**
  buttons. Replaced with a thin strip above the app.
- Chat is only for the client, the crew and dispatchers (same rule as the
  database). Others now see a clear explanation instead of «Недостаточно прав».
- Login asks for **consent to personal-data processing** (152-ФЗ) before the
  phone number is sent. The server stores when and which version was accepted.
- Privacy policy draft fixed; new `docs/legal/compliance-checklist.md` lists
  what the owner must do legally (operator, Roskomnadzor, data in Russia).

## 2026-11-17

### Beta testing
- **Demo APK** without a server (`DEMO_MODE=true`): fake data, any code except
  `0000`, nothing reaches the database.
- **Test login numbers** for staging (`TEST_LOGIN_PHONES` / `TEST_LOGIN_CODE`):
  log in with a fixed code and no SMS; 5 wrong codes lock for 15 minutes.
- GitHub Actions builds the APK on every push (**Android beta APK**).

### Build fixes found by CI
- Maven Central rate-limited GitHub runners → Gradle uses Google's mirror.
- Android Gradle Plugin 9.1.0 → 9.1.1 (minimum for current Flutter).
- `sentry_flutter` 8 → 10.5 and `flutter_secure_storage` 9 → 11.2 (old versions
  did not compile with Kotlin 2).
- Database test plan count fixed (11 checks, all green).

## 2026-11-16

### Logout and pentest fixes
- **Logout** added (there was none): button with confirmation on every main tab.
- White-box pentest (`docs/pentest-2026-11-16.md`): blocked users lose all
  access; reviews only for the crew of the order (no more 1★ to any porter);
  response ETA validated; can't respond to your own order.

## 2026-11-14

### Security hardening and iOS
- Closed critical holes: anyone could read SMS login codes and chats with the
  public key, register as admin, raise their own role, balance or rating, or
  change an order's price/status. RLS on every table, roles locked down.
- SMS login: rate limits, codes stored hashed, no reset-to-brute-force.
- Session tokens in Keychain / Android Keystore; no app-data backups; HTTPS only.
- iOS project ready for the App Store (permissions, privacy manifest, Podfile,
  build script, CI workflow) — `docs/ios-build.md`.

### Redesign
- New look for every screen on a shared UI kit (theme tokens, cards, badges,
  empty and error states, skeleton loaders).
- Fixed: the phone field crashed on the 9th digit.

## Still open

- **Rotate the leaked staging secret key** and make the repo private.
- Database migrations from 2026-11-14 and later are **not yet applied to the
  live server** — do this first (staging, then prod).
- Store blockers: in-app account deletion, reviewer demo login on prod, public
  privacy policy URL.
- Security: porters can see entrance and client phone before «Начали»; order
  price is set by the client; no limits on creating orders or messages.
- Legal: move the database to a host in Russia, register the operator with
  Roskomnadzor, fill company details in the policy and consent.
