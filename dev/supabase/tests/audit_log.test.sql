begin;
create extension if not exists pgtap with schema extensions;
select plan(26);

-- The audit log: what gets recorded, as whom, and who can read it. TU Dublin's society
-- "soc" has a committee (chair) and members; AuditU is a second university with its own
-- admin. Ids are md5('<name>')::uuid.
insert into public.universities (id, slug, name, short_name) values (md5('auditu')::uuid, 'auditu', 'Audit University', 'AuditU');
insert into public.university_domains (domain, university_id) values ('auditu.test', md5('auditu')::uuid);
insert into auth.users (id, email, aud, role)
  select md5(n)::uuid, n || '.audit@' || case when n = 'atladmin' then 'auditu.test' else 'mytudublin.ie' end, 'authenticated', 'authenticated'
  from unnest('{padmin,tudadmin,chair,member,reader,applicant,atladmin}'::text[]) n;
insert into public.user_roles (user_id, role) values (md5('padmin')::uuid, 'platform_admin');
insert into public.university_admins (university_id, user_id) values
  (md5('tudublin')::uuid, md5('tudadmin')::uuid), (md5('auditu')::uuid, md5('atladmin')::uuid);
insert into public.societies (id, slug, name, short_name, requires_approval, university_id) values
  (md5('soc')::uuid, 'audit-soc', 'Audit Test Society', 'AuditSoc', true, md5('tudublin')::uuid);
insert into public.society_roles (society_id, user_id, position) values (md5('soc')::uuid, md5('chair')::uuid, 'Chair');
insert into public.society_memberships (id, society_id, user_id, status) values
  (md5('m1')::uuid, md5('soc')::uuid, md5('member')::uuid, 'member'),
  (md5('m2')::uuid, md5('soc')::uuid, md5('reader')::uuid, 'member'),
  (md5('m3')::uuid, md5('soc')::uuid, md5('applicant')::uuid, 'pending');
insert into public.messages (id, channel_id, author_id, body)
  select md5(v.id)::uuid, c.id, md5(v.author)::uuid, v.body from public.channels c
  cross join (values ('rude', 'member', 'Rude words'), ('mine', 'reader', 'Typo here'), ('spam', 'member', 'Buy now')) v(id, author, body)
  where c.society_id = md5('soc')::uuid and c.slug = 'general';
insert into public.events (id, society_id, title, starts_at, venue, category) values
  (md5('event')::uuid, md5('soc')::uuid, 'Quiz night', now() + interval '7 days', 'Room 1', 'Social');

create function pg_temp.act_as(_name text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', case when _name is null then '' else json_build_object('sub', md5(_name)::uuid, 'role', 'authenticated')::text end, true);
end $$;
-- The newest entry for an action, as postgres.
create function pg_temp.last(_action text) returns public.audit_log language sql as $$
  select * from public.audit_log where action = _action order by id desc limit 1
$$;

select is((pg_temp.last('committee.added')).subject_id, md5('chair')::uuid, 'setting up a committee seat by hand is logged too');
select is((pg_temp.last('committee.added')).actor_role, 'system', 'with no actor');

-- Invites and the grants they lead to
set local role authenticated;
select pg_temp.act_as('padmin');
insert into public.role_invites (email, role) values ('newadmin.audit@mytudublin.ie', 'platform_admin');
reset role;
select is((pg_temp.last('invite.created')).details->>'email', 'newadmin.audit@mytudublin.ie', 'a platform admin invite is logged with its address');
select is((pg_temp.last('invite.created')).actor_role, 'platform_admin', 'and the platform admin who sent it');
select pg_temp.act_as(null);
insert into auth.users (id, email, aud, role) values (md5('newadmin')::uuid, 'newadmin.audit@mytudublin.ie', 'authenticated', 'authenticated');
select ok((select actor_id is null and actor_role = 'system' and subject_id = md5('newadmin')::uuid and university_id is null
  from pg_temp.last('platform_admin.added')), 'claiming it at sign-up logs the new platform admin');

set local role authenticated;
select pg_temp.act_as('tudadmin');
insert into public.role_invites (email, society_id, role, position) values ('reader.audit@mytudublin.ie', md5('soc')::uuid, 'committee', 'Treasurer');
reset role;
select ok((select (actor_id, actor_role, subject_id, university_id) = (md5('tudadmin')::uuid, 'university_admin', md5('reader')::uuid, md5('tudublin')::uuid)
  from pg_temp.last('committee.added')), 'an invite for an existing account gives the seat at once, logged as the university admin''s');

-- Societies
set local role authenticated;
select pg_temp.act_as('tudadmin');
update public.societies set status = 'archived' where id = md5('soc')::uuid;
update public.societies set status = 'active' where id = md5('soc')::uuid;
update public.societies set name = 'Totally Official Society' where id = md5('soc')::uuid;
select pg_temp.act_as('chair');
update public.societies set tagline = 'New tagline' where id = md5('soc')::uuid;
reset role;
select results_eq($$select action from public.audit_log where society_id = md5('soc')::uuid and action like 'society.%' order by id$$,
  array['society.created', 'society.archived', 'society.restored', 'society.renamed'], 'archiving, restoring and renaming are logged; a new tagline isn''t');
select ok((select actor_role = 'university_admin' and details->'from'->>'name' = 'Audit Test Society' and details->'to'->>'name' = 'Totally Official Society'
  from pg_temp.last('society.renamed')), 'a rename keeps the old and new names');

-- Moderation
set local role authenticated;
select pg_temp.act_as('reader');
select public.delete_message(md5('mine')::uuid);
select public.report_message(md5('spam')::uuid, 'Spam');
reset role;
insert into public.society_memberships (society_id, user_id, status) values (md5('soc')::uuid, md5('padmin')::uuid, 'member');
set local role authenticated;
select pg_temp.act_as('padmin');
select public.report_message(md5('spam')::uuid, 'Also spam');
select pg_temp.act_as('chair');
select public.dismiss_message_reports(md5('spam')::uuid);
select public.delete_message(md5('rude')::uuid);
select public.decide_membership(md5('m3')::uuid, 'approve');
select public.cancel_event(md5('event')::uuid, 'Room flooded');
reset role;
select is((select count(*)::int from public.audit_log where action = 'message.removed'), 1, 'an author deleting their own message isn''t logged; a removal is');
select ok((select actor_id = md5('chair')::uuid and subject_id is null and details = '{"channel": "general", "reported": false}'
  from pg_temp.last('message.removed')), 'the removal names the channel, not the author');
select is((select count(*)::int from public.audit_log where action = 'reports.dismissed'), 1, 'dismissing two reports about a message is one entry');
select is((pg_temp.last('reports.dismissed')).details->>'reports', '2', 'which counts them');
select is((pg_temp.last('event.cancelled')).details->>'reason', 'Room flooded', 'cancelling an event is logged with the reason');
select is_empty($$select 1 from public.audit_log where action like 'membership%' or subject_id = md5('applicant')::uuid$$,
  'membership decisions aren''t logged, so the log doesn''t reveal who belongs to which society');

-- Committee seats, domains and accounts
set local role authenticated;
select pg_temp.act_as('tudadmin');
update public.society_roles set position = 'Vice chair' where user_id = md5('reader')::uuid;
delete from public.society_roles where user_id = md5('reader')::uuid;
select pg_temp.act_as('padmin');
insert into public.university_domains values ('staff.auditu.test', md5('auditu')::uuid);
delete from public.university_domains where domain = 'staff.auditu.test';
reset role;
select results_eq($$select action || ': ' || coalesce(details->'to'->>'position', details->>'position', '') from public.audit_log
  where subject_id = md5('reader')::uuid order by id$$,
  array['committee.added: Treasurer', 'committee.changed: Vice chair', 'committee.removed: Vice chair'], 'a seat''s changes and removal are logged');
select results_eq($$select action from public.audit_log where university_id = md5('auditu')::uuid and action like 'domain.%' order by id$$,
  array['domain.added', 'domain.added', 'domain.removed'], 'adding and removing domains is logged');
select pg_temp.act_as(null);
delete from auth.users where id = md5('chair')::uuid;
select ok((select university_id = md5('tudublin')::uuid and actor_role = 'system' from pg_temp.last('account.deleted')), 'deleting an account is logged under its university');
select is_empty($$select 1 from public.audit_log where action = 'committee.removed' and subject_id = md5('chair')::uuid$$,
  'the seats that go with it aren''t logged one by one');

-- Who reads it
set local role authenticated;
select pg_temp.act_as('tudadmin');
select is((select count(*)::int from public.audit_log where university_id is distinct from md5('tudublin')::uuid), 0, 'a university admin reads only their university''s entries');
select ok((select count(*) > 0 from public.audit_log where society_id = md5('soc')::uuid), 'including its societies''');
select pg_temp.act_as('atladmin');
select results_eq($$select distinct university_id from public.audit_log$$, array[md5('auditu')::uuid], 'AuditU''s admin reads AuditU''s');
select pg_temp.act_as('member');
select is_empty($$select 1 from public.audit_log$$, 'members and committees read nothing');
select pg_temp.act_as('padmin');
select ok((select count(*) from public.audit_log where university_id is null) > 0, 'platform admins read platform-level entries too');

-- Nobody rewrites it
select throws_ok($$update public.audit_log set action = 'nothing'$$, '42501', null, 'not even a platform admin can edit entries');
select throws_ok($$delete from public.audit_log$$, '42501', null, 'or delete them');
reset role;
set local role service_role;
select throws_ok($$delete from public.audit_log$$, '42501', null, 'nor can the server''s service role');
reset role;

select * from finish();
rollback;
