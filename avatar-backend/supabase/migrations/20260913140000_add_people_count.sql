-- =============================================
-- Add missing columns to orders: people_count, planned_duration_min
-- =============================================

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS people_count int NOT NULL DEFAULT 1 CHECK (people_count >= 1),
  ADD COLUMN IF NOT EXISTS planned_duration_min int CHECK (planned_duration_min IS NULL OR planned_duration_min >= 30);

-- Индекс для будущих запросов (например, автоназначение)
CREATE INDEX IF NOT EXISTS idx_orders_people_count ON public.orders(people_count);
