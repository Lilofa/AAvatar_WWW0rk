# API Contract

## Base
Все запросы идут напрямую в Supabase (PostgREST) или через Edge Functions.

- URL: `SUPABASE_URL`
- Anon key: `SUPABASE_ANON_KEY`
- Авторизация: `Authorization: Bearer <access_token>`

## Auth flow

1. `POST /functions/v1/send-sms` → `{ phone: "+79991234567" }`
2. `POST /functions/v1/verify-sms` → `{ phone, code, role?, full_name?, invited_by? }`
   Возвращает `{ ok, userId, token_hash }`
3. Фронт вызывает `supabase.auth.verifyOtp({ type: 'magiclink', token_hash })`
   → получает `access_token` и `refresh_token`.

## Таблицы (PostgREST)

### profiles
- `GET /rest/v1/profiles?select=*&id=eq.<uuid>`
- `PATCH /rest/v1/profiles?id=eq.<uuid>` — только свои поля

### orders
- `GET /rest/v1/orders?status=eq.created` — лента грузчика
- `GET /rest/v1/orders?client_id=eq.<uuid>` — свои заказы
- `POST /rest/v1/orders` — создать заявку (только client)
- `PATCH /rest/v1/orders?id=eq.<uuid>` — смена статуса (RLS проверит)

### reviews
- `GET /rest/v1/reviews?target_id=eq.<uuid>`
- `POST /rest/v1/reviews`

### audit_log
- `GET /rest/v1/audit_log` — только admin

## RPC

### accept_order
```ts
await supabase.rpc('accept_order', { p_order_id: '...' });
