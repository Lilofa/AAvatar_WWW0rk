import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { codeHash, json, preflight, readBody, safeEqual, testLogin } from "../_shared/http.ts";

const MAX_ATTEMPTS = 5;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
// Все регистрируются заказчиками. Грузчик — по заявке из кабинета
// (submit_worker_application), dispatcher/admin — администратор.

serve(async (req) => {
  const early = preflight(req);
  if (early) return early;

  const body = await readBody(req);
  const phone = typeof body?.phone === "string" ? body.phone : "";
  const code = typeof body?.code === "string" ? body.code : "";
  if (!/^\+7\d{10}$/.test(phone) || !/^\d{4,8}$/.test(code)) {
    return json(req, { ok: false, error: "phone and code required" }, 400);
  }
  const fullName = typeof body?.full_name === "string" ? body.full_name.trim().slice(0, 120) || null : null;
  const invitedBy = typeof body?.invited_by === "string" && UUID_RE.test(body.invited_by) ? body.invited_by : null;
  // Версия текста согласия на обработку ПДн (152-ФЗ), принятого на экране входа.
  const consentVersion = typeof body?.consent_version === "string" &&
      /^[0-9A-Za-z._-]{1,32}$/.test(body.consent_version)
    ? body.consent_version
    : null;

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  try {
    const test = testLogin(phone);
    if (test) {
      // Тестовый номер: код = TEST_LOGIN_CODE. Перебор всё равно ограничен:
      // 5 ошибок — блок на 15 минут (строка в sms_codes служит счётчиком).
      const { data: lock } = await admin
        .from("sms_codes").select("attempts, expires_at").eq("phone", phone).maybeSingle();
      const locked = lock && new Date(lock.expires_at) > new Date() && lock.attempts >= MAX_ATTEMPTS;
      if (locked) return json(req, { ok: false, error: "Too many attempts" }, 429);
      if (!safeEqual(await codeHash(phone, code), await codeHash(phone, test.code))) {
        const fresh = lock && new Date(lock.expires_at) > new Date();
        await admin.from("sms_codes").upsert({
          phone,
          code: "test-login-lock",
          attempts: (fresh ? lock.attempts : 0) + 1,
          expires_at: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
        });
        return json(req, { ok: false, error: "Invalid code" }, 400);
      }
      await admin.from("sms_codes").delete().eq("phone", phone);
    } else {
      const { data: row, error: fetchErr } = await admin
        .from("sms_codes").select("*").eq("phone", phone).maybeSingle();
      if (fetchErr) throw fetchErr;
      // Одинаковый ответ для «нет кода» и «неверный код» — не раскрываем состояние.
      if (!row) return json(req, { ok: false, error: "Invalid code" }, 400);
      if (new Date(row.expires_at) < new Date()) {
        await admin.from("sms_codes").delete().eq("phone", phone);
        return json(req, { ok: false, error: "Code expired" }, 400);
      }
      if (row.attempts >= MAX_ATTEMPTS) {
        return json(req, { ok: false, error: "Too many attempts" }, 429);
      }

      // Попытка «занимается» ДО сравнения и атомарно (optimistic lock):
      // параллельные запросы не дают больше MAX_ATTEMPTS догадок.
      const { data: claimed } = await admin
        .from("sms_codes").update({ attempts: row.attempts + 1 })
        .eq("phone", phone).eq("attempts", row.attempts).select("phone");
      if (!claimed || claimed.length === 0) {
        return json(req, { ok: false, error: "Too many attempts" }, 429);
      }

      if (!safeEqual(row.code, await codeHash(phone, code))) {
        return json(req, { ok: false, error: "Invalid code" }, 400);
      }
      await admin.from("sms_codes").delete().eq("phone", phone); // одноразовый
    }

    // Синтетический email: Supabase Auth требует email или phone.
    const email = `${phone.replace("+", "")}@phone.local`;

    // Ищем пользователя по профилю (а не listUsers(): тот отдаёт только первую
    // страницу, и после ~50 пользователей вход ломался бы).
    const { data: profile } = await admin
      .from("profiles").select("id, is_blocked").eq("phone", email).maybeSingle();

    let userId: string;
    if (profile) {
      if (profile.is_blocked) return json(req, { ok: false, error: "Account blocked" }, 403);
      userId = profile.id;
    } else {
      const { data: created, error: createErr } = await admin.auth.admin.createUser({
        email,
        email_confirm: true,
        user_metadata: { phone, role: "client", full_name: fullName, invited_by: invitedBy },
      });
      if (createErr) throw createErr;
      userId = created.user.id;
    }

    if (consentVersion) {
      await admin.from("profiles")
        .update({ pd_consent_at: new Date().toISOString(), pd_consent_version: consentVersion })
        .eq("id", userId);
    }

    const { data: link, error: linkErr } = await admin.auth.admin.generateLink({
      type: "magiclink",
      email,
    });
    if (linkErr) throw linkErr;

    return json(req, { ok: true, userId, token_hash: link.properties?.hashed_token });
  } catch (e) {
    console.error("verify-sms", e);
    return json(req, { ok: false, error: "Internal error" }, 500);
  }
});
