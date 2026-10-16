begin;
create extension if not exists pgtap with schema extensions;
select plan(50);

-- Two universities side by side: TU Dublin and Atlantic University (AtlU), each with a
-- society at the same address, an event, an announcement, a resource, a message, a
-- committee and a member. tudadmin is TU Dublin's university admin. Ids are md5('<name>')::uuid.
insert into public.universities (id, slug, name, short_name) values (md5('atlantic')::uuid, 'atlantic', 'Atlantic University', 'AtlU');
insert into public.university_domains (domain, university_id) values ('atlantic.test', md5('atlantic')::uuid);
insert into auth.users (id, email, aud, role) values
  (md5('tudchair')::uuid, 'tudchair.iso@mytudublin.ie', 'authenticated', 'authenticated'),
  (md5('tudstudent')::uuid, 'tudstudent.iso@mytudublin.ie', 'authenticated', 'authenticated'),
  (md5('tudadmin')::uuid, 'tudadmin.iso@tudublin.ie', 'authenticated', 'authenticated'),
  (md5('atlchair')::uuid, 'atlchair.iso@atlantic.test', 'authenticated', 'authenticated'),
  (md5('atlstudent')::uuid, 'atlstudent.iso@atlantic.test', 'authenticated', 'authenticated');
insert into public.university_admins (university_id, user_id) values (md5('tudublin')::uuid, md5('tudadmin')::uuid);
insert into public.societies (id, slug, name, short_name, university_id) values
  (md5('tudsoc')::uuid, 'iso-quiz', 'Quiz Society', 'Quiz', md5('tudublin')::uuid),
  (md5('atlsoc')::uuid, 'iso-quiz', 'Atlantic Quiz Society', 'AtlQuiz', md5('atlantic')::uuid),
  (md5('tudchess')::uuid, 'iso-chess', 'Chess Society', 'Chess', md5('tudublin')::uuid);
insert into public.society_tags (society_id, interest_id)
  select md5(s)::uuid, (select id from public.interests where name = i) from (values ('tudsoc', 'Technology'), ('atlsoc', 'Music')) v(s, i);
insert into public.profile_interests (profile_id, interest_id) select md5('tudstudent')::uuid, id from public.interests where name = 'Music';
insert into public.society_roles (society_id, user_id, position) values
  (md5('tudsoc')::uuid, md5('tudchair')::uuid, 'Chair'), (md5('atlsoc')::uuid, md5('atlchair')::uuid, 'Chair');
insert into public.society_memberships (society_id, user_id, status) values
  (md5('tudsoc')::uuid, md5('tudstudent')::uuid, 'member'), (md5('atlsoc')::uuid, md5('atlstudent')::uuid, 'member');
insert into public.events (id, society_id, title, starts_at, venue, category, capacity) values
  (md5('tudevent')::uuid, md5('tudsoc')::uuid, 'Quiz night', now() + interval '7 days', 'Aungier St', 'Social', 50),
  (md5('atlevent')::uuid, md5('atlsoc')::uuid, 'Atlantic quiz', now() + interval '7 days', 'Main hall', 'Social', 50);
insert into public.event_registrations (event_id, user_id) values
  (md5('tudevent')::uuid, md5('tudstudent')::uuid), (md5('atlevent')::uuid, md5('atlstudent')::uuid);
insert into public.announcements (id, society_id, author_id, title, body) values
  (md5('tudpost')::uuid, md5('tudsoc')::uuid, md5('tudchair')::uuid, 'Welcome', 'Welcome to the quiz society.'),
  (md5('atlpost')::uuid, md5('atlsoc')::uuid, md5('atlchair')::uuid, 'Welcome', 'Welcome to the Atlantic quiz society.');
insert into public.resources (id, society_id, title, kind) values
  (md5('tudres')::uuid, md5('tudsoc')::uuid, 'Question bank', 'Document'),
  (md5('atlres')::uuid, md5('atlsoc')::uuid, 'Answer sheet', 'Document');
insert into public.collaboration_proposals (id, society_a, society_b, title, created_by, source)
  values (md5('proposal')::uuid, md5('tudsoc')::uuid, md5('tudchess')::uuid, 'Quiz and chess night', md5('tudchair')::uuid, 'committee');
insert into public.messages (id, channel_id, author_id, body)
  select md5(v.id)::uuid, c.id, md5(v.author)::uuid, 'Hello' from public.channels c
  join (values ('tudmsg', 'tudsoc', 'tudchair'), ('atlmsg', 'atlsoc', 'atlchair')) v(id, soc, author) on c.society_id = md5(v.soc)::uuid
  where c.slug = 'general';

create function pg_temp.act_as(_name text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', md5(_name)::uuid, 'role', 'authenticated')::text, true);
end $$;
-- Rows a statement changed, as the current user (0 means RLS hid them).
create function pg_temp.changed(_sql text) returns int language plpgsql as $$
declare n int;
begin
  execute _sql;
  get diagnostics n = row_count;
  return n;
end $$;

-- Sign-up
select is((select university_id from public.university_members where user_id = md5('tudstudent')::uuid), md5('tudublin')::uuid,
  'a mytudublin.ie sign-up is a TU Dublin member');
select is((select university_id from public.university_members where user_id = md5('tudadmin')::uuid), md5('tudublin')::uuid,
  'so is a tudublin.ie sign-up');
select is((select university_id from public.university_members where user_id = md5('atlstudent')::uuid), md5('atlantic')::uuid,
  'an atlantic.test sign-up is an Atlantic member');
select throws_ok($$insert into auth.users (id, email, aud, role) values (md5('stranger')::uuid, 'someone@unknown.test', 'authenticated', 'authenticated')$$,
  'P0001', 'Please use your university email address.', 'an address at no listed university is refused');
select is((select count(*)::int from public.societies where slug = 'iso-quiz'), 2, 'both universities have a society at the same address');
select throws_ok($$insert into public.societies (slug, name, short_name, university_id) values ('iso-quiz', 'Another Quiz Society', 'Quiz2', md5('tudublin')::uuid)$$,
  '23505', null, 'but one university can''t have two');

-- A TU Dublin student sees nothing of Atlantic's.
set local role authenticated;
select pg_temp.act_as('tudstudent');
select is_empty($$select 1 from public.societies where university_id <> md5('tudublin')::uuid$$, 'a student sees no other university''s societies');
select results_eq($$select id from public.events where id in (md5('tudevent')::uuid, md5('atlevent')::uuid)$$, array[md5('tudevent')::uuid], 'or events');
select results_eq($$select id from public.announcements where id in (md5('tudpost')::uuid, md5('atlpost')::uuid)$$, array[md5('tudpost')::uuid], 'or announcements');
select results_eq($$select society_id from public.society_tags where society_id in (md5('tudsoc')::uuid, md5('atlsoc')::uuid)$$, array[md5('tudsoc')::uuid], 'or tags');
select results_eq($$select user_id from public.society_roles where society_id in (md5('tudsoc')::uuid, md5('atlsoc')::uuid)$$, array[md5('tudchair')::uuid], 'or committees');
select results_eq($$select id from public.profiles where id in (md5('tudchair')::uuid, md5('atlchair')::uuid, md5('atlstudent')::uuid)$$,
  array[md5('tudchair')::uuid], 'or people');
select results_eq($$select id from public.resources where id in (md5('tudres')::uuid, md5('atlres')::uuid)$$, array[md5('tudres')::uuid], 'or resources');
select results_eq($$select distinct society_id from public.channels where society_id in (md5('tudsoc')::uuid, md5('atlsoc')::uuid)$$, array[md5('tudsoc')::uuid], 'or channels');
select results_eq($$select id from public.messages where id in (md5('tudmsg')::uuid, md5('atlmsg')::uuid)$$, array[md5('tudmsg')::uuid], 'or messages');
select results_eq($$select society_id from public.society_member_counts() where society_id in (md5('tudsoc')::uuid, md5('atlsoc')::uuid)$$,
  array[md5('tudsoc')::uuid], 'or member counts');
select results_eq($$select society_id from public.society_member_counts where society_id in (md5('tudsoc')::uuid, md5('atlsoc')::uuid)$$,
  array[md5('tudsoc')::uuid], 'through the view either');
select is(public.society_member_count(md5('atlsoc')::uuid), 0, 'a single society''s count is 0');
select results_eq($$select event_id from public.event_attendee_counts() where event_id in (md5('tudevent')::uuid, md5('atlevent')::uuid)$$,
  array[md5('tudevent')::uuid], 'or attendee counts');
select is_empty($$select 1 from public.recommend_societies() where society_id = md5('atlsoc')::uuid$$, 'and isn''t recommended its societies, even on a shared interest');
select throws_ok($$select public.join_society(md5('atlsoc')::uuid)$$, 'P0001', 'That society doesn''t exist.', 'and can''t join them');
select throws_ok($$select public.register_for_event(md5('atlevent')::uuid)$$, 'P0001', 'That event doesn''t exist.', 'or register for their events');
select pg_temp.act_as('atlstudent');
select results_eq($$select id from public.societies$$, array[md5('atlsoc')::uuid], 'an Atlantic student sees only Atlantic''s society');

select pg_temp.act_as('tudchair');
select throws_ok($$insert into public.collaboration_proposals (society_a, society_b, title, created_by, source)
  values (md5('tudsoc')::uuid, md5('atlsoc')::uuid, 'Inter-university quiz', auth.uid(), 'committee')$$,
  '42501', null, 'a collaboration with another university''s society is refused');
select throws_ok($$update public.collaboration_proposals set society_b = md5('atlsoc')::uuid where id = md5('proposal')::uuid$$,
  '42501', null, 'including by pointing an existing one there');

-- TU Dublin's university admin
select pg_temp.act_as('tudadmin');
select is(pg_temp.changed($$insert into public.societies (id, slug, name, short_name, university_id)
  values (md5('tudnew')::uuid, 'iso-new', 'New Society', 'NewSoc', md5('tudublin')::uuid)$$), 1, 'a university admin creates a society');
select is(pg_temp.changed($$update public.societies set tagline = 'Edited' where id = md5('tudsoc')::uuid$$), 1, 'edits one');
select is(pg_temp.changed($$update public.societies set status = 'archived' where id = md5('tudnew')::uuid$$), 1, 'archives one');
select is(pg_temp.changed($$insert into public.role_invites (email, society_id, role) values ('newchair.iso@mytudublin.ie', md5('tudsoc')::uuid, 'committee')$$),
  1, 'invites a committee member');
select is(pg_temp.changed($$delete from public.society_roles where society_id = md5('tudsoc')::uuid and user_id = md5('tudchair')::uuid$$),
  1, 'removes one');
select results_eq($$select id from public.profiles where id in (md5('tudstudent')::uuid, md5('atlstudent')::uuid, md5('atlchair')::uuid)$$,
  array[md5('tudstudent')::uuid], 'sees their university''s people and not the other''s');
select results_eq($$select user_id from public.university_members where user_id in (md5('tudstudent')::uuid, md5('atlstudent')::uuid)$$,
  array[md5('tudstudent')::uuid], 'or their memberships');

select throws_ok($$insert into public.societies (slug, name, short_name, university_id) values ('iso-new', 'New Society', 'NewSoc', md5('atlantic')::uuid)$$,
  '42501', null, 'but can''t create one at another university');
select is(pg_temp.changed($$update public.societies set tagline = 'Edited' where id = md5('atlsoc')::uuid$$), 0, 'edit one there');
select is(pg_temp.changed($$update public.societies set status = 'archived' where id = md5('atlsoc')::uuid$$), 0, 'archive one there');
select throws_ok($$update public.societies set university_id = md5('atlantic')::uuid where id = md5('tudsoc')::uuid$$,
  'P0001', 'Only platform admins can move a society to another university.', 'move one there');
select throws_ok($$insert into public.role_invites (email, society_id, role) values ('newchair.iso@atlantic.test', md5('atlsoc')::uuid, 'committee')$$,
  '42501', null, 'invite to a committee there');
select is(pg_temp.changed($$delete from public.society_roles where society_id = md5('atlsoc')::uuid$$), 0, 'remove a committee there');
select throws_ok($$insert into public.role_invites (email, society_id, role) values ('newchair.iso@atlantic.test', md5('tudsoc')::uuid, 'committee')$$,
  'P0001', 'Invite an address at TU Dublin.', 'invite another university''s address to their own committee');
select throws_ok($$insert into public.role_invites (email, university_id, role) values ('newadmin.iso@mytudublin.ie', md5('tudublin')::uuid, 'university_admin')$$,
  '42501', null, 'invite a university admin');
select throws_ok($$insert into public.university_admins (university_id, user_id) values (md5('tudublin')::uuid, md5('tudstudent')::uuid)$$,
  '42501', null, 'or appoint one');

select is(public.my_access()->'university'->>'slug', 'tudublin', 'my_access gives a university admin their university');
select is((public.my_access()->>'university_admin')::boolean, true, 'and the admin flag');
select pg_temp.act_as('atlstudent');
select is(public.my_access()->'university'->>'slug', 'atlantic', 'and a student theirs');
select is((public.my_access()->>'university_admin')::boolean, false, 'without the flag');
reset role;

-- Invites and address changes
insert into public.role_invites (email, university_id, role) values ('newadmin.iso@atlantic.test', md5('atlantic')::uuid, 'university_admin');
insert into auth.users (id, email, aud, role) values (md5('atladmin')::uuid, 'newadmin.iso@atlantic.test', 'authenticated', 'authenticated');
select results_eq($$select university_id from public.university_admins where user_id = md5('atladmin')::uuid$$, array[md5('atlantic')::uuid],
  'a university admin invite makes a university admin on sign-up');
select throws_ok($$insert into public.role_invites (email, role) values ('newchair.iso@mytudublin.ie', 'committee')$$,
  '23514', 'new row for relation "role_invites" violates check constraint "role_invites_target_check"', 'a committee invite needs a society');
select throws_ok($$update auth.users set email = 'tudstudent.iso@atlantic.test' where id = md5('tudstudent')::uuid$$,
  'P0001', 'Your new address has to be at the same university.', 'an account can''t move to another university''s address');
select throws_ok($$update auth.users set email_change = 'tudstudent.iso@atlantic.test' where id = md5('tudstudent')::uuid$$,
  'P0001', 'Your new address has to be at the same university.', 'or ask to');
select lives_ok($$update auth.users set email = 'tudstudent.iso@tudublin.ie' where id = md5('tudstudent')::uuid$$,
  'but can move to the university''s other domain');

select * from finish();
rollback;
