-- Signing in with the university mailbox (or its Microsoft account) proves someone is still
-- at the university, but a session can stay signed in for years after they leave. Every
-- sign-in now counts as verification, and once a year without one, a nightly job ends the
-- account's sessions. The next sign-in needs the university address again, which fails once
-- the university has closed the account.
alter table public.university_members add column verified_at timestamptz not null default now();
update public.university_members m set verified_at = coalesce(u.last_sign_in_at, m.joined_at)
  from auth.users u where u.id = m.user_id;

create or replace function public.on_user_signed_in()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.university_members set verified_at = new.last_sign_in_at
    where user_id = new.id and new.last_sign_in_at is not null;
  return new;
end $$;
revoke execute on function public.on_user_signed_in() from public, anon, authenticated;
create trigger on_auth_user_signed_in after update of last_sign_in_at on auth.users
  for each row execute function public.on_user_signed_in();

create or replace function public.end_lapsed_sessions()
returns int language sql security definer set search_path = public as $$
  with gone as (
    delete from auth.sessions s using public.university_members m
    where m.user_id = s.user_id and m.verified_at < now() - interval '1 year'
    returning 1
  )
  select count(*)::int from gone
$$;
revoke execute on function public.end_lapsed_sessions() from public, anon, authenticated;
select cron.schedule('end-lapsed-sessions', '45 3 * * *', 'select public.end_lapsed_sessions()');
