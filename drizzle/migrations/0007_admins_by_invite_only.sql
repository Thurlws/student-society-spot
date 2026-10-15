-- Staff addresses (@tudublin.ie) no longer become platform admins on sign-up. Platform
-- admins are granted only through role_invites with society_id null (see claim_invites).
-- Existing admin rows are kept; review them with:
--   select u.email from public.user_roles r join auth.users u on u.id = r.user_id;
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles(id, display_name)
    values (new.id, coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)));
  insert into public.notification_prefs(user_id) values (new.id);
  perform public.claim_invites(new.id, new.email);
  return new;
end $$;
