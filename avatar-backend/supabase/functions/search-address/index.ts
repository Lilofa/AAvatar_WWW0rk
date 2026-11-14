import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { json, preflight, readBody } from "../_shared/http.ts";

serve(async (req) => {
  const early = preflight(req);
  if (early) return early;

  // Только для вошедших пользователей: публичный ключ (anon) не пускаем —
  // иначе функция превращается в открытый прокси к Nominatim.
  const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { auth: { persistSession: false } },
  );
  const { data: auth } = await supabase.auth.getUser(token);
  if (!auth?.user) return json(req, { ok: false, error: "Unauthorized" }, 401);

  const body = await readBody(req);
  const query = typeof body?.query === "string" ? body.query.trim().slice(0, 200) : "";
  if (query.length < 3) return json(req, { ok: true, results: [] });

  try {
    const url = new URL("https://nominatim.openstreetmap.org/search");
    url.searchParams.set("q", query);
    url.searchParams.set("format", "json");
    url.searchParams.set("addressdetails", "1");
    url.searchParams.set("limit", "10");
    url.searchParams.set("countrycodes", "ru");

    const res = await fetch(url.toString(), {
      headers: { "User-Agent": "AvatarApp/1.0" },
      signal: AbortSignal.timeout(5000),
    });
    if (!res.ok) return json(req, { ok: false, error: "Upstream error" }, 502);
    const data = await res.json();

    return json(req, {
      ok: true,
      results: (Array.isArray(data) ? data : []).map((item: any) => ({
        display_name: String(item.display_name ?? "").slice(0, 300),
        lat: parseFloat(item.lat),
        lng: parseFloat(item.lon),
        type: String(item.type ?? ""),
      })),
    });
  } catch (e) {
    console.error("search-address", e);
    return json(req, { ok: false, error: "Internal error" }, 500);
  }
});
