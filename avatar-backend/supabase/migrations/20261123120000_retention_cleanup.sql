-- Сроки хранения из Политики конфиденциальности (п. 9), чтобы обещание было правдой:
--   * коды из SMS — удаляются после истечения (живут 5 минут);
--   * журнал отправок SMS (номер + IP, нужен для лимитов) — 30 дней.
-- Раньше cleanup_expired_sms_codes() существовала, но нигде не вызывалась.

CREATE OR REPLACE FUNCTION public.cleanup_sms_retention()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  DELETE FROM public.sms_codes WHERE expires_at < now();
  DELETE FROM public.sms_sends WHERE created_at < now() - interval '30 days';
$$;

REVOKE ALL ON FUNCTION public.cleanup_sms_retention() FROM PUBLIC, anon, authenticated;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cleanup_sms_retention') THEN
    PERFORM cron.schedule(
      'cleanup_sms_retention',
      '17 * * * *',
      $cron$ SELECT public.cleanup_sms_retention(); $cron$
    );
  END IF;
END $$;
