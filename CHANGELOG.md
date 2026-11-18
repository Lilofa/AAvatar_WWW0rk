# Changelog

What changed in the app, newest first. Each entry says what you will notice,
then what changed underneath. Updated with every new piece of work.

Try the latest demo in the browser (no install): see the "Аватар демо" artifact
link in the chat, or download the APK from GitHub → Actions → **Android beta APK**
→ latest green run → Artifacts.

## 2026-11-18

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

- Database migrations from 2026-11-14 and later are **not yet applied to the
  live server** — do this first (staging, then prod).
- Store blockers: in-app account deletion, reviewer demo login on prod, public
  privacy policy URL.
- Security: porters can see entrance and client phone before «Начали»; order
  price is set by the client; no limits on creating orders or messages.
- Legal: move the database to a host in Russia, register the operator with
  Roskomnadzor, fill company details in the policy and consent.
