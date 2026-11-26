-- Удаление аккаунта из приложения (App Store 5.1.1(v), Google Play, 152-ФЗ — отзыв
-- согласия). Вызывается ТОЛЬКО edge-функцией delete-account (service_role):
--   1) anonymize_user — стирает персональные данные в public.*, возвращает пути
--      фото пользователя в бакете orders (функция удаляет файлы);
--   2) затем функция мягко удаляет пользователя в auth (admin API).
-- Заказы остаются (учёт выполненных работ — п. 9 Политики), но без имени,
-- телефона, подъезда, комментариев и переписки удалённого человека.
-- Факт и версия согласия сохраняются как доказательство (п. 9 Политики).

CREATE OR REPLACE FUNCTION public.anonymize_user(p_uid uuid)
RETURNS text[]
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_paths text[];
BEGIN
  SELECT COALESCE(array_agg(substring(attachment_url FROM '^storage://orders/(.+)$')), '{}')
  INTO v_paths
  FROM public.messages
  WHERE author_id = p_uid AND attachment_url LIKE 'storage://orders/%';

  DELETE FROM public.messages WHERE author_id = p_uid;
  DELETE FROM public.worker_applications WHERE user_id = p_uid;

  UPDATE public.order_private
  SET client_phone = NULL, entrance = NULL
  WHERE order_id IN (SELECT id FROM public.orders WHERE client_id = p_uid);
  UPDATE public.orders SET comment = NULL WHERE client_id = p_uid;

  UPDATE public.profiles
  SET full_name     = 'Пользователь удалён',
      phone         = 'deleted:' || p_uid::text,
      avatar_url    = NULL,
      city          = NULL,
      referral_code = NULL,
      is_blocked    = true
  WHERE id = p_uid;

  RETURN v_paths;
END;
$$;
REVOKE ALL ON FUNCTION public.anonymize_user(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymize_user(uuid) TO service_role;

-- Срок хранения отклонённых заявок в грузчики — 1 год (Политика, п. 9).
CREATE OR REPLACE FUNCTION public.cleanup_worker_applications()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  DELETE FROM public.worker_applications
  WHERE status = 'rejected' AND reviewed_at < now() - interval '1 year';
$$;
REVOKE ALL ON FUNCTION public.cleanup_worker_applications() FROM PUBLIC, anon, authenticated;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cleanup_worker_applications') THEN
    PERFORM cron.schedule(
      'cleanup_worker_applications',
      '41 3 * * *',
      $cron$ SELECT public.cleanup_worker_applications(); $cron$
    );
  END IF;
END $$;
