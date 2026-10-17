begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

-- Personal calendar links (0036). Who may call the functions is in the permission matrix; these
-- are the rules inside them. Ids are md5('<name>')::uuid.
insert into auth.users (id, email, aud, role)
  select md5(n)::uuid, n || '.cal@mytudublin.ie', 'authenticated', 'authenticated'
  from unnest('{ann,bob}'::text[]) n;
insert into public.societies (id, slug, name, short_name, university_id) values
  (md5('soc')::uuid, 'cal-soc', 'Calendar Test Society', 'CalSoc', md5('tudublin')::uuid);
insert into public.events (id, society_id, title, starts_at, ends_at, venue, category, cancelled_at) values
  (md5('quiz')::uuid, md5('soc')::uuid, 'Quiz night', now() + interval '3 days', now() + interval '3 days 2 hours', 'Room 1', 'Social', null),
  (md5('hike')::uuid, md5('soc')::uuid, 'Hike', now() + interval '5 days', null, 'Bray', 'Outdoors', now()),
  (md5('ball')::uuid, md5('soc')::uuid, 'Last year''s ball', now() - interval '200 days', null, 'Hall', 'Social', null),
  (md5('talk')::uuid, md5('soc')::uuid, 'Bob''s talk', now() + interval '4 days', null, 'Room 2', 'Talk', null);
insert into public.event_registrations (event_id, user_id) values
  (md5('quiz')::uuid, md5('ann')::uuid), (md5('hike')::uuid, md5('ann')::uuid),
  (md5('ball')::uuid, md5('ann')::uuid), (md5('talk')::uuid, md5('bob')::uuid);

create function pg_temp.act_as(_name text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', md5(_name)::uuid, 'role', 'authenticated')::text, true);
end $$;
-- The links, as the people who made them saw them.
create temp table links (which text, token text);
grant all on links to authenticated;
create function pg_temp.events_for(_which text) returns setof text language sql as $$
  select title || case when cancelled then ' (cancelled)' else '' end || ', ' || society
  from public.calendar_feed_events((select token from links where which = _which))
$$;

set local role authenticated;
select pg_temp.act_as('ann');
select lives_ok($$insert into links select 'first', public.create_calendar_feed()$$, 'a student makes a calendar link');
select is((select length(token) from links where which = 'first'), 64, 'it carries a long random key');
select results_eq($$select user_id from public.calendar_feeds$$, array[md5('ann')::uuid], 'they see that they have one');
select throws_ok($$select token_hash from public.calendar_feeds$$, '42501', null, 'but not even its hash');
select throws_ok($$select * from public.calendar_feed_events('x')$$, '42501', null, 'only the server reads the events behind a link');
select pg_temp.act_as('bob');
select is_empty($$select 1 from public.calendar_feeds$$, 'nobody else sees that they have one');

reset role;
select results_eq($$select pg_temp.events_for('first')$$,
  array['Quiz night, Calendar Test Society', 'Hike (cancelled), Calendar Test Society'],
  'the link gives the events they registered for, in order, cancelled ones marked and old ones left out');
select is_empty($$select 1 from public.calendar_feed_events('not a link')$$, 'an unknown link gives nothing');

set local role authenticated;
select pg_temp.act_as('ann');
select lives_ok($$insert into links select 'second', public.create_calendar_feed()$$, 'a new link can be made');
reset role;
select is_empty($$select pg_temp.events_for('first')$$, 'which turns the old one off');
select isnt_empty($$select pg_temp.events_for('second')$$, 'and the new one works');

update public.university_members set suspended_at = now(), suspension_reason = 'Testing' where user_id = md5('ann')::uuid;
select is_empty($$select pg_temp.events_for('second')$$, 'a suspended account''s link stops working');
update public.university_members set suspended_at = null, suspension_reason = '' where user_id = md5('ann')::uuid;

set local role authenticated;
select pg_temp.act_as('ann');
select lives_ok($$select public.delete_calendar_feed()$$, 'the link can be turned off');
reset role;
select is_empty($$select pg_temp.events_for('second')$$, 'and then it gives nothing');

select * from finish();
rollback;
