# RLS Matrix (после аудита 15.11.2026, миграция `20261115120000_security_hardening`)

RLS **включён на всех** таблицах; роль `anon` не имеет прав в схеме `public`.
Прямые записи возможны только там, где указано; всё остальное — через RPC
(`SECURITY DEFINER`, проверяют роль/принадлежность внутри).

| Таблица | client | porter | dispatcher | admin |
|---|---|---|---|---|
| profiles | SELECT: свой + участники общих заказов + персонал; UPDATE: только full_name/avatar_url/city (триггер `guard_profile_update`) | то же | SELECT all | SELECT all |
| orders | SELECT свои; INSERT свой (`created`); UPDATE: только отмена своего (`guard_order_update`) | SELECT свободные + свои; прямых UPDATE нет (RPC) | SELECT all | SELECT all |
| order_responses | SELECT по заказу; INSERT только RPC `respond_to_order`; DELETE своего pending | SELECT свои; DELETE своего pending | SELECT all, UPDATE | ALL |
| order_takers / order_stages | SELECT по своим заказам; **записи нет** (RPC/триггеры) | SELECT свои | SELECT all | SELECT all |
| reviews | SELECT all; INSERT только RPC `submit_review` | SELECT all | SELECT all | SELECT all |
| messages | SELECT/INSERT: участники чата (заказчик, бригада, персонал) | то же | то же | то же |
| order_locations | — | INSERT свои (только как член бригады) | SELECT all | SELECT all |
| device_tokens | SELECT/INSERT/DELETE свои | то же | то же | то же |
| audit_log | — | — | — | SELECT all |
| sms_codes, sms_sends | — | — | — | **только service_role** (edge-функции) |

Роли `dispatcher`/`admin` выдаются **только** администратором через `service_role` /
SQL-консоль. Самому себе можно добавить лишь `client`/`porter` (`add_role`).
