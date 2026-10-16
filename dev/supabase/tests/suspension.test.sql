begin;
create extension if not exists pgtap with schema extensions;
select plan(32);

-- Suspending and reinstating accounts. TU Dublin's "soc" has a chair (committee) and two
-- members; "troll" is the one who gets suspended. tudadmin is TU Dublin's university admin,
-- padmin a platform admin. Ids are md5('<name>')::uuid.
insert into auth.users (id, email, aud, role)
  select md5(n)::uuid, n || '.susp@mytudublin.ie', 'authenticated', 'authenticated'
  from unnest('{padmin,tudadmin,otheradmin,chair,troll,reader}'::text[]) n;
update public.profiles set display_name = 'Tom Troll' where id = md5('troll')::uuid;
insert into public.user_roles (user_id, role) values (md5('padmin')::uuid, 'platform_admin');
insert into public.university_admins (university_id, user_id) values
  (md5('tudublin')::uuid, md5('tudadmin')::uuid), (md5('tudublin')::uuid, md5('otheradmin')::uuid);
insert into public.societies (id, slug, name, short_name, university_id) values
  (md5('soc')::uuid, 'susp-soc', 'Suspension Test Society', 'SuspSoc', md5('tudublin')::uuid);
insert into public.society_roles (society_id, user_id, position) values (md5('soc')::uuid, md5('chair')::uuid, 'Chair');
insert into public.society_memberships (society_id, user_id, status) values
  (md5('soc')::uuid, md5('troll')::uuid, 'member'), (md5('soc')::uuid, md5('reader')::uuid, 'member');
insert into public.events (id, society_id, title, starts_at, venue, category) values
  (md5('event')::uuid, md5('soc')::uuid, 'Quiz night', now() + interval '7 days', 'Room 1', 'Social');
update public.channels set id = md5('soc general')::uuid where society_id = md5('soc')::uuid and slug = 'general';
insert into public.messages (id, channel_id, author_id, body) values (md5('hello')::uuid, md5('soc general')::uuid, md5('reader')::uuid, 'Hello');
insert into public.support_requests (id, society_id, submitted_by, title, description, category) values
  (md5('request')::uuid, md5('soc')::uuid, md5('troll')::uuid, 'Need a locker', 'For the quiz equipment.', 'equipment');
insert into public.notifications (user_id, kind, title) values (md5('troll')::uuid, 'events', 'For the troll');

create function pg_temp.act_as(_name text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', md5(_name)::uuid, 'role', 'authenticated')::text, true);
end $$;
set local role authenticated;

-- Who can suspend whom
select pg_temp.act_as('chair');
select throws_ok($$select public.suspend_user(md5('troll')::uuid, 'Spamming')$$, 'P0001', 'That person isn''t at a university you manage.',
  'a committee can''t suspend anyone');
select pg_temp.act_as('tudadmin');
select throws_ok($$select public.suspend_user(md5('tudadmin')::uuid, 'Testing')$$, 'P0001', 'You can''t suspend yourself.', 'nobody suspends themselves');
select throws_ok($$select public.suspend_user(md5('otheradmin')::uuid, 'Disagreement')$$, 'P0001', 'Only platform admins can suspend an admin.',
  'a university admin can''t suspend another university admin');
select throws_ok($$select public.suspend_user(md5('padmin')::uuid, 'Disagreement')$$, 'P0001', 'Only platform admins can suspend an admin.',
  'or a platform admin');
select throws_ok($$select public.suspend_user(md5('troll')::uuid, ' ')$$, 'P0001', 'Say why. The person sees the reason.', 'a reason is required');
select results_eq($$select display_name from public.find_people(md5('tudublin')::uuid, 'troll')$$, array['Tom Troll'], 'an admin finds them by name');
select results_eq($$select display_name from public.find_people(md5('tudublin')::uuid, 'TROLL.susp@mytudublin.ie')$$, array['Tom Troll'],
  'or by email address');
select is_empty($$select 1 from public.find_people(md5('tudublin')::uuid, '%')$$, 'a wildcard alone matches nothing');
select lives_ok($$select public.suspend_user(md5('troll')::uuid, 'Harassing other members')$$, 'a university admin suspends a member');
select throws_ok($$select public.suspend_user(md5('troll')::uuid, 'Again')$$, 'P0001', 'This account is already suspended.', 'once');

-- What the suspended account still sees and does
select pg_temp.act_as('troll');
select ok((select (public.my_access()->'suspended'->>'reason') = 'Harassing other members'), 'they see why they were suspended');
select is((select json_array_length(public.my_access()->'committee')), 0, 'and hold no committee seats');
select is_empty($$select 1 from public.societies where id = md5('soc')::uuid$$, 'their society disappears');
select is_empty($$select 1 from public.events where id = md5('event')::uuid$$, 'with its events');
select is_empty($$select 1 from public.channels where society_id = md5('soc')::uuid$$, 'and channels');
select is_empty($$select 1 from public.messages$$, 'and messages');
select results_eq($$select id from public.profiles where id in (md5('troll')::uuid, md5('reader')::uuid, md5('chair')::uuid)$$,
  array[md5('troll')::uuid], 'they see their own profile, nobody else''s');
select is((select count(*)::int from public.notifications), 2, 'and still read their own notifications');
select is((select count(*)::int from public.support_requests), 1, 'and requests');
select throws_ok($$insert into public.messages (channel_id, author_id, body) values (md5('soc general')::uuid, auth.uid(), 'Hi')$$,
  '42501', null, 'they can''t post');
select throws_ok($$select public.register_for_event(md5('event')::uuid)$$, 'P0001', 'That event doesn''t exist.', 'or register for events');
select throws_ok($$select public.comment_on_support_request(md5('request')::uuid, 'Hello?')$$, 'P0001', 'Your account is suspended.',
  'or keep writing to the committee');
reset role;
select is(public.reserve_society_ai(md5('troll')::uuid, 'society_ask'), false, 'and get no AI features');
set local role authenticated;

-- A suspended committee member and admin lose their rights
select pg_temp.act_as('padmin');
select lives_ok($$select public.suspend_user(md5('chair')::uuid, 'Under investigation')$$, 'a platform admin suspends a committee member');
select lives_ok($$select public.suspend_user(md5('otheradmin')::uuid, 'Misusing admin rights')$$, 'and a university admin');
select pg_temp.act_as('chair');
select throws_ok($$insert into public.announcements (society_id, author_id, title, body) values (md5('soc')::uuid, auth.uid(), 'Hello', 'Posting while suspended.')$$,
  '42501', null, 'the suspended chair can''t post announcements');
select pg_temp.act_as('otheradmin');
select ok(not (public.my_access()->>'university_admin')::boolean, 'the suspended admin is no longer an admin');
select is_empty($$select 1 from public.university_members where user_id = md5('troll')::uuid$$, 'and can''t see the people they managed');

-- Lifting it
select pg_temp.act_as('tudadmin');
select throws_ok($$select public.reinstate_user(md5('otheradmin')::uuid)$$, 'P0001', 'Only platform admins can lift an admin''s suspension.',
  'a university admin can''t reinstate an admin');
select lives_ok($$select public.reinstate_user(md5('troll')::uuid)$$, 'but reinstates a member');
select pg_temp.act_as('troll');
select ok((select count(*) = 1 from public.messages) and json_typeof(public.my_access()->'suspended') = 'null', 'who gets everything back');
reset role;
select results_eq($$select action || ': ' || coalesce(details->>'reason', '') from public.audit_log where subject_id = md5('troll')::uuid order by id$$,
  array['person.suspended: Harassing other members', 'person.reinstated: '], 'both are in the audit log');

select * from finish();
rollback;
