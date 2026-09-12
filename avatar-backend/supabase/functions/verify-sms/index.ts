import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { phone, code, role = "client", full_name = null, invited_by = null } = await req.json();

    if (!phone || !code) {
      return json({ ok: false, error: "phone and code required" }, 400);
    }

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: row, error: fetchErr } = await admin
      .from("sms_codes")
      .select("*")
      .eq("phone", phone)
      .maybeSingle();

    if (fetchErr) throw fetchErr;
    if (!row) return json({ ok: false, error: "Code not found" }, 400);
    if (new Date(row.expires_at) < new Date()) {
      return json({ ok: false, error: "Code expired" }, 400);
    }
    if (row.attempts >= 5) {
      return json({ ok: false, error: "Too many attempts" }, 429);
    }
    if (row.code !== code) {
      await admin.from("sms_codes").update({ attempts: row.attempts + 1 }).eq("phone", phone);
      return json({ ok: false, error: "Invalid code" }, 400);
    }

    await admin.from("sms_codes").delete().eq("phone", phone);

    // Формируем синтетический email из телефона — Supabase Auth требует email или phone
    const email = `${phone.replace("+", "")}@phone.local`;

    // Пробуем найти пользователя
    const { data: existing } = await admin.auth.admin.listUsers();
    const user = existing?.users.find((u) => u.email === email);

    let userId: string;

    if (!user) {
      const { data: created, error: createErr } = await admin.auth.admin.createUser({
        email,
        email_confirm: true,
        user_metadata: { phone, role, full_name, invited_by },
      });
      if (createErr) throw createErr;
      userId = created.user.id;
    } else {
      userId = user.id;
    }

    // Генерируем ссылку для входа
    const { data: link, error: linkErr } = await admin.auth.admin.generateLink({
      type: "magiclink",
      email,
    });
    if (linkErr) throw linkErr;

    return json({
      ok: true,
      userId,
      // Фронт использует token_hash для verifyOtp
      token_hash: link.properties?.hashed_token,
    });
  } catch (e) {
    console.error(e);
    return json({ ok: false, error: (e as Error).message }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
