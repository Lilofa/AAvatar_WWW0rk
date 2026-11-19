# "12 things so your app doesn't get hacked": status for Аватар

Checked 19.11.2026 against branch `claude/security-ios`. ✅ done in code ·
🟡 done in code, owner must do one step · 🔴 owner action needed now · ➖ not applicable.

| # | Item | Status | Where / what |
|---|---|---|---|
| 1 | RLS on every table | ✅ | All `public` tables have RLS; anon has no table access (`20261115120000`, `20261116120000`, matrix in `docs/rls-matrix.md`). Tested by pgTAP `03_security` and attack script `sql/04_pentest_attacks.sql`. |
| 2 | Secret keys stay server-side | ✅ | App holds only the publishable/anon key. `service_role`, `SMSRU_API_KEY`, `SMS_CODE_PEPPER` live only in edge-function secrets. |
| 3 | Lock your file storage | ✅ new | Bucket `orders` is now **private** (`20261119120000_private_order_photos.sql`). Chat stores `storage://orders/<order>/<file>`; the app shows photos through 1-hour signed links that the server issues only to the order's client, crew and dispatchers. A message can only attach a file from its own order (CHECK constraint). Old public links are converted. Tests: `04_storage.test.sql`, `attachment_path_test.dart`. |
| 4 | Re-check login in every action | ✅ | Every RPC uses `auth.uid()`; guard triggers on profiles/orders; edge functions check the user (`search-address` requires a session). |
| 5 | Users can't edit their role | ✅ | Role/balance/rating columns locked by `guard_profile_update`; signup ignores `role` in metadata; blocked users lose access. |
| 6 | Verify Stripe webhooks | ➖ | No payments or webhooks in the app. When payments come (ЮKassa etc.) — verify the signature/IP of every notification before trusting it. |
| 7 | Cap AI / paid-API spending | ✅ new | No AI. The paid API is SMS: per phone (60 s, 5/hour), per IP (20/hour) and now a **global daily cap** `SMS_DAILY_LIMIT` (default 500 SMS/day ≈ 2 500 ₽). Also set a balance limit/alert in the SMS.ru account. |
| 8 | Rotate any leaked key | 🔴 | **The repo is public and its history contains the staging `service_role` secret key** (`sb_secret_woj7…`, commit `534597f`, file `.env.example`, project `djbtzyezhfnxberzliwc`). Deleting the file doesn't help — anyone can read old commits. Do now: Supabase → staging project → Settings → API Keys → revoke that secret key and create a new one; update it in GitHub Secrets / scripts. Also change the staging DB password. Old user tokens from `scripts/.tokens.json` (commit `f0f9948`) expired in September — no action. Recommended: make the repo private. |
| 9 | Check packages actually exist | ✅ | All npm packages resolve on the registry (no hallucinated/typosquatted names); Flutter deps resolve from pub.dev; edge functions import a pinned `@supabase/supabase-js@2.45.4`. |
| 10 | Patch the framework fast | ✅ new | `npm audit`: 0 vulnerabilities. Flutter direct deps all latest; 3 transitive packages patched. **Dependabot** added (`.github/dependabot.yml`): weekly PRs for pub, npm, Gradle, Actions. Next: update the `supabase` CLI devDependency (^1.200 → 3.x) and edge-function supabase-js. |
| 11 | Run Supabase Security Advisor | 🟡 | Owner: Dashboard → Advisors → Security Advisor on **staging and prod**, after applying the migrations. Fix every "Error"; send me the list of warnings. CLI alternative: `supabase db lint --linked`. |
| 12 | /security-review before shipping | ✅ | Run on this change: no high-confidence vulnerabilities; one migration robustness issue found and fixed. Earlier full pentest: `docs/pentest-2026-11-16.md`. |

## Must happen before real users

1. **Rotate the leaked staging secret key** (item 8) — today.
2. Apply migrations `20261115…`, `20261116…`, `20261119…` and the edge functions to staging, then prod; then run Security Advisor (item 11).
3. Set `SMS_DAILY_LIMIT` and a spending alert in SMS.ru.
4. Make the GitHub repository private.
