import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { phone } = await req.json();
    if (!phone || !/^\+7\d{10}$/.test(phone)) {
      return json({ ok: false, error: "Invalid phone format" }, 400);
    }

    const code = String(Math.floor(100000 + Math.random() * 900000));
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // удаляем старые коды для этого номера
    await supabase.from("sms_codes").delete().eq("phone", phone);
    // сохраняем новый
    const { error: dbErr } = await supabase.from("sms_codes").insert({
      phone,
      code,
      expires_at: new Date(Date.now() + 5 * 60 * 1000).toISOString(),
    });
    if (dbErr) throw dbErr;

    // отправляем через SMS.ru
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
    if (smsData.status !== "OK") throw new Error("SMS provider error");

    return json({ ok: true });
  } catch (e) {
    return json({ ok: false, error: (e as Error).message }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
