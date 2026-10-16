-- Sign-in emails failed for weeks without anyone noticing: they went to Microsoft 365
-- quarantine, and the only signal was students saying so. This counts, for the last day,
-- how many sign-in links were sent and how many were followed by a sign-in, for new
-- accounts (confirmation links) and returning ones (magic links). Links sent in the last 30
-- minutes are left out, to give people time to open them. When enough links go out and
-- few are used, emails are probably not arriving, and /api/health/sign-in returns 503 so an
-- uptime monitor alerts. Only the server's service role can call it.
--
-- Supabase Auth keeps only the latest link per account (confirmation_sent_at for new ones,
-- recovery_sent_at for magic links), so this counts accounts, not emails.
create or replace function public.sign_in_health()
returns jsonb language sql stable security definer set search_path = public as $$
  with sent as (
    select
      count(*) filter (where confirmation_sent_at between now() - interval '24 hours' and now() - interval '30 minutes') as new_sent,
      count(*) filter (where confirmation_sent_at between now() - interval '24 hours' and now() - interval '30 minutes'
                         and email_confirmed_at >= confirmation_sent_at) as new_used,
      count(*) filter (where recovery_sent_at between now() - interval '24 hours' and now() - interval '30 minutes') as returning_sent,
      count(*) filter (where recovery_sent_at between now() - interval '24 hours' and now() - interval '30 minutes'
                         and last_sign_in_at >= recovery_sent_at) as returning_used
    from auth.users
  )
  select jsonb_build_object(
    'new_accounts', jsonb_build_object('sent', new_sent, 'used', new_used),
    'returning', jsonb_build_object('sent', returning_sent, 'used', returning_used),
    -- At least 5 links of a kind, and fewer than 3 in 10 used.
    'status', case when (new_sent >= 5 and new_used * 10 < new_sent * 3)
                     or (returning_sent >= 5 and returning_used * 10 < returning_sent * 3)
                   then 'degraded' else 'ok' end)
  from sent
$$;
revoke execute on function public.sign_in_health() from public, anon, authenticated;
grant execute on function public.sign_in_health() to service_role;
