import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { clientIp, codeHash, json, preflight, randomCode, readBody } from "../_shared/http.ts";

const COOLDOWN_SEC = 60; // между двумя SMS на один номер
const MAX_PER_PHONE_HOUR = 5;
const MAX_PER_IP_HOUR = 20;

serve(async (req) => {
  const early = preflight(req);
  if (early) return early;

  const body = await readBody(req);
  const phone = typeof body?.phone === "string" ? body.phone : "";
  if (!/^\+7\d{10}$/.test(phone)) {
    return json(req, { ok: false, error: "Invalid phone format" }, 400);
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );
  const ip = clientIp(req);
  const hourAgo = new Date(Date.now() - 3600_000).toISOString();

  try {
    // --- rate limit (защита от SMS-бомбинга, перебора и счетов за SMS) ---
    const { data: lastSend } = await admin
      .from("sms_sends").select("created_at").eq("phone", phone)
      .order("created_at", { ascending: false }).limit(1).maybeSingle();
    if (lastSend && Date.now() - new Date(lastSend.created_at).getTime() < COOLDOWN_SEC * 1000) {
      return json(req, { ok: false, error: "Too many requests", retry_after: COOLDOWN_SEC }, 429);
    }
    const { count: phoneCount } = await admin
      .from("sms_sends").select("id", { count: "exact", head: true })
      .eq("phone", phone).gte("created_at", hourAgo);
    if ((phoneCount ?? 0) >= MAX_PER_PHONE_HOUR) {
      return json(req, { ok: false, error: "Too many requests" }, 429);
    }
    if (ip !== "unknown") {
      const { count: ipCount } = await admin
        .from("sms_sends").select("id", { count: "exact", head: true })
        .eq("ip", ip).gte("created_at", hourAgo);
      if ((ipCount ?? 0) >= MAX_PER_IP_HOUR) {
        return json(req, { ok: false, error: "Too many requests" }, 429);
      }
    }

    // --- код: CSPRNG, в базе только хеш ---
    const code = randomCode();
    const { error: dbErr } = await admin.from("sms_codes").upsert({
      phone,
      code: await codeHash(phone, code),
      attempts: 0,
      expires_at: new Date(Date.now() + 5 * 60 * 1000).toISOString(),
    });
    if (dbErr) throw dbErr;
    await admin.from("sms_sends").insert({ phone, ip: ip === "unknown" ? null : ip });

    const smsRes = await fetch("https://sms.ru/sms/send", {
      method: "POST",
      body: new URLSearchParams({
        api_id: Deno.env.get("SMSRU_API_KEY")!,
        to: phone.replace("+", ""),
        msg: `Код подтверждения: ${code}`,
        json: "1",
      }),
    });
    const smsData = await smsRes.json();
    if (smsData.status !== "OK") {
      await admin.from("sms_codes").delete().eq("phone", phone);
      console.error("sms provider error", smsData.status_code);
      return json(req, { ok: false, error: "SMS service unavailable" }, 502);
    }
    return json(req, { ok: true });
  } catch (e) {
    console.error("send-sms", e); // детали — в логи, не клиенту
    return json(req, { ok: false, error: "Internal error" }, 500);
  }
});
