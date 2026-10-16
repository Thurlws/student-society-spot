begin;
create extension if not exists pgtap with schema extensions;
select plan(32);

-- The rules inside the write functions, beyond who may call them (that's the permission
-- matrix). Ids are md5('<name>')::uuid.
insert into auth.users (id, email, aud, role)
  select md5(n)::uuid, n || '.rules@mytudublin.ie', 'authenticated', 'authenticated'
  from unnest('{chair,treasurer,ann,bob,cara}'::text[]) n;
insert into public.societies (id, slug, name, short_name, requires_approval, university_id) values
  (md5('open')::uuid, 'rules-open', 'Rules Open Society', 'OpenRules', false, md5('tudublin')::uuid),
  (md5('closed')::uuid, 'rules-closed', 'Rules Closed Society', 'ClosedRules', true, md5('tudublin')::uuid);
insert into public.society_roles (society_id, user_id) values
  (md5('open')::uuid, md5('chair')::uuid), (md5('open')::uuid, md5('treasurer')::uuid), (md5('closed')::uuid, md5('chair')::uuid);
insert into public.events (id, society_id, title, starts_at, venue, category, capacity) values
  (md5('two seats')::uuid, md5('open')::uuid, 'Two seats', now() + interval '2 days', 'Room 1', 'Social', 2),
  (md5('finished')::uuid, md5('open')::uuid, 'Finished', now() - interval '2 days', 'Room 1', 'Social', null);

create function pg_temp.act_as(_name text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', md5(_name)::uuid, 'role', 'authenticated')::text, true);
end $$;
set local role authenticated;

-- Joining
select pg_temp.act_as('ann');
select is(public.join_society(md5('open')::uuid), 'member', 'an open society takes you in straight away');
select is(public.join_society(md5('closed')::uuid), 'pending', 'an approval-only society files a request');
select throws_ok($$select public.join_society(md5('closed')::uuid)$$, 'P0001', 'Your request to join ClosedRules is already pending.', 'a second request is refused');
select pg_temp.act_as('chair');
select is((select count(*)::int from public.notifications where title = 'New membership request' and body = 'ClosedRules'), 1, 'the committee hears about the request');
select lives_ok($$select public.decide_membership((select membership_id from public.society_members(md5('closed')::uuid) where user_id = md5('ann')::uuid), 'decline')$$, 'the committee declines');
select throws_ok($$select public.decide_membership((select membership_id from public.society_members(md5('closed')::uuid) where user_id = md5('ann')::uuid), 'approve')$$,
  'P0001', 'This request has already been handled.', 'a decided request can''t be decided again');
select pg_temp.act_as('ann');
select is((select count(*)::int from public.notifications where title = 'Your request to join ClosedRules was declined'), 1, 'the student hears the answer');
select is(public.join_society(md5('closed')::uuid), 'pending', 'a declined student can ask again');
select lives_ok($$select public.leave_society(md5('open')::uuid)$$, 'a member can leave');
select throws_ok($$select public.leave_society(md5('open')::uuid)$$, 'P0001', 'You''re not a member of OpenRules.', 'leaving twice is refused');
select pg_temp.act_as('chair');
select throws_ok($$select public.leave_society(md5('open')::uuid)$$, 'P0001', 'You''re on the OpenRules committee, so you can''t leave it here.', 'the committee can''t leave by accident');

-- Events
select pg_temp.act_as('ann');
select lives_ok($$select public.register_for_event(md5('two seats')::uuid)$$, 'registering works');
select throws_ok($$select public.register_for_event(md5('two seats')::uuid)$$, 'P0001', 'You''re already registered for this event.', 'registering twice is refused');
select throws_ok($$select public.register_for_event(md5('finished')::uuid)$$, 'P0001', 'This event has already taken place.', 'past events take no registrations');
select pg_temp.act_as('bob');
select lives_ok($$select public.register_for_event(md5('two seats')::uuid)$$, 'the last seat goes');
select pg_temp.act_as('cara');
select throws_ok($$select public.register_for_event(md5('two seats')::uuid)$$, 'P0001', 'This event is full.', 'capacity stops the next registration');
select pg_temp.act_as('bob');
select lives_ok($$select public.cancel_registration(md5('two seats')::uuid)$$, 'cancelling frees the seat');
select pg_temp.act_as('cara');
select lives_ok($$select public.register_for_event(md5('two seats')::uuid)$$, 'and someone else can take it');
select pg_temp.act_as('chair');
select throws_ok($$select public.create_event(md5('open')::uuid, 'Too late', '', current_date - 3, '18:00', null, 'Room 1', 'Social', null)$$,
  'P0001', 'Pick today or a later date.', 'events can''t start in the past');
select lives_ok($$select public.create_event(md5('open')::uuid, 'Winter social', '', '2027-01-15', '19:30', '22:00', 'Room 1', 'Social', null)$$, 'the committee creates an event');
select lives_ok($$select public.create_event(md5('open')::uuid, 'Summer social', '', '2027-06-15', '19:30', null, 'Room 1', 'Social', null)$$, 'and another');
select is((select starts_at from public.events where title = 'Winter social'), '2027-01-15 19:30:00+00'::timestamptz, 'event times are Dublin wall-clock times (GMT in winter)');
select is((select starts_at from public.events where title = 'Summer social'), '2027-06-15 18:30:00+00'::timestamptz, 'and Irish Summer Time in summer');
select throws_ok($$select public.schedule_meeting(md5('open')::uuid, 'x', '', current_date + 1, '18:00')$$, 'P0001', 'Give the call a title.', 'calls need a title');

-- Requests to the committee
select pg_temp.act_as('ann');
select lives_ok($$select public.join_society(md5('open')::uuid)$$, 'ann rejoins');
select lives_ok($$select public.submit_support_request(md5('open')::uuid, 'Need a locker', 'Somewhere to keep the kit.', 'equipment', 'normal')$$, 'a member sends a request');
select pg_temp.act_as('chair');
select throws_ok($$select public.assign_support_request((select id from public.support_requests where title = 'Need a locker'), md5('ann')::uuid)$$,
  'P0001', 'Pick someone on this society''s committee.', 'requests go only to committee members');
select lives_ok($$select public.assign_support_request((select id from public.support_requests where title = 'Need a locker'), md5('treasurer')::uuid)$$, 'assigning to the treasurer works');
select throws_ok($$select public.set_support_request_status((select id from public.support_requests where title = 'Need a locker'), 'resolved', '')$$,
  'P0001', 'Add a resolution note so the member knows the outcome.', 'resolving needs a note');
select throws_ok($$select public.set_support_request_status((select id from public.support_requests where title = 'Need a locker'), 'open', '')$$,
  'P0001', 'Can''t move a request from Open to Open.', 'status moves follow the lifecycle');
select lives_ok($$select public.set_support_request_status((select id from public.support_requests where title = 'Need a locker'), 'resolved', 'Locker 12 is yours.')$$, 'resolving with a note works');
select pg_temp.act_as('ann');
select is((select count(*)::int from public.support_request_activity a join public.support_requests r on r.id = a.request_id where r.title = 'Need a locker'), 3,
  'the member sees the whole history: created, assigned, resolved');

reset role;
select * from finish();
rollback;
