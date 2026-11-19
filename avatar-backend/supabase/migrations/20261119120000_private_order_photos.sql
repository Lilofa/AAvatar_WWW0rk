-- Чек-лист «12 пунктов против взлома», п. 3 — закрыть файловое хранилище.
--
-- Было: бакет 'orders' public = true. Любой, у кого есть ссылка
-- https://<ref>.supabase.co/storage/v1/object/public/orders/<order>/<file>,
-- открывал фото заказа (адрес, вещи клиента) без входа, навсегда.
-- Стало: бакет приватный; приложение хранит в сообщении ссылку вида
-- storage://orders/<order_id>/<file> и показывает фото по временной
-- подписанной ссылке (1 час). Подписать ссылку может только тот, кто проходит
-- политику orders_read_participants (участник заказа / диспетчер / админ).

UPDATE storage.buckets SET public = false WHERE id = 'orders';

-- Старые публичные ссылки в чате → внутренний формат (домен проекта любой).
-- Только ссылки на папку своего заказа, без '..'; хвост ?query отбрасываем.
-- Остальные старые строки не трогаем (NOT VALID ниже их пропускает).
UPDATE public.messages
SET attachment_url = 'storage://orders/' ||
    substring(attachment_url FROM '/storage/v1/object/public/orders/([^?#]+)')
WHERE substring(attachment_url FROM '/storage/v1/object/public/orders/([^?#]+)')
      LIKE order_id::text || '/%'
  AND attachment_url NOT LIKE '%..%';

-- Вложение может указывать только на файл ЭТОГО заказа: нельзя подсунуть в чат
-- чужое фото или внешнюю ссылку (трекинг, фишинг). NOT VALID — старые строки
-- неизвестного формата не ломают миграцию, новые проверяются всегда.
ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_attachment_own_order;
ALTER TABLE public.messages
  ADD CONSTRAINT messages_attachment_own_order CHECK (
    attachment_url IS NULL
    OR (attachment_url LIKE 'storage://orders/' || order_id::text || '/%'
        AND attachment_url NOT LIKE '%..%')
  ) NOT VALID;

-- П. 7 (потолок расходов): send-sms считает все SMS за сутки — нужен индекс по времени.
CREATE INDEX IF NOT EXISTS idx_sms_sends_created ON public.sms_sends(created_at DESC);
