# RLS Matrix

| Таблица     | client             | porter                                | dispatcher | admin |
|-------------|--------------------|---------------------------------------|------------|-------|
| profiles    | SELECT all, UPDATE own | SELECT all, UPDATE own            | SELECT all | ALL   |
| orders      | SELECT own, INSERT own, UPDATE own (cancel) | SELECT free + own, UPDATE own (accept, advance) | SELECT all, UPDATE all | ALL |
| reviews     | SELECT all, INSERT own (for completed) | SELECT all                       | SELECT all | ALL   |
| audit_log   | —                  | —                                     | —          | SELECT all |
| sms_codes   | —                  | —                                     | —          | service_role only |
