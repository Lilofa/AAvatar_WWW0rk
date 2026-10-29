-- ПРЕДЛОЖЕНИЕ АГЕНТА (30.09.2026), применяет Матвей:
-- вложение (фото) в сообщении чата заказа.
-- Фронт уже готов: uploadOrderPhoto -> storage 'orders',
-- sendOrderChatMessage(attachmentUrl: ...), рендер пузыря с фото.
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS attachment_url text;

-- RLS не меняем: колонка наследует политики таблицы messages
-- (чтение/запись для участников заказа).
