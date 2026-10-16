-- Each university's people see only their own university: its societies, their events,
-- announcements and committees, and the profiles of people they share a society with.
-- Platform admins keep seeing everything. University admins manage their own university's
-- societies, committees, tags, invites and reports, the way platform admins do for all of
-- them. Sign-up accepts any listed university domain and records the account's university,
-- and an account can't move to another university's address.

-- ===== Helpers (private: the API can't call them) =====
create function private.domain_university(_email text)
returns uuid language sql stable security definer set search_path = public as $$
  select university_id from public.university_domains where domain = split_part(lower(_email), '@', 2)
$$;

create function private.user_university(_uid uuid)
returns uuid language sql stable security definer set search_path = public as $$
  select university_id from public.university_members where user_id = _uid
$$;

create function private.society_university(_society_id uuid)
returns uuid language sql stable security definer set search_path = public as $$
  select university_id from public.societies where id = _society_id
$$;

-- Platform admins manage every university; university admins their own. A null university
-- (a society or profile that doesn't exist) is for platform admins only.
create function private.can_manage_university(_university_id uuid, _uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select _uid is not null and (
    private.has_role(_uid, 'platform_admin')
    or exists (select 1 from public.university_admins where university_id = _university_id and user_id = _uid)
  )
$$;

create function private.can_manage_society(_society_id uuid, _uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select private.can_manage_university(private.society_university(_society_id), _uid)
$$;

-- New functions are executable by everyone by default; policies run as the signed-in user.
revoke execute on function private.domain_university(text), private.user_university(uuid), private.society_university(uuid),
  private.can_manage_university(uuid, uuid), private.can_manage_society(uuid, uuid) from public, anon;
grant execute on function private.domain_university(text), private.user_university(uuid), private.society_university(uuid),
  private.can_manage_university(uuid, uuid), private.can_manage_society(uuid, uuid) to authenticated;

create or replace function private.society_visible(_society_id uuid, _uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select _uid is not null and exists (
    select 1 from public.societies s where s.id = _society_id and (
      (s.status = 'active' and s.university_id = private.user_university(_uid))
      or private.can_manage_university(s.university_id, _uid)
      or private.is_society_committee(s.id, _uid)
    )
  )
$$;

create or replace function private.can_see_profile(_profile uuid, _uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select _uid is not null and (
    _profile = _uid
    -- admins see their university's people (platform admins everyone's)
    or private.can_manage_university(private.user_university(_profile), _uid)
    -- committee members are public contacts for the societies you can see
    or exists (select 1 from public.society_roles where user_id = _profile and private.society_visible(society_id, _uid))
    -- people who share a society (member or committee) can see each other; a pending
    -- request doesn't count, or asking to join would reveal the members
    or exists (
      select 1
      from (select society_id from public.society_memberships where user_id = _uid and status = 'member'
            union select society_id from public.society_roles where user_id = _uid) mine
      join (select society_id from public.society_memberships where user_id = _profile and status = 'member'
            union select society_id from public.society_roles where user_id = _profile) theirs
        on mine.society_id = theirs.society_id
    )
  )
$$;

-- ===== Universities =====
grant select on public.universities, public.university_domains, public.university_members, public.university_admins to authenticated;
grant insert, update, delete on public.universities to authenticated;
grant insert, delete on public.university_domains, public.university_admins to authenticated;

create policy "Read own or managed university" on public.universities for select to authenticated
  using (id = private.user_university(auth.uid()) or private.can_manage_university(id, auth.uid()));
create policy "Platform admins add universities" on public.universities for insert to authenticated
  with check (private.has_role(auth.uid(), 'platform_admin'));
create policy "Platform admins edit universities" on public.universities for update to authenticated
  using (private.has_role(auth.uid(), 'platform_admin')) with check (private.has_role(auth.uid(), 'platform_admin'));
create policy "Platform admins remove universities" on public.universities for delete to authenticated
  using (private.has_role(auth.uid(), 'platform_admin'));

create policy "Admins read domains" on public.university_domains for select to authenticated
  using (private.can_manage_university(university_id, auth.uid()));
create policy "Platform admins add domains" on public.university_domains for insert to authenticated
  with check (private.has_role(auth.uid(), 'platform_admin'));
create policy "Platform admins remove domains" on public.university_domains for delete to authenticated
  using (private.has_role(auth.uid(), 'platform_admin'));

create policy "Read own or managed membership" on public.university_members for select to authenticated
  using (user_id = auth.uid() or private.can_manage_university(university_id, auth.uid()));

create policy "Read own or managed admins" on public.university_admins for select to authenticated
  using (user_id = auth.uid() or private.can_manage_university(university_id, auth.uid()));
create policy "Platform admins add university admins" on public.university_admins for insert to authenticated
  with check (private.has_role(auth.uid(), 'platform_admin') and private.user_university(user_id) = university_id);
create policy "Platform admins remove university admins" on public.university_admins for delete to authenticated
  using (private.has_role(auth.uid(), 'platform_admin'));

-- ===== Societies and what hangs off them =====
drop policy "Read active societies" on public.societies;
create policy "Read societies" on public.societies for select to authenticated
  using ((status = 'active' and university_id = private.user_university(auth.uid())) or private.can_manage_university(university_id, auth.uid()));
drop policy "Admins create societies" on public.societies;
create policy "Admins create societies" on public.societies for insert to authenticated
  with check (private.can_manage_university(university_id, auth.uid()));
drop policy "Admins or committee update societies" on public.societies;
create policy "Admins or committee update societies" on public.societies for update to authenticated
  using (private.can_manage_university(university_id, auth.uid()) or private.is_society_committee(id, auth.uid()))
  with check (private.can_manage_university(university_id, auth.uid()) or private.is_society_committee(id, auth.uid()));

create or replace function public.guard_society_update()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and not private.has_role(auth.uid(), 'platform_admin') then
    if new.university_id is distinct from old.university_id then
      raise exception 'Only platform admins can move a society to another university.';
    end if;
    if not private.can_manage_university(old.university_id, auth.uid()) then
      if new.slug is distinct from old.slug or new.status is distinct from old.status then
        raise exception 'Only your university''s admins can change a society''s address or archive it.';
      end if;
      if new.source is distinct from old.source or new.source_id is distinct from old.source_id
         or new.source_snapshot is distinct from old.source_snapshot or new.source_synced_at is distinct from old.source_synced_at
         or new.join_url is distinct from old.join_url or new.official_url is distinct from old.official_url then
        raise exception 'Official society links can only be changed by an import or an admin.';
      end if;
    end if;
  end if;
  return new;
end $$;

drop policy "Admins add tags" on public.society_tags;
create policy "Admins add tags" on public.society_tags for insert to authenticated
  with check (private.can_manage_society(society_id, auth.uid()));
drop policy "Admins remove tags" on public.society_tags;
create policy "Admins remove tags" on public.society_tags for delete to authenticated
  using (private.can_manage_society(society_id, auth.uid()));

-- Committee seats only for people at the society's university.
drop policy "Admins add committee" on public.society_roles;
create policy "Admins add committee" on public.society_roles for insert to authenticated
  with check (private.can_manage_society(society_id, auth.uid()) and private.user_university(user_id) = private.society_university(society_id));
drop policy "Admins edit committee" on public.society_roles;
create policy "Admins edit committee" on public.society_roles for update to authenticated
  using (private.can_manage_society(society_id, auth.uid()))
  with check (private.can_manage_society(society_id, auth.uid()) and private.user_university(user_id) = private.society_university(society_id));
drop policy "Admins remove committee" on public.society_roles;
create policy "Admins remove committee" on public.society_roles for delete to authenticated
  using (private.can_manage_society(society_id, auth.uid()));

drop policy "Read resources" on public.resources;
create policy "Read resources" on public.resources for select to authenticated
  using (private.is_society_member(society_id, auth.uid()) or private.can_manage_society(society_id, auth.uid()));

drop policy "Read proposals" on public.collaboration_proposals;
create policy "Read proposals" on public.collaboration_proposals for select to authenticated
  using (
    created_by = auth.uid()
    or private.is_society_committee(society_a, auth.uid())
    or private.is_society_committee(society_b, auth.uid())
    or private.can_manage_society(society_a, auth.uid())
  );
-- An edit could point a proposal at another university's society, which creating one can't.
drop policy "Committee edits proposals" on public.collaboration_proposals;
create policy "Committee edits proposals" on public.collaboration_proposals for update to authenticated
  using (private.is_society_committee(society_a, auth.uid()) or private.is_society_committee(society_b, auth.uid()))
  with check ((private.is_society_committee(society_a, auth.uid()) or private.is_society_committee(society_b, auth.uid()))
    and private.society_university(society_a) = private.society_university(society_b));

drop policy "Committee, admins and the reporter read reports" on public.message_reports;
create policy "Committee, admins and the reporter read reports" on public.message_reports for select to authenticated
  using (reported_by = auth.uid()
    or (private.is_society_committee(society_id, auth.uid()) and author_id <> auth.uid())
    or private.can_manage_society(society_id, auth.uid()));

create or replace function public.delete_message(_message_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare m public.messages; c public.channels;
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
end $$;

create or replace function public.dismiss_message_reports(_message_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare r public.message_reports;
begin
  select * into r from public.message_reports where message_id = _message_id limit 1;
  if not found or not (private.is_society_committee(r.society_id, auth.uid()) or private.can_manage_society(r.society_id, auth.uid())) then
    raise exception 'Only the society''s committee or an admin can dismiss reports.';
  end if;
  if r.author_id = auth.uid() and not private.can_manage_society(r.society_id, auth.uid()) then
    raise exception 'Reports about your own message are for the rest of the committee to handle.';
  end if;
  update public.message_reports set dismissed_at = now(), dismissed_by = auth.uid() where message_id = _message_id and dismissed_at is null;
  if not found then raise exception 'There are no open reports for this message.'; end if;
end $$;

create or replace function public.join_society(_society_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare s public.societies; cur text; _uid uuid := auth.uid();
begin
  if _uid is null then raise exception 'Please sign in first.'; end if;
  select * into s from public.societies where id = _society_id and status = 'active' and university_id = private.user_university(_uid);
  if not found then raise exception 'That society doesn''t exist.'; end if;
  select status into cur from public.society_memberships where society_id = _society_id and user_id = _uid;
  if cur = 'member' or private.is_society_committee(_society_id, _uid) then raise exception 'You''re already a member of %.', s.short_name; end if;
  if cur = 'pending' then raise exception 'Your request to join % is already pending.', s.short_name; end if;
  insert into public.society_memberships(society_id, user_id, status, requested_at, decided_at, decided_by)
    values (_society_id, _uid, case when s.requires_approval then 'pending' else 'member' end, now(), case when s.requires_approval then null else now() end, null)
    on conflict (society_id, user_id) do update set status = excluded.status, requested_at = now(), decided_at = excluded.decided_at, decided_by = null;
  if s.requires_approval then
    perform public.notify_user(r.user_id, 'requests', 'New membership request', s.short_name, jsonb_build_object('to', '/committee'), 'req:' || _society_id || ':' || _uid)
      from public.society_roles r where r.society_id = _society_id;
    return 'pending';
  end if;
  return 'member';
end $$;

-- Recommendations come from your own university only, even for platform admins.
create or replace function public.recommend_societies()
returns table(society_id uuid, slug text, score bigint, matched_interests text[]) language sql stable security definer set search_path = public as $$
 SELECT s.id,s.slug,count(pi.interest_id),coalesce(array_agg(i.name ORDER BY i.name) FILTER(WHERE pi.interest_id IS NOT NULL),'{}'::text[])
 FROM public.societies s LEFT JOIN public.society_tags st ON st.society_id=s.id LEFT JOIN public.profile_interests pi ON pi.interest_id=st.interest_id AND pi.profile_id=auth.uid() LEFT JOIN public.interests i ON i.id=pi.interest_id
 WHERE auth.uid() IS NOT NULL AND s.status='active' AND s.university_id=private.user_university(auth.uid()) AND NOT EXISTS(SELECT 1 FROM public.society_memberships m WHERE m.society_id=s.id AND m.user_id=auth.uid() AND m.status IN ('member','pending')) AND NOT private.is_society_committee(s.id,auth.uid())
 GROUP BY s.id ORDER BY count(pi.interest_id) DESC,s.name;
$$;

-- Counts only for societies the caller can see.
create or replace function public.society_member_counts()
returns table(society_id uuid, members int) language sql stable security definer set search_path = public as $$
  select society_id, count(*)::int from public.society_memberships where status = 'member'
  group by society_id having private.society_visible(society_id, auth.uid())
$$;
create or replace function public.society_member_count(_society_id uuid)
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from public.society_memberships
  where society_id = _society_id and status = 'member' and private.society_visible(_society_id, auth.uid())
$$;
create or replace function public.event_attendee_counts()
returns table(event_id uuid, attendees int) language sql stable security definer set search_path = public as $$
  select r.event_id, count(*)::int from public.event_registrations r join public.events e on e.id = r.event_id
  group by r.event_id, e.society_id having private.society_visible(e.society_id, auth.uid())
$$;

-- ===== Invites =====
-- Society invites (committee) come from the society's university admins; university admin
-- and platform admin invites from platform admins. Everyone but a platform admin must be
-- invited at an address of the university they'll act for.
alter table public.role_invites add column university_id uuid references public.universities(id) on delete cascade;
alter table public.role_invites drop constraint role_invites_role_check;
alter table public.role_invites add constraint role_invites_role_check
  check (role in ('committee', 'admin', 'platform_admin', 'university_admin'));
-- not valid: older rows aren't rechecked, new ones must name exactly what they grant.
alter table public.role_invites add constraint role_invites_target_check check (case role
  when 'platform_admin' then society_id is null and university_id is null
  when 'university_admin' then society_id is null and university_id is not null
  else society_id is not null and university_id is null end) not valid;
drop index public.role_invites_unique;
create unique index role_invites_unique on public.role_invites (email, coalesce(society_id, university_id, '00000000-0000-0000-0000-000000000000'::uuid)) where claimed_at is null;

drop policy "Admins read invites" on public.role_invites;
create policy "Admins read invites" on public.role_invites for select to authenticated
  using (private.can_manage_university(coalesce(university_id, private.society_university(society_id)), auth.uid()));
drop policy "Admins create invites" on public.role_invites;
create policy "Admins create invites" on public.role_invites for insert to authenticated
  with check (private.has_role(auth.uid(), 'platform_admin')
    or (role in ('committee', 'admin') and private.can_manage_society(society_id, auth.uid())));
drop policy "Admins delete invites" on public.role_invites;
create policy "Admins delete invites" on public.role_invites for delete to authenticated
  using (private.has_role(auth.uid(), 'platform_admin')
    or (role in ('committee', 'admin') and private.can_manage_society(society_id, auth.uid())));

create or replace function public.on_invite_created()
returns trigger language plpgsql security definer set search_path = public as $$
declare _uid uuid; _uni uuid := coalesce(new.university_id, private.society_university(new.society_id));
begin
  if _uni is not null and private.domain_university(new.email) is distinct from _uni then
    raise exception 'Invite an address at %.', (select short_name from public.universities where id = _uni);
  end if;
  select id into _uid from auth.users where lower(email) = new.email;
  if _uid is not null then perform public.claim_invites(_uid, new.email); end if;
  return null;
end $$;

-- Grants follow the invite's role. Before, any invite without a society made a platform admin.
create or replace function public.claim_invites(_uid uuid, _email text)
returns void language plpgsql security definer set search_path = public as $$
declare inv record;
begin
  for inv in select * from public.role_invites where email = lower(_email) and claimed_at is null loop
    if inv.role = 'platform_admin' then
      insert into public.user_roles(user_id, role) values (_uid, 'platform_admin') on conflict do nothing;
    elsif inv.role = 'university_admin' then
      insert into public.university_admins(university_id, user_id) values (inv.university_id, _uid) on conflict do nothing;
    elsif inv.society_id is not null then
      insert into public.society_roles(society_id, user_id, role, position)
        values (inv.society_id, _uid, case when inv.role = 'admin' then 'admin' else 'committee' end, inv.position)
        on conflict (society_id, user_id) do update set position = excluded.position;
      insert into public.society_memberships(society_id, user_id, status, decided_at)
        values (inv.society_id, _uid, 'member', now())
        on conflict (society_id, user_id) do update set status = 'member';
    end if;
    update public.role_invites set claimed_at = now() where id = inv.id;
  end loop;
end $$;

-- ===== Sign-up =====
-- Signed-out visitors call this to check an address before asking for a sign-in link.
create or replace function public.email_domain_allowed(_email text)
returns boolean language sql stable security definer set search_path = public as $$
  select private.domain_university(_email) is not null
$$;
grant execute on function public.email_domain_allowed(text) to anon, authenticated;

create or replace function public.enforce_email_domain()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (tg_op = 'INSERT' or new.email is distinct from old.email)
     and (new.email is null or not public.email_domain_allowed(new.email)) then
    raise exception 'Please use your university email address.';
  end if;
  if tg_op = 'UPDATE' and new.email_change is distinct from old.email_change
     and coalesce(new.email_change, '') <> '' and not public.email_domain_allowed(new.email_change) then
    raise exception 'Please use your university email address.';
  end if;
  -- An account belongs to one university; another university's address would carry its
  -- memberships and committee seats across.
  if tg_op = 'UPDATE' and (
       (new.email is distinct from old.email
        and private.domain_university(new.email) is distinct from private.domain_university(old.email))
    or (new.email_change is distinct from old.email_change and coalesce(new.email_change, '') <> ''
        and private.domain_university(new.email_change) is distinct from private.domain_university(old.email))) then
    raise exception 'Your new address has to be at the same university.';
  end if;
  return new;
end $$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles(id, display_name)
    values (new.id, coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)));
  insert into public.notification_prefs(user_id) values (new.id);
  insert into public.university_members(user_id, university_id)
    select new.id, u from private.domain_university(new.email) u where u is not null;
  perform public.claim_invites(new.id, new.email);
  return new;
end $$;

-- ===== The signed-in user's summary =====
create or replace function public.my_access()
returns json language sql stable security definer set search_path = public as $$
  select json_build_object(
    'is_admin', private.has_role(auth.uid(), 'platform_admin'),
    'university', (select json_build_object('id', u.id, 'slug', u.slug, 'name', u.name, 'short_name', u.short_name)
       from public.university_members m join public.universities u on u.id = m.university_id where m.user_id = auth.uid()),
    'university_admin', exists (select 1 from public.university_admins where user_id = auth.uid()),
    'committee', coalesce((select json_agg(json_build_object('society_id', s.id, 'slug', s.slug, 'short_name', s.short_name, 'position', r.position))
       from public.society_roles r join public.societies s on s.id = r.society_id where r.user_id = auth.uid() and s.status = 'active'), '[]'::json)
  )
$$;
