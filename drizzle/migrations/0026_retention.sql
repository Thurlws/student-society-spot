-- Retention: personal data that only serves a short-term purpose is deleted when that purpose
-- is over. Before, only call transcripts had a limit (7 days, migration 0003); summaries,
-- notifications, AI usage, call participation and closed reports were kept forever. The
-- periods are in docs/privacy/retention.md and are the defaults to agree with each
-- university's Data Protection Officer. Change them there and here together.
--
-- What isn't here is kept while the account or the society exists: profiles, memberships,
-- committee seats, messages, announcements, events and member requests that are still open.
create or replace function public.purge_expired_data()
returns jsonb language plpgsql security definer set search_path = public as $$
declare n jsonb := '{}'; c int;
begin
  -- Call recaps (summary, Q&A, who took part): a year after the call. Transcripts go after 7 days (0003).
  delete from public.call_recaps where created_at < now() - interval '12 months';
  get diagnostics c = row_count; n := n || jsonb_build_object('call_recaps', c);
  -- Who joined which call: only needed to write the recap and count guest link uses.
  delete from public.call_participants where joined_at < now() - interval '90 days';
  get diagnostics c = row_count; n := n || jsonb_build_object('call_participants', c);
  -- Guest links stop working when they expire; keep them a month for questions about them.
  delete from public.call_invites where expires_at < now() - interval '30 days';
  get diagnostics c = row_count; n := n || jsonb_build_object('call_invites', c);
  -- AI quotas look back one hour; a month is enough to review cost or abuse.
  delete from public.ai_usage where created_at < now() - interval '30 days';
  get diagnostics c = row_count; n := n || jsonb_build_object('ai_usage', c);
  -- The fit explanations are a daily cache.
  delete from public.society_fit_cache where created_at < now() - interval '30 days';
  get diagnostics c = row_count; n := n || jsonb_build_object('society_fit_cache', c);
  -- Notifications: read ones after 90 days, any after a year.
  delete from public.notifications
    where (read_at is not null and created_at < now() - interval '90 days') or created_at < now() - interval '12 months';
  get diagnostics c = row_count; n := n || jsonb_build_object('notifications', c);
  -- Who went to an event: a year after it ended. The event itself stays as society history.
  delete from public.event_registrations r using public.events e
    where e.id = r.event_id and coalesce(e.ends_at, e.starts_at) < now() - interval '12 months';
  get diagnostics c = row_count; n := n || jsonb_build_object('event_registrations', c);
  -- Closed reports: a year after they were dismissed. Open ones stay until someone handles them.
  delete from public.message_reports where dismissed_at < now() - interval '12 months';
  get diagnostics c = row_count; n := n || jsonb_build_object('message_reports', c);
  -- Resolved member requests and their history: two years after the last change.
  delete from public.support_requests where status = 'resolved' and updated_at < now() - interval '24 months';
  get diagnostics c = row_count; n := n || jsonb_build_object('support_requests', c);
  -- The audit log: two years, long enough to answer questions about a committee's year.
  delete from public.audit_log where at < now() - interval '24 months';
  get diagnostics c = row_count; n := n || jsonb_build_object('audit_log', c);
  return n;
end $$;
revoke execute on function public.purge_expired_data() from public, anon, authenticated;
select cron.schedule('purge-expired-data', '30 3 * * *', 'select public.purge_expired_data()');
