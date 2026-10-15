-- One locked quota function for every AI call, including call recaps (summary, question),
-- which used to count and insert in two racy requests, and caption transcription, which
-- had no limit. Limits are per user per hour; guest captions count against the person
-- who created the guest link. 600 seven-second clips is about 70 minutes of speech.
CREATE OR REPLACE FUNCTION public.reserve_society_ai(_uid uuid,_feature text) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE used integer; lim integer;
BEGIN
 lim := CASE _feature WHEN 'society_fit' THEN 20 WHEN 'society_ask' THEN 60 WHEN 'society_proposal' THEN 10
                      WHEN 'summary' THEN 10 WHEN 'question' THEN 60 WHEN 'transcribe' THEN 600 ELSE 0 END;
 IF lim=0 THEN RETURN false; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(_uid::text||_feature,0));
 SELECT count(*) INTO used FROM public.ai_usage WHERE user_id=_uid AND feature=_feature AND created_at>now()-interval '1 hour';
 IF used>=lim THEN RETURN false; END IF;
 INSERT INTO public.ai_usage(user_id,feature) VALUES(_uid,_feature); RETURN true;
END; $$;
