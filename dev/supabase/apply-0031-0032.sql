-- SocConnect: database updates 0031 and 0032 (display names, removal notices), all at once.
-- Generated 2026-10-16 from drizzle/migrations (unchanged). Lovable does not apply migration
-- files that arrive from GitHub, so paste ALL of this into Lovable: More, then Cloud, then SQL
-- editor, click Run and confirm. One transaction: everything goes in, or nothing changes.

begin;

do $check$
begin
  if to_regprocedure('private.check_display_name()') is not null then
    raise exception 'These updates are already in this database. Nothing was changed.';
  end if;
  if not exists (select 1 from pg_policies where tablename = 'saved_proposals' and policyname = 'Save own'
                 and with_check like '%collaboration_proposals%') then
    raise exception 'This database is missing earlier updates (0030). Nothing was changed. Send this message to Claude.';
  end if;
end $check$;

-- ===== 0031_display_names =====

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

-- ===== 0032_removal_notices =====

-- EU Digital Services Act, article 17: when a committee member or an admin removes someone's
-- message, its author is told it was removed, why if a reason was given, and what they can do.
-- Before, the message just disappeared. The notice uses the 'requests' kind, which is always
-- delivered whatever the person's notification settings, like membership decisions.
drop function public.delete_message(uuid);
create function public.delete_message(_message_id uuid, _reason text default '')
returns void language plpgsql security definer set search_path = public as $$
declare m public.messages; c public.channels; s public.societies; why text := left(btrim(coalesce(_reason, '')), 300);
begin
  select * into m from public.messages where id = _message_id for update;
  if found then select * into c from public.channels where id = m.channel_id; end if;
  if not found or not (private.is_society_member(c.society_id, auth.uid()) or private.can_manage_society(c.society_id, auth.uid())) then
    raise exception 'That message doesn''t exist.';
  end if;
  if not (coalesce(m.author_id = auth.uid(), false) or private.is_society_committee(c.society_id, auth.uid()) or private.can_manage_society(c.society_id, auth.uid())) then
    raise exception 'You can only delete your own messages.';
  end if;
  delete from public.messages where id = m.id;
  if m.author_id is not null and m.author_id is distinct from auth.uid() then
    select * into s from public.societies where id = c.society_id;
    perform public.notify_user(m.author_id, 'requests', 'Your message was removed',
      'Your message in ' || s.short_name || ' #' || c.name || ' ("'
        || left(m.body, 80) || case when char_length(m.body) > 80 then '…' else '' end || '") was removed by '
        || case when private.is_society_committee(c.society_id, auth.uid()) then 'the committee' else 'an admin' end
        || case when why <> '' then '. Reason: ' || why else '' end
        || '. If you think it was a mistake, send the committee a request from the society''s page.',
      jsonb_build_object('to', '/societies/$societyId', 'params', jsonb_build_object('societyId', s.slug)), null);
  end if;
end $$;
revoke execute on function public.delete_message(uuid, text) from public, anon;

-- ===== Bookkeeping =====
-- If Drizzle (Lovable's migration runner) keeps its record here, note these updates too.
do $record$
begin
  if to_regclass('drizzle.__drizzle_migrations') is not null then
    insert into drizzle.__drizzle_migrations (hash, created_at) values
      ('2f9b743b722f426a613e466850aefd4ce8cab083299a103fb6f2a970f1416064', 1792120371276),
      ('df031a04ba0ff750f7ccc7963af35bd91872b442009b116329599bb7c27b4636', 1792120431276);
  end if;
end $record$;

commit;
