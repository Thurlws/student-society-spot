begin;
create extension if not exists pgtap with schema extensions;
select plan(16);

-- Editing and cancelling events: what registered people and members are told, and what
-- a cancelled event refuses. Ids are md5('<name>')::uuid.
insert into auth.users (id, email, aud, role)
  select md5(n)::uuid, n || '.events@mytudublin.ie', 'authenticated', 'authenticated'
  from unnest('{chair,goer,fan,latecomer}'::text[]) n;
insert into public.societies (id, slug, name, short_name, university_id) values (md5('soc')::uuid, 'events-soc', 'Events Test Society', 'EvSoc', md5('tudublin')::uuid);
insert into public.society_roles (society_id, user_id) values (md5('soc')::uuid, md5('chair')::uuid);
-- goer is registered and a member, fan is only a member.
insert into public.society_memberships (society_id, user_id, status) values
  (md5('soc')::uuid, md5('goer')::uuid, 'member'), (md5('soc')::uuid, md5('fan')::uuid, 'member');
insert into public.events (id, society_id, title, starts_at, venue, category, capacity) values
  (md5('quiz')::uuid, md5('soc')::uuid, 'Quiz night', now() + interval '3 days', 'Room 1', 'Social', 10),
  (md5('old')::uuid, md5('soc')::uuid, 'Old quiz', now() - interval '3 days', 'Room 1', 'Social', null);
insert into public.event_registrations (event_id, user_id) values (md5('quiz')::uuid, md5('goer')::uuid);

create function pg_temp.act_as(_name text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', md5(_name)::uuid, 'role', 'authenticated')::text, true);
end $$;
create function pg_temp.notices(_name text, _title text) returns setof text language sql as $$
  select body from public.notifications where user_id = md5(_name)::uuid and title = _title and read_at is null
$$;
set local role authenticated;

-- Editing
select pg_temp.act_as('chair');
select lives_ok($$select public.update_event(md5('quiz')::uuid, 'Quiz night', 'Bring a pen', '2027-01-20', '19:30', '22:00', 'Room 2', 'Social', 10)$$, 'the committee edits an event');
select is((select starts_at from public.events where id = md5('quiz')::uuid), '2027-01-20 19:30:00+00'::timestamptz, 'new times are Dublin wall-clock times');
select lives_ok($$select public.update_event(md5('quiz')::uuid, 'Quiz night', 'Bring a pen', '2027-01-20', '20:00', '22:00', 'Room 2', 'Social', 10)$$, 'and moves it again');
select pg_temp.act_as('goer');
select results_eq($$select * from pg_temp.notices('goer', 'Event changed: Quiz night')$$, array['Wed 20 Jan, 20:00, Room 2'],
  'registered people get one notice with the latest time and place');
select pg_temp.act_as('fan');
select is_empty($$select * from pg_temp.notices('fan', 'Event changed: Quiz night')$$, 'members who aren''t going aren''t told about edits');
select pg_temp.act_as('chair');
select lives_ok($$select public.update_event(md5('quiz')::uuid, 'Quiz night!', 'Bring two pens', '2027-01-20', '20:00', '22:00', 'Room 2', 'Social', 10)$$, 'wording-only edits work');
select pg_temp.act_as('goer');
select is((select count(*)::int from public.notifications where user_id = md5('goer')::uuid and title like 'Event changed:%'), 1, 'and don''t notify anyone again');
select pg_temp.act_as('chair');
select throws_ok($$select public.update_event(md5('quiz')::uuid, 'Quiz night', '', '2027-01-20', '20:00', null, 'Room 2', 'Social', 0)$$,
  'P0001', 'The capacity can''t be lower than the 1 person already registered.', 'capacity can''t drop below the people already registered');
select throws_ok($$select public.update_event(md5('quiz')::uuid, 'Quiz night', '', current_date - 5, '20:00', null, 'Room 2', 'Social', 10)$$,
  'P0001', 'Pick today or a later date.', 'an event can''t be moved into the past');

-- Cancelling
select throws_ok($$select public.cancel_event(md5('old')::uuid, '')$$, 'P0001', 'This event has already taken place.', 'past events can''t be cancelled');
select lives_ok($$select public.cancel_event(md5('quiz')::uuid, 'The room is flooded.')$$, 'the committee cancels an event');
select throws_ok($$select public.cancel_event(md5('quiz')::uuid, '')$$, 'P0001', 'This event is already cancelled.', 'cancelling twice is refused');
select throws_ok($$select public.update_event(md5('quiz')::uuid, 'Quiz night', '', '2027-01-20', '20:00', null, 'Room 2', 'Social', 10)$$,
  'P0001', 'This event was cancelled, so it can''t be edited.', 'a cancelled event can''t be edited');
select pg_temp.act_as('goer');
select results_eq($$select * from pg_temp.notices('goer', 'Cancelled: Quiz night!')$$, array['The room is flooded.'], 'registered people are told once, with the reason');
select pg_temp.act_as('fan');
select results_eq($$select * from pg_temp.notices('fan', 'Cancelled: Quiz night!')$$, array['The room is flooded.'], 'members are told too');
select pg_temp.act_as('latecomer');
select throws_ok($$select public.register_for_event(md5('quiz')::uuid)$$, 'P0001', 'This event was cancelled.', 'a cancelled event takes no registrations');

reset role;
select * from finish();
rollback;
