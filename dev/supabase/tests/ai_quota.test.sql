begin;
create extension if not exists pgtap with schema extensions;
select plan(3);

insert into auth.users (id, email, aud, role) values
  ('00000000-0000-0000-0000-00000000c001', 'caption.user@mytudublin.ie', 'authenticated', 'authenticated');

select is(
  (select count(*)::int from generate_series(1, 601) where public.reserve_society_ai('00000000-0000-0000-0000-00000000c001', 'transcribe')),
  600, 'captions stop after 600 clips an hour');
select is(
  (select count(*)::int from generate_series(1, 11) where public.reserve_society_ai('00000000-0000-0000-0000-00000000c001', 'summary')),
  10, 'recaps stop after 10 an hour');
select ok(not public.reserve_society_ai('00000000-0000-0000-0000-00000000c001', 'unknown'), 'unknown features get no quota');

select * from finish();
rollback;
