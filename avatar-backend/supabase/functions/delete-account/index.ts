// Удаление аккаунта из приложения: «Кабинет → Удалить аккаунт».
// App Store 5.1.1(v) и Google Play требуют удаление внутри приложения;
// по 152-ФЗ это же — отзыв согласия (Политика, п. 10).
//
// 1. Кто удаляет — только сам пользователь: берём id ИЗ ЕГО ТОКЕНА, не из тела.
// 2. anonymize_user (SQL, только service_role): стирает имя, телефон, переписку,
//    телефон/подъезд в своих заказах, заявки; возвращает пути своих фото.
// 3. Удаляем фото из приватного бакета orders.
// 4. Мягко удаляем пользователя в auth: заказы остаются для учёта, вход
//    невозможен, тот же номер потом можно зарегистрировать заново.
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { json, preflight } from "../_shared/http.ts";

serve(async (req) => {
  const early = preflight(req);
  if (early) return early;
  if (req.method !== "POST") return json(req, { ok: false, error: "Method not allowed" }, 405);

  const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  const url = Deno.env.get("SUPABASE_URL")!;
  const userClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    auth: { persistSession: false },
  });
  const { data: auth } = await userClient.auth.getUser(token);
  const uid = auth?.user?.id;
  if (!uid) return json(req, { ok: false, error: "Unauthorized" }, 401);

  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });

  try {
    const { data: paths, error: anonErr } = await admin.rpc("anonymize_user", { p_uid: uid });
    if (anonErr) throw anonErr;

    const files = (Array.isArray(paths) ? paths : [])
      .filter((p): p is string => typeof p === "string" && p.length > 0 && !p.includes(".."));
    for (let i = 0; i < files.length; i += 100) {
      const { error } = await admin.storage.from("orders").remove(files.slice(i, i + 100));
      if (error) console.error("delete-account: storage remove failed", error.message);
    }

    // Уникальный адрес вместо синтетического <номер>@phone.local — чтобы номер
    // освободился для новой регистрации, затем мягкое удаление.
    const { error: updErr } = await admin.auth.admin.updateUserById(uid, {
      email: `deleted-${uid}@deleted.invalid`,
      email_confirm: true,
      user_metadata: {},
    });
    if (updErr) console.error("delete-account: scrub auth user failed", updErr.message);

    const { error: delErr } = await admin.auth.admin.deleteUser(uid, true);
    if (delErr) throw delErr;

    return json(req, { ok: true });
  } catch (e) {
    console.error("delete-account failed", e instanceof Error ? e.message : String(e));
    return json(req, { ok: false, error: "Не удалось удалить аккаунт. Напишите нам." }, 500);
  }
});
