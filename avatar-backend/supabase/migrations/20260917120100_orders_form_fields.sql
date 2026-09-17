ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS task_title       text,
  ADD COLUMN IF NOT EXISTS task_description text,
  ADD COLUMN IF NOT EXISTS transport        text,
  ADD COLUMN IF NOT EXISTS tariff_hint      text,
  ADD COLUMN IF NOT EXISTS client_phone     text,
  ADD COLUMN IF NOT EXISTS coords_from      jsonb,
  ADD COLUMN IF NOT EXISTS coords_to        jsonb;
