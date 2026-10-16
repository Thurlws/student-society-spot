begin;
create extension if not exists pgtap with schema extensions;
select plan(7);

-- "lapsed" last proved they're at the university over a year ago; "recent" signs in now.
insert into auth.users (id, email, aud, role) values
  (md5('lapsed')::uuid, 'lapsed.reverify@mytudublin.ie', 'authenticated', 'authenticated'),
  (md5('recent')::uuid, 'recent.reverify@mytudublin.ie', 'authenticated', 'authenticated');
update public.university_members set verified_at = now() - interval '13 months' where user_id in (md5('lapsed')::uuid, md5('recent')::uuid);
insert into auth.sessions (id, user_id) values
  (md5('lapsed session')::uuid, md5('lapsed')::uuid), (md5('recent session')::uuid, md5('recent')::uuid);

update auth.users set last_sign_in_at = now() - interval '1 minute' where id = md5('recent')::uuid;
select is((select verified_at from public.university_members where user_id = md5('recent')::uuid), now() - interval '1 minute',
  'signing in counts as verifying');
select is((select verified_at from public.university_members where user_id = md5('lapsed')::uuid), now() - interval '13 months',
  'and only for the account that signed in');

select is(public.end_lapsed_sessions(), 1, 'the nightly job ends one session');
select results_eq($$select id from auth.sessions where id in (md5('lapsed session')::uuid, md5('recent session')::uuid)$$,
  array[md5('recent session')::uuid], 'the lapsed member''s, not the recent one''s');
select is((select schedule from cron.job where jobname = 'end-lapsed-sessions'), '45 3 * * *', 'it runs every night');

set local role authenticated;
select throws_ok($$select public.end_lapsed_sessions()$$, '42501', null, 'signed-in users can''t run it');
reset role;
set local role anon;
select throws_ok($$select public.end_lapsed_sessions()$$, '42501', null, 'or signed-out visitors');
reset role;

select * from finish();
rollback;
