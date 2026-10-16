begin;
create extension if not exists pgtap with schema extensions;
select plan(7);

-- Everyone gets a display name that isn't the start of their email address (0031).
insert into auth.users (id, email, aud, role, raw_user_meta_data) values
  (md5('plain')::uuid, 'c22999001@mytudublin.ie', 'authenticated', 'authenticated', '{}'),
  (md5('microsoft')::uuid, 'ms.names@mytudublin.ie', 'authenticated', 'authenticated', '{"full_name": "Niamh Kelly"}');

select is((select display_name from public.profiles where id = md5('plain')::uuid), '',
  'sign-up no longer uses the start of the email address as the name');
select is((select display_name from public.profiles where id = md5('microsoft')::uuid), 'Niamh Kelly',
  'a name from a Microsoft account is kept');

create function pg_temp.act_as(_name text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', md5(_name)::uuid, 'role', 'authenticated')::text, true);
end $$;
set local role authenticated;
select pg_temp.act_as('plain');
select throws_ok($$update public.profiles set onboarded_at = now() where id = auth.uid()$$,
  'P0001', 'Tell us what people should call you.', 'onboarding can''t finish without a name');
select throws_ok($$update public.profiles set display_name = 'C22999001', onboarded_at = now() where id = auth.uid()$$,
  'P0001', 'Use the name people know you by, not your email address.', 'or with the start of the email address as the name');
select lives_ok($$update public.profiles set display_name = 'Ciarán', onboarded_at = now() where id = auth.uid()$$,
  'it finishes with a real name');
reset role;

-- Someone onboarded before names were required, whose name was cleared, can still change
-- other things; the app asks them for a name.
-- (As migration 0031 left them: set without the trigger, which would refuse it now.)
set local session_replication_role = replica;
update public.profiles set display_name = '', onboarded_at = now() where id = md5('microsoft')::uuid;
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.act_as('microsoft');
select lives_ok($$update public.profiles set course = 'TU856' where id = auth.uid()$$,
  'a person without a name can still edit the rest of their profile');
select throws_ok($$update public.profiles set display_name = ' ' where id = auth.uid()$$,
  'P0001', 'Tell us what people should call you.', 'but can''t set a blank name');

select * from finish();
rollback;
