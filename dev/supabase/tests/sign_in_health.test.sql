begin;
create extension if not exists pgtap with schema extensions;
select plan(6);

-- sign_in_health counts sign-in links sent between 24 hours and 30 minutes ago, and how many
-- were followed by a sign-in. Accounts are made up here; links sent to other local accounts
-- (by the browser journeys, say) are deleted first, inside this rolled-back test.
delete from auth.users where confirmation_sent_at > now() - interval '25 hours' or recovery_sent_at > now() - interval '25 hours';

select is(public.sign_in_health()->>'status', 'ok', 'with no links sent, all is well');

-- Six returning students got a magic link an hour ago; one signed in.
insert into auth.users (id, email, aud, role, email_confirmed_at, recovery_sent_at, last_sign_in_at)
  select gen_random_uuid(), 'r' || n || '.health@mytudublin.ie', 'authenticated', 'authenticated', now() - interval '30 days',
    now() - interval '1 hour', case when n = 1 then now() - interval '55 minutes' else now() - interval '10 days' end
  from generate_series(1, 6) n;
select is(public.sign_in_health()->'returning', '{"sent": 6, "used": 1}'::jsonb, 'it counts magic links and the sign-ins after them');
select is(public.sign_in_health()->>'status', 'degraded', 'and says sign-in emails probably aren''t arriving');

update auth.users set last_sign_in_at = recovery_sent_at + interval '2 minutes' where email like 'r%.health@mytudublin.ie';
select is(public.sign_in_health()->>'status', 'ok', 'once people sign in, it''s fine again');

-- New accounts: links sent in the last 30 minutes don't count yet.
insert into auth.users (id, email, aud, role, confirmation_sent_at)
  select gen_random_uuid(), 'n' || n || '.health@mytudublin.ie', 'authenticated', 'authenticated', now() - interval '5 minutes'
  from generate_series(1, 6) n;
select is(public.sign_in_health()->'new_accounts', '{"sent": 0, "used": 0}'::jsonb, 'links from the last 30 minutes wait');

set local role authenticated;
select throws_ok($$select public.sign_in_health()$$, '42501', null, 'signed-in users can''t read it');
reset role;

select * from finish();
rollback;
