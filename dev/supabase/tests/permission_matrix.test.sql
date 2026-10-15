begin;
create extension if not exists pgtap with schema extensions;

-- Who can read and change what: every table, and every database function a signed-in user
-- can call, tried as each kind of user. Supabase grants every table to anon and
-- authenticated by default, so row-level security and function checks are the only
-- barrier, and this file is their specification. If a change here is intended, update the
-- expected row and say why in the commit.
--
-- Users, in the order of every expected array:
--   anon       signed out
--   student    signed in, no ties to any test society
--   applicant  waiting for approval at B
--   member     member of A and B
--   committee  committee of A
--   other      committee of B (another society's committee)
--   admin      platform admin
-- plus "bystander", who is never the one acting. Societies: A is open, B needs approval,
-- Z is archived. Every id is md5('<name>')::uuid so cases can name rows.
--
-- Results: a number (rows seen, or rows changed; signed-out visitors can't read the
-- interests some inserts select from, so those insert 0), "ok" (a function ran), "denied" (no
-- privilege or policy), "refused" (a function raised its own error) or a SQLSTATE.

insert into auth.users (id, email, aud, role)
  select md5(n)::uuid, n || '.matrix@mytudublin.ie', 'authenticated', 'authenticated'
  from unnest('{student,applicant,member,committee,other,admin,bystander}'::text[]) n;
insert into public.user_roles (user_id, role) values (md5('admin')::uuid, 'platform_admin');

insert into public.societies (id, slug, name, short_name, requires_approval, status) values
  (md5('A')::uuid, 'matrix-a', 'Matrix Open Society', 'OpenSoc', false, 'active'),
  (md5('B')::uuid, 'matrix-b', 'Matrix Approval Society', 'ApprSoc', true, 'active'),
  (md5('Z')::uuid, 'matrix-z', 'Matrix Archived Society', 'OldSoc', false, 'archived');
-- Channels and rooms are made by triggers; give them names we can use.
update public.channels c set id = md5(s.tag || ' ' || c.slug)::uuid
  from (values (md5('A')::uuid, 'A'), (md5('B')::uuid, 'B'), (md5('Z')::uuid, 'Z')) s(id, tag) where c.society_id = s.id;
update public.call_rooms r set id = md5(s.tag || ' ' || r.slug)::uuid
  from (values (md5('A')::uuid, 'A'), (md5('B')::uuid, 'B'), (md5('Z')::uuid, 'Z')) s(id, tag) where r.society_id = s.id;

insert into public.society_tags (society_id, interest_id)
  select md5(s)::uuid, (select id from public.interests where name = i) from (values ('A', 'Technology'), ('Z', 'Music')) v(s, i);
insert into public.society_roles (society_id, user_id, position) values
  (md5('A')::uuid, md5('committee')::uuid, 'Chair'),
  (md5('B')::uuid, md5('other')::uuid, 'Chair');
insert into public.society_memberships (id, society_id, user_id, status) values
  (md5('member at A')::uuid, md5('A')::uuid, md5('member')::uuid, 'member'),
  (md5('member at B')::uuid, md5('B')::uuid, md5('member')::uuid, 'member'),
  (md5('applicant at B')::uuid, md5('B')::uuid, md5('applicant')::uuid, 'pending');
insert into public.profile_interests (profile_id, interest_id)
  select md5(p)::uuid, (select id from public.interests where name = 'Technology') from unnest('{student,member}'::text[]) p;
insert into public.resources (id, society_id, title, kind) values
  (md5('resource A')::uuid, md5('A')::uuid, 'Kit list', 'Guide'),
  (md5('resource B')::uuid, md5('B')::uuid, 'Constitution', 'Document');
insert into public.role_invites (id, email, society_id, role) values
  (md5('invite')::uuid, 'invited.matrix@mytudublin.ie', md5('A')::uuid, 'committee');
insert into public.events (id, society_id, title, starts_at, venue, category, capacity) values
  (md5('event A')::uuid, md5('A')::uuid, 'Quiz night', now() + interval '7 days', 'Room 1', 'Social', 50),
  (md5('event B')::uuid, md5('B')::uuid, 'Workshop', now() + interval '7 days', 'Room 2', 'Workshop', 50),
  (md5('event Z')::uuid, md5('Z')::uuid, 'Old event', now() + interval '7 days', 'Room 3', 'Social', 50);
insert into public.event_registrations (event_id, user_id) values
  (md5('event A')::uuid, md5('member')::uuid),
  (md5('event B')::uuid, md5('student')::uuid);
insert into public.announcements (id, society_id, author_id, title, body) values
  (md5('announcement A')::uuid, md5('A')::uuid, md5('committee')::uuid, 'Welcome', 'Welcome to the society, everyone.'),
  (md5('announcement Z')::uuid, md5('Z')::uuid, null, 'Goodbye', 'This society has closed for now.');
insert into public.messages (id, channel_id, author_id, body) values
  (md5('message A')::uuid, md5('A general')::uuid, md5('member')::uuid, 'Hello A'),
  (md5('message B')::uuid, md5('B general')::uuid, md5('other')::uuid, 'Hello B');
insert into public.notifications (id, user_id, kind, title) values
  (md5('notification member')::uuid, md5('member')::uuid, 'events', 'For the member'),
  (md5('notification student')::uuid, md5('student')::uuid, 'events', 'For the student');
insert into public.support_requests (id, society_id, submitted_by, title, description, category) values
  (md5('request A')::uuid, md5('A')::uuid, md5('member')::uuid, 'Need a projector', 'For the quiz night on Friday.', 'equipment');
insert into public.support_request_activity (id, request_id, actor_id, kind, text) values
  (md5('activity A')::uuid, md5('request A')::uuid, md5('member')::uuid, 'created', 'Request submitted');
insert into public.collaboration_proposals (id, society_a, society_b, title, created_by, source) values
  (md5('proposal AB')::uuid, md5('A')::uuid, md5('B')::uuid, 'Joint quiz', md5('committee')::uuid, 'committee');
insert into public.saved_proposals (user_id, proposal_id) values (md5('committee')::uuid, md5('proposal AB')::uuid);
insert into public.call_participants (id, room_id, user_id, livekit_identity) values
  (md5('participant A')::uuid, md5('A lounge')::uuid, md5('member')::uuid, 'member');
insert into public.call_invites (id, room_id, code_hash, created_by, expires_at) values
  (md5('call invite A')::uuid, md5('A lounge')::uuid, 'matrix-hash', md5('committee')::uuid, now() + interval '1 day');
insert into public.call_recaps (id, room_id, society_id, title, summary, participant_ids, shared, created_by) values
  (md5('recap A private')::uuid, md5('A lounge')::uuid, md5('A')::uuid, 'Planning', '{}', array[md5('member')::uuid], false, null),
  (md5('recap A shared')::uuid, md5('A lounge')::uuid, md5('A')::uuid, 'AGM', '{}', '{}', true, md5('committee')::uuid);
insert into public.ai_usage (id, user_id, feature) values (md5('usage')::uuid, md5('student')::uuid, 'society_ask');
insert into public.society_fit_cache (user_id, society_id, reason, context_hash) values
  (md5('student')::uuid, md5('A')::uuid, 'Likes technology', 'h');
insert into public.society_ai_state (feature, status, message) values ('matrix-test', 503, 'Down for the test');

create temp table matrix_users (ord int, name text, uid uuid);
insert into matrix_users values
  (1, 'anon', null), (2, 'student', md5('student')::uuid), (3, 'applicant', md5('applicant')::uuid),
  (4, 'member', md5('member')::uuid), (5, 'committee', md5('committee')::uuid), (6, 'other', md5('other')::uuid),
  (7, 'admin', md5('admin')::uuid);

-- Runs one statement as a user inside a block that is always rolled back.
create function pg_temp.run_as(_uid uuid, _sql text, _kind text) returns text language plpgsql as $$
declare n bigint;
begin
  begin
    if _uid is null then
      perform set_config('request.jwt.claims', '{"role":"anon"}', true);
      set local role anon;
    else
      perform set_config('request.jwt.claims', json_build_object('sub', _uid, 'role', 'authenticated')::text, true);
      set local role authenticated;
    end if;
    if _kind = 'count' then execute format('select count(*) from (%s) q', _sql) into n;
    else execute _sql; get diagnostics n = row_count;
    end if;
    raise exception using errcode = 'TT001', message = case when _kind = 'call' then 'ok' else n::text end;
  exception
    when sqlstate 'TT001' then return sqlerrm;
    when insufficient_privilege then return 'denied';
    when raise_exception then return 'refused';
    when others then return sqlstate;
  end;
end $$;

create temp table matrix (ord serial, label text, kind text, sql text, expected text[]);
-- @people, @societies, @events: the test users, societies and events above.
insert into matrix (label, kind, sql, expected) values
-- Reads                                                                anon student applicant member committee other admin
('profiles: read', 'count', $$select 1 from public.profiles where id in @people$$, '{0,3,3,3,3,3,7}'),
('interests: read', 'count', $$select 1 from public.interests where name in ('Technology', 'Music')$$, '{0,2,2,2,2,2,2}'),
('profile_interests: read', 'count', $$select 1 from public.profile_interests where profile_id in @people$$, '{0,1,0,1,0,0,0}'),
('notification_prefs: read', 'count', $$select 1 from public.notification_prefs where user_id in @people$$, '{0,1,1,1,1,1,1}'),
('user_roles: read', 'count', $$select 1 from public.user_roles where user_id in @people$$, '{0,0,0,0,0,0,1}'),
('societies: read', 'count', $$select 1 from public.societies where id in @societies$$, '{0,2,2,2,2,2,3}'),
('society_tags: read', 'count', $$select 1 from public.society_tags where society_id in @societies$$, '{0,1,1,1,1,1,2}'),
('society_roles: read', 'count', $$select 1 from public.society_roles where society_id in @societies$$, '{0,2,2,2,2,2,2}'),
('society_memberships: read', 'count', $$select 1 from public.society_memberships where society_id in @societies$$, '{0,0,1,2,1,2,0}'),
('society_member_counts view: read', 'count', $$select 1 from public.society_member_counts where society_id in @societies$$, '{0,2,2,2,2,2,3}'),
('resources: read', 'count', $$select 1 from public.resources where society_id in @societies$$, '{0,0,0,2,1,1,2}'),
('role_invites: read', 'count', $$select 1 from public.role_invites where id = md5('invite')::uuid$$, '{0,0,0,0,0,0,1}'),
('events: read', 'count', $$select 1 from public.events where id in @events$$, '{0,2,2,2,2,2,3}'),
('event_registrations: read', 'count', $$select 1 from public.event_registrations where event_id in @events$$, '{0,1,0,1,0,0,0}'),
('announcements: read', 'count', $$select 1 from public.announcements where society_id in @societies$$, '{0,1,1,1,1,1,2}'),
('channels: read', 'count', $$select 1 from public.channels where society_id in @societies$$, '{0,0,0,6,3,3,0}'),
('messages: read', 'count', $$select 1 from public.messages where id in (md5('message A')::uuid, md5('message B')::uuid)$$, '{0,0,0,2,1,1,0}'),
('notifications: read', 'count', $$select 1 from public.notifications where id in (md5('notification member')::uuid, md5('notification student')::uuid)$$, '{0,1,0,1,0,0,0}'),
('support_requests: read', 'count', $$select 1 from public.support_requests where society_id in @societies$$, '{0,0,0,1,1,0,0}'),
('support_request_activity: read', 'count', $$select 1 from public.support_request_activity where id = md5('activity A')::uuid$$, '{0,0,0,1,1,0,0}'),
('collaboration_proposals: read', 'count', $$select 1 from public.collaboration_proposals where id = md5('proposal AB')::uuid$$, '{0,0,0,0,1,1,1}'),
('saved_proposals: read', 'count', $$select 1 from public.saved_proposals where proposal_id = md5('proposal AB')::uuid$$, '{0,0,0,0,1,0,0}'),
('call_rooms: read', 'count', $$select 1 from public.call_rooms where society_id in @societies$$, '{0,0,0,4,2,2,0}'),
('call_participants: read', 'count', $$select 1 from public.call_participants where id = md5('participant A')::uuid$$, '{0,0,0,1,1,0,0}'),
('call_invites: read', 'count', $$select 1 from public.call_invites where id = md5('call invite A')::uuid$$, '{0,0,0,0,1,0,0}'),
('call_recaps: read', 'count', $$select 1 from public.call_recaps where society_id in @societies$$, '{0,0,0,2,2,0,0}'),
('ai_usage: read', 'count', $$select 1 from public.ai_usage where user_id in @people$$, '{0,1,0,0,0,0,0}'),
('society_fit_cache: read', 'count', $$select 1 from public.society_fit_cache where society_id in @societies$$, '{0,1,0,0,0,0,0}'),
('society_ai_state: read', 'count', $$select 1 from public.society_ai_state$$, '{0,0,0,0,0,0,0}'),

-- Writes. "rows" is how many rows the statement changed (0 means RLS hid them).
('profiles: update own', 'rows', $$update public.profiles set display_name = display_name where id in @people$$, '{0,1,1,1,1,1,1}'),
('profiles: update someone else', 'rows', $$update public.profiles set display_name = 'x' where id = md5('bystander')::uuid$$, '{0,0,0,0,0,0,0}'),
('interests: add', 'rows', $$insert into public.interests (name) values ('Matrix')$$, '{denied,denied,denied,denied,denied,denied,denied}'),
('profile_interests: add own', 'rows', $$insert into public.profile_interests select auth.uid(), id from public.interests where name = 'Music'$$, '{0,1,1,1,1,1,1}'),
('profile_interests: add for someone else', 'rows', $$insert into public.profile_interests select md5('bystander')::uuid, id from public.interests where name = 'Music'$$, '{0,denied,denied,denied,denied,denied,denied}'),
('notification_prefs: update own', 'rows', $$update public.notification_prefs set events = events where user_id in @people$$, '{0,1,1,1,1,1,1}'),
('user_roles: make self admin', 'rows', $$insert into public.user_roles values (auth.uid(), 'platform_admin')$$, '{denied,denied,denied,denied,denied,denied,denied}'),
('societies: create', 'rows', $$insert into public.societies (slug, name, short_name) values ('matrix-new', 'Matrix New Society', 'NewSoc')$$, '{denied,denied,denied,denied,denied,denied,1}'),
('societies: edit A''s tagline', 'rows', $$update public.societies set tagline = 'New tagline' where id = md5('A')::uuid$$, '{0,0,0,0,1,0,1}'),
('societies: archive A', 'rows', $$update public.societies set status = 'archived' where id = md5('A')::uuid$$, '{0,0,0,0,refused,0,1}'),
('societies: change A''s join link', 'rows', $$update public.societies set join_url = 'https://example.com' where id = md5('A')::uuid$$, '{0,0,0,0,refused,0,1}'),
('societies: delete A', 'rows', $$delete from public.societies where id = md5('A')::uuid$$, '{0,0,0,0,0,0,0}'),
('society_tags: add to A', 'rows', $$insert into public.society_tags select md5('A')::uuid, id from public.interests where name = 'Music'$$, '{0,denied,denied,denied,denied,denied,1}'),
('society_tags: remove from A', 'rows', $$delete from public.society_tags where society_id = md5('A')::uuid$$, '{0,0,0,0,0,0,1}'),
('society_roles: join B''s committee', 'rows', $$insert into public.society_roles (society_id, user_id) values (md5('B')::uuid, auth.uid())$$, '{denied,denied,denied,denied,denied,denied,1}'),
('society_roles: edit A''s committee', 'rows', $$update public.society_roles set position = 'Treasurer' where society_id = md5('A')::uuid$$, '{0,0,0,0,0,0,1}'),
('society_roles: remove A''s committee', 'rows', $$delete from public.society_roles where society_id = md5('A')::uuid$$, '{0,0,0,0,0,0,1}'),
('society_memberships: add self to B', 'rows', $$insert into public.society_memberships (society_id, user_id, status) values (md5('B')::uuid, auth.uid(), 'member')$$, '{denied,denied,denied,denied,denied,denied,denied}'),
('society_memberships: approve directly', 'rows', $$update public.society_memberships set status = 'member' where id = md5('applicant at B')::uuid$$, '{0,0,0,0,0,0,0}'),
('society_memberships: delete', 'rows', $$delete from public.society_memberships where society_id in @societies$$, '{0,0,0,0,0,0,0}'),
('resources: add to A', 'rows', $$insert into public.resources (society_id, title, kind) values (md5('A')::uuid, 'Rota', 'Link')$$, '{denied,denied,denied,denied,1,denied,denied}'),
('resources: edit A''s', 'rows', $$update public.resources set title = 'Kit' where id = md5('resource A')::uuid$$, '{0,0,0,0,1,0,0}'),
('resources: delete A''s', 'rows', $$delete from public.resources where id = md5('resource A')::uuid$$, '{0,0,0,0,1,0,0}'),
('role_invites: invite an admin', 'rows', $$insert into public.role_invites (email, role) values ('new.admin@mytudublin.ie', 'platform_admin')$$, '{denied,denied,denied,denied,denied,denied,1}'),
('role_invites: delete', 'rows', $$delete from public.role_invites where id = md5('invite')::uuid$$, '{0,0,0,0,0,0,1}'),
('events: insert directly', 'rows', $$insert into public.events (society_id, title, starts_at, venue, category) values (md5('A')::uuid, 'Direct', now() + interval '1 day', 'Room', 'Social')$$, '{denied,denied,denied,denied,denied,denied,denied}'),
('events: edit A''s directly', 'rows', $$update public.events set title = 'Renamed' where id = md5('event A')::uuid$$, '{denied,denied,denied,denied,denied,denied,denied}'),
('events: delete A''s', 'rows', $$delete from public.events where id = md5('event A')::uuid$$, '{0,0,0,0,1,0,0}'),
('event_registrations: insert directly', 'rows', $$insert into public.event_registrations values (md5('event B')::uuid, auth.uid())$$, '{denied,denied,denied,denied,denied,denied,denied}'),
('event_registrations: delete directly', 'rows', $$delete from public.event_registrations where event_id in @events$$, '{0,0,0,0,0,0,0}'),
('announcements: post to A', 'rows', $$insert into public.announcements (society_id, author_id, title, body) values (md5('A')::uuid, auth.uid(), 'Hello', 'Hello from the matrix test.')$$, '{denied,denied,denied,denied,1,denied,denied}'),
('announcements: post to A as someone else', 'rows', $$insert into public.announcements (society_id, author_id, title, body) values (md5('A')::uuid, md5('bystander')::uuid, 'Hello', 'Hello from the matrix test.')$$, '{denied,denied,denied,denied,denied,denied,denied}'),
('announcements: edit A''s', 'rows', $$update public.announcements set title = 'Welcome back' where id = md5('announcement A')::uuid$$, '{0,0,0,0,1,0,0}'),
('announcements: change A''s author', 'rows', $$update public.announcements set author_id = md5('bystander')::uuid where id = md5('announcement A')::uuid$$, '{0,0,0,0,1,0,0}'),
('announcements: delete A''s', 'rows', $$delete from public.announcements where id = md5('announcement A')::uuid$$, '{0,0,0,0,1,0,0}'),
('channels: add', 'rows', $$insert into public.channels (society_id, slug, name) values (md5('A')::uuid, 'new', 'new')$$, '{denied,denied,denied,denied,denied,denied,denied}'),
('messages: post in A', 'rows', $$insert into public.messages (channel_id, author_id, body) values (md5('A general')::uuid, auth.uid(), 'Hi')$$, '{denied,denied,denied,1,1,denied,denied}'),
('messages: post in A as someone else', 'rows', $$insert into public.messages (channel_id, author_id, body) values (md5('A general')::uuid, md5('bystander')::uuid, 'Hi')$$, '{denied,denied,denied,denied,denied,denied,denied}'),
('messages: edit', 'rows', $$update public.messages set body = 'Edited' where id = md5('message A')::uuid$$, '{0,0,0,0,0,0,0}'),
('messages: delete directly', 'rows', $$delete from public.messages where id = md5('message A')::uuid$$, '{0,0,0,0,0,0,0}'),
('notifications: mark read', 'rows', $$update public.notifications set read_at = now() where id in (md5('notification member')::uuid, md5('notification student')::uuid)$$, '{0,1,0,1,0,0,0}'),
('notifications: create', 'rows', $$insert into public.notifications (user_id, kind, title) values (auth.uid(), 'events', 'Fake')$$, '{denied,denied,denied,denied,denied,denied,denied}'),
('notifications: delete', 'rows', $$delete from public.notifications where id in (md5('notification member')::uuid, md5('notification student')::uuid)$$, '{0,0,0,0,0,0,0}'),
('support_requests: insert directly', 'rows', $$insert into public.support_requests (society_id, submitted_by, title, description, category) values (md5('A')::uuid, auth.uid(), 'Direct insert', 'Skipping the function.', 'other')$$, '{denied,denied,denied,denied,denied,denied,denied}'),
('support_requests: edit directly', 'rows', $$update public.support_requests set status = 'resolved' where id = md5('request A')::uuid$$, '{0,0,0,0,0,0,0}'),
('support_request_activity: insert directly', 'rows', $$insert into public.support_request_activity (request_id, actor_id, kind, text) values (md5('request A')::uuid, auth.uid(), 'comment', 'Hi')$$, '{denied,denied,denied,denied,denied,denied,denied}'),
('collaboration_proposals: create for A and B', 'rows', $$insert into public.collaboration_proposals (society_a, society_b, title, created_by, source) values (md5('A')::uuid, md5('B')::uuid, 'Joint social', auth.uid(), 'committee')$$, '{denied,denied,denied,denied,1,1,denied}'),
('collaboration_proposals: edit', 'rows', $$update public.collaboration_proposals set title = 'Joint quiz night' where id = md5('proposal AB')::uuid$$, '{0,0,0,0,1,1,0}'),
('collaboration_proposals: delete', 'rows', $$delete from public.collaboration_proposals where id = md5('proposal AB')::uuid$$, '{0,0,0,0,0,0,0}'),
('saved_proposals: save', 'rows', $$insert into public.saved_proposals values (auth.uid(), md5('proposal AB')::uuid)$$, '{denied,1,1,1,23505,1,1}'),
('saved_proposals: unsave', 'rows', $$delete from public.saved_proposals where proposal_id = md5('proposal AB')::uuid$$, '{0,0,0,0,1,0,0}'),
('call_rooms: add', 'rows', $$insert into public.call_rooms (society_id, slug, name) values (md5('A')::uuid, 'new', 'New room')$$, '{denied,denied,denied,denied,denied,denied,denied}'),
('call_rooms: edit', 'rows', $$update public.call_rooms set name = 'Renamed' where society_id in @societies$$, '{0,0,0,0,0,0,0}'),
('call_participants: add', 'rows', $$insert into public.call_participants (room_id, user_id, livekit_identity) values (md5('A lounge')::uuid, auth.uid(), 'x')$$, '{denied,denied,denied,denied,denied,denied,denied}'),
('call_invites: create for A', 'rows', $$insert into public.call_invites (room_id, code_hash, created_by, expires_at) values (md5('A lounge')::uuid, 'matrix-new', auth.uid(), now() + interval '1 day')$$, '{denied,denied,denied,denied,1,denied,denied}'),
('call_invites: delete A''s', 'rows', $$delete from public.call_invites where id = md5('call invite A')::uuid$$, '{0,0,0,0,1,0,0}'),
('call_recaps: add', 'rows', $$insert into public.call_recaps (room_id, society_id, title, summary) values (md5('A lounge')::uuid, md5('A')::uuid, 'Fake', '{}')$$, '{denied,denied,denied,denied,denied,denied,denied}'),
('call_recaps: share directly', 'rows', $$update public.call_recaps set shared = true where id = md5('recap A private')::uuid$$, '{0,0,0,0,0,0,0}'),
('ai_usage: add', 'rows', $$insert into public.ai_usage (user_id, feature) values (auth.uid(), 'society_ask')$$, '{denied,denied,denied,denied,denied,denied,denied}'),
('ai_usage: clear own', 'rows', $$delete from public.ai_usage where user_id in @people$$, '{0,0,0,0,0,0,0}'),
('society_fit_cache: add', 'rows', $$insert into public.society_fit_cache (user_id, society_id, reason, context_hash) values (auth.uid(), md5('B')::uuid, 'x', 'x')$$, '{denied,denied,denied,denied,denied,denied,denied}'),
('society_ai_state: clear', 'rows', $$delete from public.society_ai_state$$, '{0,0,0,0,0,0,0}'),

-- Database functions. Signed-out visitors can't call any of them.
('join_society(A)', 'call', $$select public.join_society(md5('A')::uuid)$$, '{denied,ok,ok,refused,refused,ok,ok}'),
('join_society(B)', 'call', $$select public.join_society(md5('B')::uuid)$$, '{denied,ok,refused,refused,ok,refused,ok}'),
('join_society(Z, archived)', 'call', $$select public.join_society(md5('Z')::uuid)$$, '{denied,refused,refused,refused,refused,refused,refused}'),
('cancel_membership_request(B)', 'call', $$select public.cancel_membership_request(md5('B')::uuid)$$, '{denied,refused,ok,refused,refused,refused,refused}'),
('leave_society(A)', 'call', $$select public.leave_society(md5('A')::uuid)$$, '{denied,refused,refused,ok,refused,refused,refused}'),
('decide_membership(applicant at B)', 'call', $$select public.decide_membership(md5('applicant at B')::uuid, 'approve')$$, '{denied,refused,refused,refused,refused,ok,refused}'),
('society_members(B)', 'count', $$select * from public.society_members(md5('B')::uuid)$$, '{denied,0,0,0,0,2,0}'),
('register_for_event(A''s event)', 'call', $$select public.register_for_event(md5('event A')::uuid)$$, '{denied,ok,ok,refused,ok,ok,ok}'),
('register_for_event(Z''s event)', 'call', $$select public.register_for_event(md5('event Z')::uuid)$$, '{denied,refused,refused,refused,refused,refused,ok}'),
('update_event(A''s event)', 'call', $$select public.update_event(md5('event A')::uuid, 'Quiz night', '', current_date + 8, '19:00', null, 'Room 4', 'Social', 50)$$, '{denied,refused,refused,refused,ok,refused,refused}'),
('cancel_event(A''s event)', 'call', $$select public.cancel_event(md5('event A')::uuid, 'Room flooded')$$, '{denied,refused,refused,refused,ok,refused,refused}'),
('cancel_registration(A''s event)', 'call', $$select public.cancel_registration(md5('event A')::uuid)$$, '{denied,refused,refused,ok,refused,refused,refused}'),
('create_event(A)', 'call', $$select public.create_event(md5('A')::uuid, 'Board games', '', current_date + 7, '18:00', '20:00', 'Room 1', 'Social', 20)$$, '{denied,refused,refused,refused,ok,refused,refused}'),
('schedule_meeting(A)', 'call', $$select public.schedule_meeting(md5('A')::uuid, 'Planning call', '', current_date + 7, '18:00')$$, '{denied,refused,refused,refused,ok,refused,refused}'),
('submit_support_request(A)', 'call', $$select public.submit_support_request(md5('A')::uuid, 'Need a room', 'For the quiz night on Friday.', 'question', 'normal')$$, '{denied,refused,refused,ok,ok,refused,refused}'),
('assign_support_request(A''s request)', 'call', $$select public.assign_support_request(md5('request A')::uuid, md5('committee')::uuid)$$, '{denied,refused,refused,refused,ok,refused,refused}'),
('set_support_request_status(A''s request)', 'call', $$select public.set_support_request_status(md5('request A')::uuid, 'in_progress', '')$$, '{denied,refused,refused,refused,ok,refused,refused}'),
('comment_on_support_request(A''s request)', 'call', $$select public.comment_on_support_request(md5('request A')::uuid, 'Any update?')$$, '{denied,refused,refused,ok,ok,refused,refused}'),
('share_recap(A''s private recap)', 'call', $$select public.share_recap(md5('recap A private')::uuid)$$, '{denied,refused,refused,refused,ok,refused,refused}'),
('my_access()', 'call', $$select public.my_access()$$, '{denied,ok,ok,ok,ok,ok,ok}'),
('recommend_societies()', 'count', $$select 1 from public.recommend_societies() where society_id in @societies$$, '{denied,2,1,0,1,1,2}'),
('event_attendee_counts()', 'count', $$select 1 from public.event_attendee_counts() where event_id in @events$$, '{denied,2,2,2,2,2,2}'),
('society_member_counts()', 'count', $$select 1 from public.society_member_counts() where society_id in @societies$$, '{denied,2,2,2,2,2,2}'),
('society_member_count(A)', 'call', $$select public.society_member_count(md5('A')::uuid)$$, '{denied,ok,ok,ok,ok,ok,ok}');

update matrix set sql = replace(replace(replace(sql,
  '@people', $$(select md5(n)::uuid from unnest('{student,applicant,member,committee,other,admin,bystander}'::text[]) n)$$),
  '@societies', $$(md5('A')::uuid, md5('B')::uuid, md5('Z')::uuid)$$),
  '@events', $$(md5('event A')::uuid, md5('event B')::uuid, md5('event Z')::uuid)$$);

select plan((select count(*)::int * 7 from matrix) + 5);

select is(pg_temp.run_as(u.uid, m.sql, m.kind), m.expected[u.ord], m.label || ' as ' || u.name)
  from matrix m cross join matrix_users u order by m.ord, u.ord;

-- Guards for tables and functions added later.
select is_empty($$select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity$$, 'every table has row-level security on');
select is_empty($$select tablename || ': ' || policyname from pg_policies
  where schemaname = 'public' and cmd in ('SELECT', 'ALL') and btrim(qual) = 'true'$$, 'no read policy lets everyone in');
select set_eq($$select p.proname::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'private') and has_function_privilege('anon', p.oid, 'execute')$$,
  array['email_domain_allowed'], 'signed-out visitors can call no database function except the domain check');
select set_eq($$select p.proname::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prosecdef and has_function_privilege('authenticated', p.oid, 'execute')$$,
  array['assign_support_request', 'cancel_event', 'cancel_membership_request', 'cancel_registration', 'comment_on_support_request',
        'create_event', 'decide_membership', 'event_attendee_counts', 'join_society', 'leave_society', 'my_access',
        'recommend_societies', 'register_for_event', 'schedule_meeting', 'set_support_request_status', 'share_recap',
        'society_member_count', 'society_member_counts', 'society_members', 'submit_support_request', 'update_event'],
  'signed-in users can call only these owner-rights functions; a new one must be added here and to the matrix');
select is_empty($$select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prosecdef and not (p.proconfig @> array['search_path=public'] or p.proconfig @> array['search_path="public"'])$$,
  'owner-rights functions pin their search path');

select * from finish();
rollback;
