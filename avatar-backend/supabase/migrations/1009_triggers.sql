-- =============================================
-- updated_at
-- =============================================
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_profiles_updated ON public.profiles;
CREATE TRIGGER trg_profiles_updated
BEFORE UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_orders_updated ON public.orders;
CREATE TRIGGER trg_orders_updated
BEFORE UPDATE ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =============================================
-- Автозаполнение таймстемпов + аудит при смене статуса
-- =============================================
CREATE OR REPLACE FUNCTION public.orders_status_timestamps()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    CASE NEW.status
      WHEN 'accepted'    THEN NEW.accepted_at  := now();
      WHEN 'in_progress' THEN NEW.started_at   := now();
      WHEN 'completed'   THEN NEW.completed_at := now();
      WHEN 'cancelled'   THEN NEW.cancelled_at := now();
      ELSE NULL;
    END CASE;

    INSERT INTO public.audit_log (user_id, action, entity, entity_id, payload)
    VALUES (
      auth.uid(),
      'status_changed',
      'order',
      NEW.id,
      jsonb_build_object('from', OLD.status, 'to', NEW.status)
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_orders_status ON public.orders;
CREATE TRIGGER trg_orders_status
BEFORE UPDATE ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.orders_status_timestamps();

-- =============================================
-- Пересчет рейтинга и счетчиков при новом отзыве
-- =============================================
CREATE OR REPLACE FUNCTION public.reviews_recalc_rating()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.profiles p
  SET
    rating          = sub.avg_rating,
    reviews_count   = sub.cnt,
    completed_count = sub.cnt
  FROM (
    SELECT
      round(avg(rating)::numeric, 2) AS avg_rating,
      count(*) AS cnt
    FROM public.reviews
    WHERE target_id = NEW.target_id
  ) sub
  WHERE p.id = NEW.target_id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_reviews_recalc ON public.reviews;
CREATE TRIGGER trg_reviews_recalc
AFTER INSERT ON public.reviews
FOR EACH ROW EXECUTE FUNCTION public.reviews_recalc_rating();

-- =============================================
-- Автогенерация referral_code
-- =============================================
CREATE OR REPLACE FUNCTION public.profiles_gen_referral_code()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.referral_code IS NULL OR NEW.referral_code = '' THEN
    NEW.referral_code := upper(substring(md5(NEW.id::text || clock_timestamp()::text) from 1 for 8));
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_profiles_referral_code ON public.profiles;
CREATE TRIGGER trg_profiles_referral_code
BEFORE INSERT ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.profiles_gen_referral_code();
