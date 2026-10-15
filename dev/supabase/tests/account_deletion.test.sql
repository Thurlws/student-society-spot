begin;
create extension if not exists pgtap with schema extensions;
select plan(5);

-- A committee member who has posted, chatted, handled a request and created a guest link,
-- and a member with a support request.
insert into auth.users (id, email, aud, role) values
  ('00000000-0000-0000-0000-00000000e001', 'leaver@mytudublin.ie', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-00000000e002', 'stayer@mytudublin.ie', 'authenticated', 'authenticated');
insert into public.societies (id, slug, name, short_name)
  values ('00000000-0000-0000-0000-00000000e100', 'test-deletion-soc', 'Test Deletion Society', 'DelSoc');
insert into public.society_roles (society_id, user_id) values
  ('00000000-0000-0000-0000-00000000e100', '00000000-0000-0000-0000-00000000e001');
insert into public.society_memberships (society_id, user_id, status, decided_by) values
  ('00000000-0000-0000-0000-00000000e100', '00000000-0000-0000-0000-00000000e002', 'member', '00000000-0000-0000-0000-00000000e001');
insert into public.announcements (society_id, author_id, title, body) values
  ('00000000-0000-0000-0000-00000000e100', '00000000-0000-0000-0000-00000000e001', 'Welcome', 'Welcome to the society, everyone.');
insert into public.messages (channel_id, author_id, body)
  select id, '00000000-0000-0000-0000-00000000e001', 'hello' from public.channels where society_id = '00000000-0000-0000-0000-00000000e100' limit 1;
insert into public.call_invites (room_id, code_hash, created_by, expires_at)
  select id, 'hash-e1', '00000000-0000-0000-0000-00000000e001', now() + interval '1 day' from public.call_rooms where society_id = '00000000-0000-0000-0000-00000000e100' limit 1;
insert into public.support_requests (society_id, submitted_by, title, description, category, assigned_to) values
  ('00000000-0000-0000-0000-00000000e100', '00000000-0000-0000-0000-00000000e002', 'Need a laptop', 'Can I borrow one for hack night?', 'equipment', '00000000-0000-0000-0000-00000000e001');

select lives_ok($$delete from auth.users where id = '00000000-0000-0000-0000-00000000e001'$$, 'an account with content can be deleted');
select is((select count(*)::int from public.messages where author_id = '00000000-0000-0000-0000-00000000e001'), 0, 'their messages go with them');
select is((select count(*)::int from public.announcements where society_id = '00000000-0000-0000-0000-00000000e100' and author_id is null), 1, 'society announcements stay without the name');
select is((select assigned_to from public.support_requests where submitted_by = '00000000-0000-0000-0000-00000000e002'), null::uuid, 'requests they handled stay, unassigned');
select is((select count(*)::int from public.society_memberships where user_id = '00000000-0000-0000-0000-00000000e002' and decided_by is null), 1, 'memberships they approved stay');

select * from finish();
rollback;
