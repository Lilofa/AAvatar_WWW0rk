-- =============================================
-- Extensions
-- =============================================
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- =============================================
-- ENUM types
-- =============================================
CREATE TYPE public.user_role AS ENUM ('porter', 'client', 'dispatcher', 'admin');
CREATE TYPE public.order_status AS ENUM ('created', 'accepted', 'in_progress', 'completed', 'cancelled');
CREATE TYPE public.cargo_type AS ENUM ('furniture', 'appliances', 'construction', 'boxes', 'other');
CREATE TYPE public.stage_type AS ENUM ('woke', 'departed', 'arrived', 'started', 'finished');

-- =============================================
-- profiles
-- =============================================
CREATE TABLE public.profiles (
  id              uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  phone           text UNIQUE NOT NULL,
  role            public.user_role NOT NULL DEFAULT 'client',
  roles           text[] NOT NULL DEFAULT '{}',
  active_role     text,
  pool            text NOT NULL DEFAULT 'new' CHECK (pool IN ('top', 'middle', 'new')),
  full_name       text,
  avatar_url      text,
  city            text,
  rating          numeric(3,2) NOT NULL DEFAULT 0,
  reviews_count   int NOT NULL DEFAULT 0,
  completed_count int NOT NULL DEFAULT 0,
  balance         numeric(12,2) NOT NULL DEFAULT 0,
  referral_code   text UNIQUE,
  invited_by      uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  is_blocked      boolean NOT NULL DEFAULT false,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_profiles_role          ON public.profiles(role);
CREATE INDEX idx_profiles_invited_by    ON public.profiles(invited_by);
CREATE INDEX idx_profiles_referral_code ON public.profiles(referral_code);
CREATE INDEX idx_profiles_pool          ON public.profiles(pool);

-- =============================================
-- orders
-- =============================================
CREATE TABLE public.orders (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id                uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  porter_id                uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  address_from             text NOT NULL,
  address_to               text NOT NULL,
  entrance                 int,
  cargo_type               public.cargo_type NOT NULL DEFAULT 'other',
  weight_kg                int,
  volume_m3                numeric(5,2),
  people_count           int NOT NULL DEFAULT 1 CHECK (people_count >= 1),
  planned_duration_min   int CHECK (planned_duration_min IS NULL OR planned_duration_min >= 30),
  photo_urls               text[] NOT NULL DEFAULT '{}',
  price                    numeric(10,2) NOT NULL CHECK (price >= 0),
  status                   public.order_status NOT NULL DEFAULT 'created',
  urgency                  text CHECK (urgency IS NULL OR urgency IN ('urgent', 'current', 'pre', 'ahead')),
  comment                  text,
  result_comment           text,
  went_well                boolean,
  feedback_missed          boolean NOT NULL DEFAULT false,
  minutes_adjusted_by_admin boolean NOT NULL DEFAULT false,
  is_replacement           boolean NOT NULL DEFAULT false,
  available_from           timestamptz,
  scheduled_at             timestamptz,
  accepted_at              timestamptz,
  started_at               timestamptz,
  completed_at             timestamptz,
  cancelled_at             timestamptz,
  created_at               timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_orders_status    ON public.orders(status);
CREATE INDEX idx_orders_client    ON public.orders(client_id, created_at DESC);
CREATE INDEX idx_orders_porter    ON public.orders(porter_id, created_at DESC);
CREATE INDEX idx_orders_feed      ON public.orders(status, created_at DESC) WHERE status = 'created';
CREATE INDEX idx_orders_available ON public.orders(status, available_from, created_at DESC) WHERE status = 'created';
CREATE INDEX idx_orders_people_count ON public.orders(people_count);

-- =============================================
-- order_responses
-- =============================================
CREATE TABLE public.order_responses (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id     uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  porter_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  eta_minutes  int,
  status       text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'declined')),
  created_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (order_id, porter_id)
);

CREATE INDEX idx_order_responses_order  ON public.order_responses(order_id, status);
CREATE INDEX idx_order_responses_porter ON public.order_responses(porter_id, created_at DESC);

-- =============================================
-- order_takers
-- =============================================
CREATE TABLE public.order_takers (
  order_id   uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  porter_id  uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  is_lead    boolean NOT NULL DEFAULT false,
  joined_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (order_id, porter_id)
);

CREATE INDEX idx_order_takers_porter ON public.order_takers(porter_id);

-- =============================================
-- order_stages
-- =============================================
CREATE TABLE public.order_stages (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id    uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  porter_id   uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  stage       public.stage_type NOT NULL,
  coords      jsonb,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (order_id, porter_id, stage)
);

CREATE INDEX idx_order_stages_order ON public.order_stages(order_id, created_at DESC);

-- =============================================
-- reviews
-- =============================================
CREATE TABLE public.reviews (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id        uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  author_id       uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  target_id       uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  rating          int NOT NULL CHECK (rating BETWEEN 1 AND 5),
  text            text,
  editable_until  timestamptz DEFAULT (now() + interval '24 hours'),
  created_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (order_id, author_id)
);

CREATE INDEX idx_reviews_target ON public.reviews(target_id, created_at DESC);

-- =============================================
-- messages
-- =============================================
CREATE TABLE public.messages (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id   uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  author_id  uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  text       text NOT NULL CHECK (length(text) BETWEEN 1 AND 2000),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_messages_order ON public.messages(order_id, created_at DESC);

-- =============================================
-- order_locations
-- =============================================
CREATE TABLE public.order_locations (
  id          bigserial PRIMARY KEY,
  order_id    uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  porter_id   uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  lat         numeric(9,6) NOT NULL,
  lng         numeric(9,6) NOT NULL,
  accuracy_m  numeric(6,2),
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_locations_order ON public.order_locations(order_id, created_at DESC);

-- =============================================
-- device_tokens
-- =============================================
CREATE TABLE public.device_tokens (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  token      text NOT NULL,
  platform   text NOT NULL CHECK (platform IN ('ios', 'android')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, token)
);

CREATE INDEX idx_device_tokens_user ON public.device_tokens(user_id);

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

-- =============================================
-- sms_codes
-- =============================================
CREATE TABLE public.sms_codes (
  phone       text PRIMARY KEY,
  code        text NOT NULL,
  attempts    int NOT NULL DEFAULT 0,
  expires_at  timestamptz NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- =============================================
-- Права доступа для ролей Supabase
-- =============================================
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON SCHEMA public TO anon, authenticated, service_role;

GRANT ALL ON ALL TABLES    IN SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON TABLES TO anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON FUNCTIONS TO anon, authenticated, service_role;
