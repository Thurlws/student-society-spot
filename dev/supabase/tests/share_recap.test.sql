begin;
create extension if not exists pgtap with schema extensions;
select plan(4);

-- A drop-in room (no host) and a scheduled call hosted by a member.
insert into auth.users (id, email, aud, role) values
  ('00000000-0000-0000-0000-00000000f001', 'recap.committee@mytudublin.ie', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-00000000f002', 'recap.host@mytudublin.ie', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-00000000f003', 'recap.stranger@mytudublin.ie', 'authenticated', 'authenticated');
insert into public.societies (id, slug, name, short_name) values ('00000000-0000-0000-0000-00000000f100', 'test-recap-soc', 'Test Recap Society', 'RecapSoc');
insert into public.society_roles (society_id, user_id) values ('00000000-0000-0000-0000-00000000f100', '00000000-0000-0000-0000-00000000f001');
insert into public.call_rooms (id, society_id, slug, name, kind, starts_at, host_id) values
  ('00000000-0000-0000-0000-00000000f200', '00000000-0000-0000-0000-00000000f100', 'hosted', 'Hosted call', 'meeting', now(), '00000000-0000-0000-0000-00000000f002');
insert into public.call_recaps (id, room_id, society_id, title, summary)
  select '00000000-0000-0000-0000-00000000f301', id, society_id, 'Lounge chat', '{"overview":"Private chat"}' from public.call_rooms
  where society_id = '00000000-0000-0000-0000-00000000f100' and slug = 'lounge';
insert into public.call_recaps (id, room_id, society_id, title, summary) values
  ('00000000-0000-0000-0000-00000000f302', '00000000-0000-0000-0000-00000000f200', '00000000-0000-0000-0000-00000000f100', 'Hosted call', '{"overview":"Plans"}');

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-00000000f003","role":"authenticated"}';
select throws_ok($$select public.share_recap('00000000-0000-0000-0000-00000000f301')$$,
  'P0001', 'Only the committee or the call''s host can share a recap.', 'a stranger cannot share a recap from a room without a host');
select throws_ok($$select public.share_recap('00000000-0000-0000-0000-00000000f302')$$,
  'P0001', 'Only the committee or the call''s host can share a recap.', 'a stranger cannot share a hosted call''s recap');

set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-00000000f002","role":"authenticated"}';
select lives_ok($$select public.share_recap('00000000-0000-0000-0000-00000000f302')$$, 'the host can share their call''s recap');

set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-00000000f001","role":"authenticated"}';
select lives_ok($$select public.share_recap('00000000-0000-0000-0000-00000000f301')$$, 'the committee can share a drop-in room''s recap');

reset role;
select * from finish();
rollback;
