begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

-- The nightly purge deletes what is past its retention period and nothing newer. Each table
-- gets an "old" row just past its limit and a "new" one just inside it. Ids are md5('<name>')::uuid.
insert into auth.users (id, email, aud, role) values (md5('keeper')::uuid, 'keeper.ret@mytudublin.ie', 'authenticated', 'authenticated');
insert into public.societies (id, slug, name, short_name, university_id) values (md5('soc')::uuid, 'ret-soc', 'Retention Society', 'RetSoc', md5('tudublin')::uuid);
update public.call_rooms set id = md5('room')::uuid where society_id = md5('soc')::uuid and slug = 'lounge';
delete from public.audit_log;

insert into public.call_recaps (id, room_id, society_id, title, summary, created_at) values
  (md5('old recap')::uuid, md5('room')::uuid, md5('soc')::uuid, 'Old', '{}', now() - interval '13 months'),
  (md5('new recap')::uuid, md5('room')::uuid, md5('soc')::uuid, 'New', '{}', now() - interval '11 months');
insert into public.call_participants (room_id, user_id, livekit_identity, joined_at) values
  (md5('room')::uuid, md5('keeper')::uuid, 'old', now() - interval '91 days'),
  (md5('room')::uuid, md5('keeper')::uuid, 'new', now() - interval '89 days');
insert into public.call_invites (room_id, code_hash, created_by, expires_at) values
  (md5('room')::uuid, 'old', md5('keeper')::uuid, now() - interval '31 days'),
  (md5('room')::uuid, 'new', md5('keeper')::uuid, now() - interval '29 days');
insert into public.ai_usage (user_id, feature, created_at) values
  (md5('keeper')::uuid, 'old', now() - interval '31 days'), (md5('keeper')::uuid, 'new', now() - interval '29 days');
insert into public.society_fit_cache (user_id, society_id, reason, context_hash, created_at) values
  (md5('keeper')::uuid, md5('soc')::uuid, 'old', 'h', now() - interval '31 days');
insert into public.notifications (user_id, kind, title, read_at, created_at) values
  (md5('keeper')::uuid, 'events', 'old read', now(), now() - interval '91 days'),
  (md5('keeper')::uuid, 'events', 'new read', now(), now() - interval '89 days'),
  (md5('keeper')::uuid, 'events', 'old unread', null, now() - interval '13 months'),
  (md5('keeper')::uuid, 'events', 'new unread', null, now() - interval '11 months');
insert into public.events (id, society_id, title, starts_at, venue, category) values
  (md5('old event')::uuid, md5('soc')::uuid, 'Old event', now() - interval '13 months', 'Room 1', 'Social'),
  (md5('new event')::uuid, md5('soc')::uuid, 'New event', now() - interval '11 months', 'Room 1', 'Social');
insert into public.event_registrations (event_id, user_id) values
  (md5('old event')::uuid, md5('keeper')::uuid), (md5('new event')::uuid, md5('keeper')::uuid);
insert into public.messages (id, channel_id, author_id, body)
  select md5(v)::uuid, c.id, md5('keeper')::uuid, v from public.channels c cross join unnest('{m1,m2,m3}'::text[]) v
  where c.society_id = md5('soc')::uuid and c.slug = 'general';
insert into public.message_reports (message_id, society_id, author_id, reported_by, excerpt, dismissed_at) values
  (md5('m1')::uuid, md5('soc')::uuid, md5('keeper')::uuid, md5('keeper')::uuid, 'old', now() - interval '13 months'),
  (md5('m2')::uuid, md5('soc')::uuid, md5('keeper')::uuid, md5('keeper')::uuid, 'new', now() - interval '11 months'),
  (md5('m3')::uuid, md5('soc')::uuid, md5('keeper')::uuid, md5('keeper')::uuid, 'open', null);
insert into public.support_requests (society_id, submitted_by, title, description, category, status, updated_at) values
  (md5('soc')::uuid, md5('keeper')::uuid, 'Old resolved', 'Resolved long ago.', 'other', 'resolved', now() - interval '25 months'),
  (md5('soc')::uuid, md5('keeper')::uuid, 'Old but open', 'Still waiting here.', 'other', 'open', now() - interval '25 months'),
  (md5('soc')::uuid, md5('keeper')::uuid, 'New resolved', 'Resolved recently.', 'other', 'resolved', now() - interval '23 months');
insert into public.audit_log (actor_role, action, at) values ('system', 'old', now() - interval '25 months'), ('system', 'new', now() - interval '23 months');

select is(public.purge_expired_data(), '{"call_recaps": 1, "call_participants": 1, "call_invites": 1, "ai_usage": 1, "society_fit_cache": 1,
  "notifications": 2, "event_registrations": 1, "message_reports": 1, "support_requests": 1, "audit_log": 1}'::jsonb,
  'the purge deletes one expired row of each kind, and both kinds of old notification');
select results_eq($$select title from public.call_recaps where society_id = md5('soc')::uuid$$, array['New'], 'recaps stay a year');
select results_eq($$select livekit_identity from public.call_participants where room_id = md5('room')::uuid$$, array['new'], 'call participation 90 days');
select results_eq($$select code_hash from public.call_invites where room_id = md5('room')::uuid$$, array['new'], 'expired guest links 30 days');
select results_eq($$select feature from public.ai_usage where user_id = md5('keeper')::uuid$$, array['new'], 'AI usage 30 days');
select results_eq($$select title from public.notifications where user_id = md5('keeper')::uuid order by title$$,
  array['new read', 'new unread'], 'read notifications 90 days, unread ones a year');
select results_eq($$select event_id from public.event_registrations where user_id = md5('keeper')::uuid$$,
  array[md5('new event')::uuid], 'event registrations a year after the event');
select is((select count(*)::int from public.events where id = md5('old event')::uuid), 1, 'the event itself stays');
select results_eq($$select excerpt from public.message_reports where society_id = md5('soc')::uuid order by excerpt$$,
  array['new', 'open'], 'closed reports a year, open ones until handled');
select results_eq($$select title from public.support_requests where submitted_by = md5('keeper')::uuid order by title$$,
  array['New resolved', 'Old but open'], 'resolved requests two years, open ones until resolved');
select results_eq($$select action from public.audit_log$$, array['new'], 'the audit log two years');
select is((select schedule from cron.job where jobname = 'purge-expired-data'), '30 3 * * *', 'it runs every night');

set local role authenticated;
select throws_ok($$select public.purge_expired_data()$$, '42501', null, 'signed-in users can''t run it');
reset role;
set local role anon;
select throws_ok($$select public.purge_expired_data()$$, '42501', null, 'or signed-out visitors');
reset role;

select * from finish();
rollback;
