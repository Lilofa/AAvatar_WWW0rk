import { GoogleSpreadsheet } from "google-spreadsheet";
import { createClient } from "@supabase/supabase-js";
import * as dotenv from "dotenv";
import { JWT } from "google-auth-library";

dotenv.config({ path: ".env.migration" });

// ============================================
// КОНФИГ
// ============================================
const SUPABASE_URL = process.env.SUPABASE_URL!;
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;
const SHEET_ID = process.env.GOOGLE_SHEETS_ID!;
const SERVICE_EMAIL = process.env.GOOGLE_SERVICE_ACCOUNT_EMAIL!;
const PRIVATE_KEY = process.env.GOOGLE_PRIVATE_KEY!.replace(/\\n/g, "\n");

const SHEET_PORTERS = process.env.SHEET_PORTERS || "Грузчики";
const SHEET_ORDERS = process.env.SHEET_ORDERS || "Заказы";
const SHEET_RESPONSES = process.env.SHEET_RESPONSES || "Отклики";
const SHEET_REFERRALS = process.env.SHEET_REFERRALS || "Рефералы";

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const auth = new JWT({
  email: SERVICE_EMAIL,
  key: PRIVATE_KEY,
  scopes: ["https://www.googleapis.com/auth/spreadsheets"],
});

// ============================================
// ХЕЛПЕРЫ
// ============================================
function log(msg: string) {
  console.log(`[${new Date().toISOString()}] ${msg}`);
}

function chunk<T>(arr: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
  return out;
}

function parseDate(value: any): string | null {
  if (!value) return null;
  const d = new Date(value);
  return isNaN(d.getTime()) ? null : d.toISOString();
}

// ============================================
// МИГРАЦИЯ ГРУЗЧИКОВ
// ============================================
async function migratePorters(doc: GoogleSpreadsheet) {
  log("=== Грузчики ===");
  const sheet = doc.sheetsByTitle[SHEET_PORTERS];
  if (!sheet) { log(`Лист "${SHEET_PORTERS}" не найден, пропускаем`); return; }

  await sheet.loadHeaderRow();
  const rows = await sheet.getRows();
  log(`Строк: ${rows.length}`);

  const porters: any[] = [];

  for (const row of rows) {
    const vkId = row.get("VK ID") || row.get("vk_id");
    const phone = row.get("Телефон") || row.get("phone");
    if (!phone) continue;

    // Создаём пользователя в auth.users через admin API
    const email = `${phone.replace(/\D/g, "")}@phone.local`;

    let userId: string | null = null;
    try {
      const { data: existing } = await supabase.auth.admin.listUsers();
      const user = existing?.users.find((u) => u.email === email);

      if (user) {
        userId = user.id;
      } else {
        const { data: created, error } = await supabase.auth.admin.createUser({
          email,
          email_confirm: true,
          user_metadata: {
            phone,
            role: "porter",
            full_name: row.get("ФИО") || row.get("Имя"),
            vk_id: vkId,
          },
        });
        if (error) { log(`Ошибка создания user ${phone}: ${error.message}`); continue; }
        userId = created.user.id;
      }
    } catch (e) {
      log(`Исключение при создании user ${phone}: ${(e as Error).message}`);
      continue;
    }

    porters.push({
      id: userId,
      phone: phone.startsWith("+") ? phone : `+${phone}`,
      role: "porter",
      roles: ["porter"],
      active_role: "porter",
      full_name: row.get("ФИО") || row.get("Имя") || null,
      city: row.get("Город") || null,
      rating: parseFloat(row.get("Рейтинг") || "0") || 0,
      reviews_count: parseInt(row.get("Отзывов") || "0") || 0,
      completed_count: parseInt(row.get("Выполнено") || "0") || 0,
      is_blocked: (row.get("Заблокирован") || "").toLowerCase() === "да",
      pool: "new",
    });
  }

  // Батчами по 100
  for (const batch of chunk(porters, 100)) {
    const { error } = await supabase.from("profiles").upsert(batch, { onConflict: "id" });
    if (error) log(`Ошибка вставки профилей: ${error.message}`);
  }

  log(`Загружено грузчиков: ${porters.length}`);
  return porters;
}

// ============================================
// МИГРАЦИЯ ЗАКАЗОВ
// ============================================
async function migrateOrders(doc: GoogleSpreadsheet, porters: any[]) {
  log("=== Заказы ===");
  const sheet = doc.sheetsByTitle[SHEET_ORDERS];
  if (!sheet) { log(`Лист "${SHEET_ORDERS}" не найден, пропускаем`); return; }

  await sheet.loadHeaderRow();
  const rows = await sheet.getRows();
  log(`Строк: ${rows.length}`);

  const phoneToId = new Map(porters.map((p) => [p.phone, p.id]));

  const orders: any[] = [];

  for (const row of rows) {
    const clientPhone = row.get("Телефон клиента") || row.get("client_phone");
    const porterPhone = row.get("Телефон грузчика") || row.get("porter_phone");

    let clientId = phoneToId.get(clientPhone);
    let porterId = porterPhone ? phoneToId.get(porterPhone) : null;

    // Если клиента нет — создаём
    if (!clientId && clientPhone) {
      const email = `${clientPhone.replace(/\D/g, "")}@phone.local`;
      const { data: created } = await supabase.auth.admin.createUser({
        email, email_confirm: true,
        user_metadata: { phone: clientPhone, role: "client" },
      });
      if (created?.user) {
        clientId = created.user.id;
        await supabase.from("profiles").upsert({
          id: clientId, phone: clientPhone, role: "client",
          roles: ["client"], active_role: "client", pool: "new",
        });
      }
    }
    if (!clientId) continue;

    orders.push({
      id: row.get("ID заказа") || row.get("order_id") || undefined,
      client_id: clientId,
      porter_id: porterId || null,
      address_from: row.get("Откуда") || row.get("address_from") || "",
      address_to: row.get("Куда") || row.get("address_to") || "",
      entrance: parseInt(row.get("Подъезд") || "0") || null,
      price: parseFloat(row.get("Сумма") || row.get("price") || "0") || 0,
      status: mapStatus(row.get("Статус") || row.get("status")),
      urgency: row.get("Срочность") || null,
      comment: row.get("Комментарий") || null,
      scheduled_at: parseDate(row.get("Время начала") || row.get("scheduled_at")),
      accepted_at: parseDate(row.get("Принят") || row.get("accepted_at")),
      completed_at: parseDate(row.get("Завершён") || row.get("completed_at")),
      cancelled_at: parseDate(row.get("Отменён") || row.get("cancelled_at")),
      created_at: parseDate(row.get("Создан") || row.get("created_at")) || new Date().toISOString(),
      people_count: parseInt(row.get("Человек") || "1") || 1,
    });
  }

  for (const batch of chunk(orders, 100)) {
    const { error } = await supabase.from("orders").upsert(batch, { onConflict: "id" });
    if (error) log(`Ошибка вставки заказов: ${error.message}`);
  }

  log(`Загружено заказов: ${orders.length}`);
}

function mapStatus(raw: string): string {
  const map: Record<string, string> = {
    "новая": "created", "new": "created",
    "принята": "accepted", "accepted": "accepted",
    "в работе": "in_progress", "in_progress": "in_progress",
    "выполнена": "completed", "completed": "completed",
    "отменена": "cancelled", "cancelled": "cancelled",
  };
  return map[raw?.toLowerCase().trim()] || "created";
}

// ============================================
// МИГРАЦИЯ ОТКЛИКОВ
// ============================================
async function migrateResponses(doc: GoogleSpreadsheet, porters: any[]) {
  log("=== Отклики ===");
  const sheet = doc.sheetsByTitle[SHEET_RESPONSES];
  if (!sheet) { log(`Лист "${SHEET_RESPONSES}" не найден, пропускаем`); return; }

  await sheet.loadHeaderRow();
  const rows = await sheet.getRows();
  log(`Строк: ${rows.length}`);

  const phoneToId = new Map(porters.map((p) => [p.phone, p.id]));
  const responses: any[] = [];

  for (const row of rows) {
    const phone = row.get("Телефон грузчика") || row.get("porter_phone");
    const porterId = phoneToId.get(phone);
    if (!porterId) continue;

    responses.push({
      id: row.get("ID отклика") || undefined,
      order_id: row.get("ID заказа") || row.get("order_id"),
      porter_id: porterId,
      eta_minutes: parseInt(row.get("ETA") || "0") || null,
      status: row.get("Статус") || "pending",
      created_at: parseDate(row.get("Создан")) || new Date().toISOString(),
    });
  }

  for (const batch of chunk(responses, 100)) {
    const { error } = await supabase.from("order_responses").upsert(batch, { onConflict: "id" });
    if (error) log(`Ошибка вставки откликов: ${error.message}`);
  }

  log(`Загружено откликов: ${responses.length}`);
}

// ============================================
// МИГРАЦИЯ РЕФЕРАЛОВ
// ============================================
async function migrateReferrals(doc: GoogleSpreadsheet, porters: any[]) {
  log("=== Рефералы ===");
  const sheet = doc.sheetsByTitle[SHEET_REFERRALS];
  if (!sheet) { log(`Лист "${SHEET_REFERRALS}" не найден, пропускаем`); return; }

  await sheet.loadHeaderRow();
  const rows = await sheet.getRows();
  log(`Строк: ${rows.length}`);

  const phoneToId = new Map(porters.map((p) => [p.phone, p.id]));
  const referrals: any[] = [];

  for (const row of rows) {
    const inviterPhone = row.get("Телефон пригласившего");
    const invitedPhone = row.get("Телефон приглашённого");

    const inviterId = phoneToId.get(inviterPhone);
    const invitedId = phoneToId.get(invitedPhone);

    if (!inviterId || !invitedId) continue;

    referrals.push({
      inviter_id: inviterId,
      invited_id: invitedId,
      status: row.get("Статус") || "new",
      created_at: parseDate(row.get("Создан")) || new Date().toISOString(),
      counted_at: parseDate(row.get("Засчитан")),
    });
  }

  for (const batch of chunk(referrals, 100)) {
    const { error } = await supabase.from("referrals").upsert(batch, { onConflict: "inviter_id, invited_id" });
    if (error) log(`Ошибка вставки рефералов: ${error.message}`);
  }

  log(`Загружено рефералов: ${referrals.length}`);
}

// ============================================
// MAIN
// ============================================
async function main() {
  log("=== СТАРТ МИГРАЦИИ ===");

  const doc = new GoogleSpreadsheet(SHEET_ID, auth);
  await doc.loadInfo();
  log(`Таблица: ${doc.title}`);

  const porters = await migratePorters(doc) || [];
  await migrateOrders(doc, porters);
  await migrateResponses(doc, porters);
  await migrateReferrals(doc, porters);

  log("=== ГОТОВО ===");
}

main().catch((e) => {
  console.error("FATAL:", e);
  process.exit(1);
});
