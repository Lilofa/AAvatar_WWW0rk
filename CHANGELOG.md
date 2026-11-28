# Changelog

What changed in the app, newest first. Each entry says what you will notice,
then what changed underneath. Updated with every new piece of work.

Try the latest demo in the browser (no install): see the "Аватар демо" artifact
link in the chat, or download the APK from GitHub → Actions → **Android beta APK**
→ latest green run → Artifacts.

## 2026-11-28

### Optional tool: Entire (history of AI agent work next to the code)
- `docs/entire.md` (Russian): what Entire Checkpoints is, how to install it,
  how to read checkpoints. **Warning:** by default it pushes agent transcripts
  to the git remote, and this repo is public — keep them local or in a
  private repo.
- `scripts/entire-setup.sh`: installs the CLI and enables it in local-only
  mode (or with a private repo: `./scripts/entire-setup.sh github:owner/repo`).
- Not installed in the cloud session: its safety check blocked the install
  (Entire adds hooks to the agent itself). Run it on your own computer.

## 2026-11-26

### Privacy policy and user agreement ready to publish
- Operator filled in from avagruz.ru: **ИП Грищук Александр Сергеевич**,
  ИНН 701739286703, ОГРНИП 311701732000069, 22-8070@mail.ru. No blanks left.
- Policy updated for today's features: porter applications, city and
  approximate location (stays on the phone), the map (OpenStreetMap), payment
  data. It now covers the app only (avagruz.ru has its own policy).
- **User agreement** rewritten for how the company really works: the app is
  the ИП's ordering tool, prices are preliminary until the dispatcher confirms,
  payment methods, cancellation under consumer law, porter applications.
- Both documents are **inside the app**: links on the login screen («Получая
  код, вы принимаете…») and at the bottom of the cabinet (Apple requires this).
- Login consent names the operator; new version `2026-11-26`.
- `legal-site/` + workflow **Legal pages** publish them on GitHub Pages
  (switch on once: Settings → Pages → Source: GitHub Actions). Text lives in
  `docs/legal/`; `python3 scripts/sync-legal.py` updates the app and the site,
  and a test fails if they differ.

### Fixed before the policy could be true
- **Porters no longer see the client's phone and entrance** in open orders
  (pentest B2). They live in a separate private table: phone — client, crew of
  the order, dispatcher; entrance — also the crew lead after «Начали».
- `get_order_safe` returned **any** order to **any** logged-in user by id. Now
  only to people in that order, staff, and porters for open feed orders.
- **«Удалить аккаунт»** at the bottom of the cabinet (App Store / Google Play
  requirement): erases name, phone, messages, photos, order phone/entrance and
  applications; finished orders stay without personal data for accounting;
  the same phone can register again.
- Rejected porter applications are deleted automatically after 1 year.

### Payments: method in the order, «paid» mark by the dispatcher
- Checked avagruz.ru: customers pay cash, by bank transfer (invoice for
  companies) or by transfer to a Sber card with 100% prepayment. There is no
  online card payment, so the app now records payment the same way.
- New order form: **«Оплата»** — наличными бригаде / переводом (предоплата) /
  по счёту для организаций. The client's order card shows the payment status.
- Dispatcher's order screen: **«Оплачено»** button (and «Снять»). Only
  dispatchers/admins can mark an order paid; the server refuses a client who
  tries to create an order already marked paid or to change it.
- `docs/payments.md`: plan for online card/СБП payment via ЮKassa (server
  computes the amount, webhook re-checked with ЮKassa, 54-ФЗ receipts) and
  what the owner must provide (contract on the ИП, shop ID and secret key).
  Also a warning about transfers to a personal card.

### City map and city detection
- Porter feed: new **map button** in the top bar switches between the list and
  a **map of the city with orders as pins** (red = urgent). Tap a pin → short
  card → «Открыть заказ».
- Client cabinet: «Мои заказы» has a **«На карте»** button.
- **City chip** (cabinet header and on the map): «Определить автоматически» or
  pick Томск / Новосибирск by hand. Location is asked only when the person taps
  «Определить», accuracy is approximate, and the coordinates never leave the
  phone — only the city name is saved to the profile.
- Map: OpenStreetMap (free, no key). For heavy traffic later, switch the tile
  server (e.g. MapTiler) — one line.
- Android asks only for approximate location; iOS has the permission text and
  the privacy manifest lists «coarse location».
- The service cities are Томск and Новосибирск (from avagruz.ru).

### Everyone signs up as a client; porters apply from the cabinet (Artem)
- The login screen no longer asks «Я заказчик / Я грузчик». Everyone is created
  as a client; the server ignores any role sent at signup.
- Cabinet → card **«Работа грузчиком» → «Подать заявку»**: name, city (Томск /
  Новосибирск), experience, 18+ confirmation. Status shows on the card: on
  review, rejected (with the reason, can apply again), approved.
- Dispatcher/admin see **«Заявки в грузчики»** at the top of their screen and
  approve or reject (with a reason). After approval the person gets the
  porter tabs without logging out.
- Server: table `worker_applications` (people see only their own; writes only
  through checked functions), max 3 applications per 30 days, one at a time.
- Fixed underneath: the server only looked at one «active» role, so a person
  who is both client and porter would have lost their own orders or porter
  actions. Role checks now use `has_role()`.
- Demo: switch the role strip to «Заказчик», apply in the cabinet, then switch
  to «Диспетчер» and approve.

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
