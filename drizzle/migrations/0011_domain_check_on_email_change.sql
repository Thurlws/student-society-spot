-- enforce_email_domain only ran on sign-up, so a signed-in user could call
-- updateUser({ email }) and move their account to a personal address. Check the requested
-- address (email_change) and the final email on updates too, but only when they change,
-- so routine updates to existing accounts are never blocked.
create or replace function public.enforce_email_domain()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (tg_op = 'INSERT' or new.email is distinct from old.email)
     and (new.email is null or not public.email_domain_allowed(new.email)) then
    raise exception 'Please use your TU Dublin email (@mytudublin.ie)';
  end if;
  if tg_op = 'UPDATE' and new.email_change is distinct from old.email_change
     and coalesce(new.email_change, '') <> '' and not public.email_domain_allowed(new.email_change) then
    raise exception 'Please use your TU Dublin email (@mytudublin.ie)';
  end if;
  return new;
end $$;

create trigger enforce_email_domain_on_change before update of email, email_change on auth.users
  for each row execute function public.enforce_email_domain();
