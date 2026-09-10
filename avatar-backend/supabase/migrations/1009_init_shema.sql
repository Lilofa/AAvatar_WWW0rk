CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TYPE public.user_role AS ENUM ('porter', 'client', 'dispatcher', 'admin');
CREATE TYPE public.order_status AS ENUM ('created', 'accepted', 'in_progress', 'completed', 'cancelled');
CREATE TYPE public.cargo_type AS ENUM ('furniture', 'appliances', 'construction', 'boxes', 'other');

-- =============================================
-- profiles
-- =============================================
CREATE TABLE public.profiles (
  id              uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  phone           text UNIQUE NOT NULL,
  role            public.user_role NOT NULL DEFAULT 'client',
  full_name       text,
  avatar_url      text,
  city            text,
  rating          numeric(3,2) NOT NULL DEFAULT 0,
  reviews_count   int NOT NULL DEFAULT 0,
  completed_count int NOT NULL DEFAULT 0,
  referral_code   text UNIQUE,
  invited_by      uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  is_blocked      boolean NOT NULL DEFAULT false,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_profiles_role          ON public.profiles(role);
CREATE INDEX idx_profiles_invited_by    ON public.profiles(invited_by);
CREATE INDEX idx_profiles_referral_code ON public.profiles(referral_code);

-- =============================================
-- orders
-- =============================================
CREATE TABLE public.orders (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id       uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  porter_id       uuid REFERENCES public.profiles(id) ON DELETE SET NULL,

  address_from    text NOT NULL,
  address_to      text NOT NULL,
  cargo_type      public.cargo_type NOT NULL DEFAULT 'other',
  weight_kg       int,
  volume_m3       numeric(5,2),
  photo_urls      text[] NOT NULL DEFAULT '{}',

  price           numeric(10,2) NOT NULL CHECK (price >= 0),
  status          public.order_status NOT NULL DEFAULT 'created',
  comment         text,

  scheduled_at    timestamptz,
  accepted_at     timestamptz,
  started_at      timestamptz,
  completed_at    timestamptz,
  cancelled_at    timestamptz,

  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_orders_status      ON public.orders(status);
CREATE INDEX idx_orders_client      ON public.orders(client_id, created_at DESC);
CREATE INDEX idx_orders_porter      ON public.orders(porter_id, created_at DESC);
CREATE INDEX idx_orders_feed        ON public.orders(status, created_at DESC) WHERE status = 'created';

-- =============================================
-- reviews
-- =============================================
CREATE TABLE public.reviews (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id    uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  author_id   uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  target_id   uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  rating      int NOT NULL CHECK (rating BETWEEN 1 AND 5),
  text        text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (order_id, author_id)
);

CREATE INDEX idx_reviews_target ON public.reviews(target_id, created_at DESC);

-- =============================================
-- audit_log
-- =============================================
CREATE TABLE public.audit_log (
  id          bigserial PRIMARY KEY,
  user_id     uuid,
  action      text NOT NULL,
  entity      text NOT NULL,
  entity_id   uuid,
  payload     jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_audit_entity ON public.audit_log(entity, entity_id, created_at DESC);
