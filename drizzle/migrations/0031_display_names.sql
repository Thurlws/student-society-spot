-- People appeared under the start of their email address, usually a student number, because
-- sign-up used it as the display name and onboarding offered it pre-filled. New accounts now
-- start without a name (or with the one their Microsoft account gives), and onboarding asks
-- what people should be called. The database refuses to finish onboarding without a name, or
-- with the start of the email address as the name.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles(id, display_name)
    values (new.id, left(coalesce(nullif(btrim(new.raw_user_meta_data->>'full_name'), ''),
                                  nullif(btrim(new.raw_user_meta_data->>'name'), ''), ''), 80));
  insert into public.notification_prefs(user_id) values (new.id);
  insert into public.university_members(user_id, university_id)
    select new.id, u from private.domain_university(new.email) u where u is not null;
  perform public.claim_invites(new.id, new.email);
  return new;
end $$;

-- Names that are only the start of the email address are cleared. Those people see "Someone"
-- until they sign in again, when the app asks them what to call them.
update public.profiles p set display_name = ''
  from auth.users u
  where u.id = p.id and lower(btrim(p.display_name)) = lower(split_part(u.email, '@', 1));

-- Checked when onboarding finishes and whenever the name changes afterwards, so a cleared name
-- doesn't block other changes to the profile.
create or replace function private.check_display_name()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.onboarded_at is not null
     and (tg_op = 'INSERT' or old.onboarded_at is null or new.display_name is distinct from old.display_name) then
    if char_length(btrim(new.display_name)) < 2 then
      raise exception 'Tell us what people should call you.';
    end if;
    if lower(btrim(new.display_name)) = (select lower(split_part(email, '@', 1)) from auth.users where id = new.id) then
      raise exception 'Use the name people know you by, not your email address.';
    end if;
  end if;
  return new;
end $$;
revoke execute on function private.check_display_name() from public, anon, authenticated;

create trigger profiles_display_name before insert or update of display_name, onboarded_at on public.profiles
  for each row execute function private.check_display_name();
