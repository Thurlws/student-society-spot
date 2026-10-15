begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

-- The helpers are no longer in the API-exposed schema.
select hasnt_function('public', 'has_role', 'has_role is not callable through the API');
select hasnt_function('public', 'is_society_member', 'is_society_member is not callable through the API');
select hasnt_function('public', 'is_society_committee', 'is_society_committee is not callable through the API');
select hasnt_function('public', 'society_visible', 'society_visible is not callable through the API');
select hasnt_function('public', 'can_see_profile', 'can_see_profile is not callable through the API');

-- Fixtures: an approval-only society with one committee member and one member, plus an outsider.
insert into auth.users (id, email, aud, role) values
  ('00000000-0000-0000-0000-00000000b001', 'committee@mytudublin.ie', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-00000000b002', 'member@mytudublin.ie', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-00000000b003', 'outsider@mytudublin.ie', 'authenticated', 'authenticated');
insert into public.societies (id, slug, name, short_name, requires_approval)
  values ('00000000-0000-0000-0000-00000000b100', 'test-private-soc', 'Test Private Society', 'TestSoc', true);
insert into public.society_roles (society_id, user_id) values
  ('00000000-0000-0000-0000-00000000b100', '00000000-0000-0000-0000-00000000b001');
insert into public.society_memberships (society_id, user_id, status) values
  ('00000000-0000-0000-0000-00000000b100', '00000000-0000-0000-0000-00000000b002', 'member');

-- As the outsider.
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-00000000b003","role":"authenticated"}';
select is((select count(*)::int from public.society_memberships where user_id = '00000000-0000-0000-0000-00000000b002'), 0,
  'an outsider cannot read someone else''s membership');
select is((select count(*)::int from public.profiles where id = '00000000-0000-0000-0000-00000000b002'), 0,
  'an outsider cannot see a member''s profile');
select is((select count(*)::int from public.profiles where id = '00000000-0000-0000-0000-00000000b001'), 1,
  'committee members stay visible as contacts');
select is(public.join_society('00000000-0000-0000-0000-00000000b100'), 'pending', 'functions that use the helpers still work');
select is((select count(*)::int from public.profiles where id = '00000000-0000-0000-0000-00000000b002'), 0,
  'a pending request does not reveal the members');

-- As the committee member.
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-00000000b001","role":"authenticated"}';
select is((select count(*)::int from public.society_memberships where society_id = '00000000-0000-0000-0000-00000000b100'), 2,
  'the committee reads its society''s memberships, including the pending one');
select is((select count(*)::int from public.society_members('00000000-0000-0000-0000-00000000b100')), 2,
  'the committee request list still loads');

reset role;
select * from finish();
rollback;
