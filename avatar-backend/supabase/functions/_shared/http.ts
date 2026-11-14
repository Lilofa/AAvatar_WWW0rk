// Общие хелперы edge-функций: CORS по allowlist, JSON-ответы, IP, хеширование.

const ALLOWED = (Deno.env.get("ALLOWED_ORIGINS") ?? "")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);

/// Мобильное приложение шлёт запросы без Origin — CORS ему не нужен.
/// Браузерам отвечаем ТОЛЬКО если Origin в ALLOWED_ORIGINS (через запятую).
export function corsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("origin");
  const h: Record<string, string> = {
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
  if (origin && ALLOWED.includes(origin)) h["Access-Control-Allow-Origin"] = origin;
  return h;
}

export function json(req: Request, body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(req),
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

export function preflight(req: Request): Response | null {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders(req) });
  if (req.method !== "POST") return json(req, { ok: false, error: "Method not allowed" }, 405);
  return null;
}

/// Тело запроса: только JSON-объект, не больше 4 КБ.
export async function readBody(req: Request): Promise<Record<string, unknown> | null> {
  try {
    const text = await req.text();
    if (text.length > 4096) return null;
    const v = JSON.parse(text);
    return v && typeof v === "object" && !Array.isArray(v) ? v : null;
  } catch {
    return null;
  }
}

export function clientIp(req: Request): string {
  return (
    req.headers.get("cf-connecting-ip") ??
    req.headers.get("x-real-ip") ??
    req.headers.get("x-forwarded-for")?.split(",")[0].trim() ??
    "unknown"
  );
}

export async function sha256Hex(text: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/// Сравнение за постоянное время (хеши одинаковой длины).
export function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/// Равномерный 6-значный код из криптографического ГСЧ (без modulo bias).
export function randomCode(): string {
  const buf = new Uint32Array(1);
  const limit = Math.floor(0xffffffff / 900000) * 900000;
  do crypto.getRandomValues(buf); while (buf[0] >= limit);
  return String(100000 + (buf[0] % 900000));
}

export async function codeHash(phone: string, code: string): Promise<string> {
  const pepper = Deno.env.get("SMS_CODE_PEPPER") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  return await sha256Hex(`${phone}:${code}:${pepper}`);
}
