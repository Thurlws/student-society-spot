-- Admins couldn't stop someone abusing the platform: removing their messages one at a time
-- was all there was. Admins can now suspend an account. A suspended account keeps its
-- memberships, seats and content, but every permission helper treats it as having none:
-- it sees no societies, events, posts, channels, calls or other people, can't post, join,
-- register, report or use the AI features, and loses committee and admin rights. It can
-- still read its own profile, settings, notifications and requests, so "Download my data"
-- keeps working. Lifting the suspension gives everything back.
--
-- Platform admins can suspend anyone but themselves. University admins can suspend people at
-- their own university, but not an admin: that's for platform admins. Every suspension and
-- reinstatement is in the audit log with who did it.
alter table public.university_members
  add column suspended_at timestamptz,
  add column suspension_reason text not null default '' check (char_length(suspension_reason) <= 300);

create function private.is_suspended(_uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.university_members where user_id = _uid and suspended_at is not null)
$$;
revoke execute on function private.is_suspended(uuid) from public, anon;
grant execute on function private.is_suspended(uuid) to authenticated;

-- ===== Permission helpers: a suspended account has no rights =====
create or replace function private.has_role(_user_id uuid, _role public.app_role)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.user_roles where user_id = _user_id and role = _role)
    and not private.is_suspended(_user_id)
$$;

create or replace function private.is_society_committee(_society_id uuid, _uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.society_roles where society_id = _society_id and user_id = _uid)
    and not private.is_suspended(_uid)
$$;

create or replace function private.is_society_member(_society_id uuid, _uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select (exists (select 1 from public.society_memberships where society_id = _society_id and user_id = _uid and status = 'member')
          and not private.is_suspended(_uid))
      or private.is_society_committee(_society_id, _uid)
$$;

create or replace function private.can_manage_university(_university_id uuid, _uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select _uid is not null and not private.is_suspended(_uid) and (
    private.has_role(_uid, 'platform_admin')
    or exists (select 1 from public.university_admins where university_id = _university_id and user_id = _uid)
  )
$$;

create or replace function private.society_visible(_society_id uuid, _uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select _uid is not null and not private.is_suspended(_uid) and exists (
    select 1 from public.societies s where s.id = _society_id and (
      (s.status = 'active' and s.university_id = private.user_university(_uid))
      or private.can_manage_university(s.university_id, _uid)
      or private.is_society_committee(s.id, _uid)
    )
  )
$$;

-- Your own profile stays readable; nobody else's is.
create or replace function private.can_see_profile(_profile uuid, _uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select _uid is not null and (
    _profile = _uid
    or (not private.is_suspended(_uid) and (
      -- admins see their university's people (platform admins everyone's)
      private.can_manage_university(private.user_university(_profile), _uid)
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
    ))
  )
$$;

-- The society directory checks your university, not a helper.
drop policy "Read societies" on public.societies;
create policy "Read societies" on public.societies for select to authenticated
  using ((status = 'active' and university_id = private.user_university(auth.uid()) and not private.is_suspended(auth.uid()))
    or private.can_manage_university(university_id, auth.uid()));

-- ===== What used to rest on your own rows alone =====
-- Joining checks your university, not a helper.
create or replace function public.join_society(_society_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare s public.societies; cur text; _uid uuid := auth.uid();
begin
  if _uid is null then raise exception 'Please sign in first.'; end if;
  if private.is_suspended(_uid) then raise exception 'Your account is suspended.'; end if;
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

create or replace function public.recommend_societies()
returns table(society_id uuid, slug text, score bigint, matched_interests text[]) language sql stable security definer set search_path = public as $$
 SELECT s.id,s.slug,count(pi.interest_id),coalesce(array_agg(i.name ORDER BY i.name) FILTER(WHERE pi.interest_id IS NOT NULL),'{}'::text[])
 FROM public.societies s LEFT JOIN public.society_tags st ON st.society_id=s.id LEFT JOIN public.profile_interests pi ON pi.interest_id=st.interest_id AND pi.profile_id=auth.uid() LEFT JOIN public.interests i ON i.id=pi.interest_id
 WHERE auth.uid() IS NOT NULL AND NOT private.is_suspended(auth.uid()) AND s.status='active' AND s.university_id=private.user_university(auth.uid()) AND NOT EXISTS(SELECT 1 FROM public.society_memberships m WHERE m.society_id=s.id AND m.user_id=auth.uid() AND m.status IN ('member','pending')) AND NOT private.is_society_committee(s.id,auth.uid())
 GROUP BY s.id ORDER BY count(pi.interest_id) DESC,s.name;
$$;

-- A suspended member can still read their own requests, but not keep writing to the committee.
create or replace function public.comment_on_support_request(_id uuid, _text text)
returns void language plpgsql security definer set search_path = public as $$
declare r public.support_requests;
begin
  select * into r from public.support_requests where id = _id;
  if not found or not (r.submitted_by = auth.uid() or private.is_society_committee(r.society_id, auth.uid())) then raise exception 'You can''t comment on this request.'; end if;
  if private.is_suspended(auth.uid()) then raise exception 'Your account is suspended.'; end if;
  if char_length(btrim(coalesce(_text, ''))) < 1 then raise exception 'Write a comment first.'; end if;
  if char_length(_text) > 1000 then raise exception 'Comments can be up to 1,000 characters.'; end if;
  insert into public.support_request_activity(request_id, actor_id, kind, text) values (_id, auth.uid(), 'comment', btrim(_text));
  update public.support_requests set updated_at = now() where id = _id;
  if auth.uid() = r.submitted_by then
    perform public.notify_user(coalesce(r.assigned_to, x.user_id), 'requests', 'New comment: ' || r.title, left(btrim(_text), 140),
      jsonb_build_object('to', '/requests/$requestId', 'params', jsonb_build_object('requestId', _id)), 'src:' || _id)
      from (select user_id from public.society_roles where society_id = r.society_id and (r.assigned_to is null or user_id = r.assigned_to)) x;
  else
    perform public.notify_user(r.submitted_by, 'requests', 'New reply: ' || r.title, left(btrim(_text), 140),
      jsonb_build_object('to', '/requests/$requestId', 'params', jsonb_build_object('requestId', _id)), 'src:' || _id);
  end if;
end $$;

-- No AI features (recaps, questions, captions, recommendations) while suspended.
CREATE OR REPLACE FUNCTION public.reserve_society_ai(_uid uuid,_feature text) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE used integer; lim integer;
BEGIN
 IF private.is_suspended(_uid) THEN RETURN false; END IF;
 lim := CASE _feature WHEN 'society_fit' THEN 20 WHEN 'society_ask' THEN 60 WHEN 'society_proposal' THEN 10
                      WHEN 'summary' THEN 10 WHEN 'question' THEN 60 WHEN 'transcribe' THEN 600 ELSE 0 END;
 IF lim=0 THEN RETURN false; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(_uid::text||_feature,0));
 SELECT count(*) INTO used FROM public.ai_usage WHERE user_id=_uid AND feature=_feature AND created_at>now()-interval '1 hour';
 IF used>=lim THEN RETURN false; END IF;
 INSERT INTO public.ai_usage(user_id,feature) VALUES(_uid,_feature); RETURN true;
END; $$;

-- Taking part in a call let you write its recap and read it later.
drop policy "Own or committee participants" on public.call_participants;
create policy "Own or committee participants" on public.call_participants for select to authenticated
  using ((user_id = auth.uid() and not private.is_suspended(auth.uid()))
    or exists (select 1 from public.call_rooms r where r.id = room_id and private.is_society_committee(r.society_id, auth.uid())));
drop policy "Participants, committee or members of shared read recaps" on public.call_recaps;
create policy "Participants, committee or members of shared read recaps" on public.call_recaps for select to authenticated
  using (((auth.uid() = any(participant_ids) or created_by = auth.uid()) and not private.is_suspended(auth.uid()))
    or private.is_society_committee(society_id, auth.uid())
    or (shared and private.is_society_member(society_id, auth.uid())));

-- ===== Suspending and reinstating =====
-- Only platform admins act on admins. Raw tables, because the helpers say a suspended admin isn't one.
create function private.can_suspend(_user_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select _user_id is distinct from auth.uid()
    and private.can_manage_university(private.user_university(_user_id), auth.uid())
    and (private.has_role(auth.uid(), 'platform_admin')
         or not (exists (select 1 from public.user_roles where user_id = _user_id)
                 or exists (select 1 from public.university_admins where user_id = _user_id)))
$$;
revoke execute on function private.can_suspend(uuid) from public, anon, authenticated;

create function public.suspend_user(_user_id uuid, _reason text)
returns void language plpgsql security definer set search_path = public as $$
declare m public.university_members;
begin
  select * into m from public.university_members where user_id = _user_id for update;
  if not found or not private.can_manage_university(m.university_id, auth.uid()) then
    raise exception 'That person isn''t at a university you manage.';
  end if;
  if _user_id = auth.uid() then raise exception 'You can''t suspend yourself.'; end if;
  if not private.can_suspend(_user_id) then raise exception 'Only platform admins can suspend an admin.'; end if;
  if m.suspended_at is not null then raise exception 'This account is already suspended.'; end if;
  if char_length(btrim(coalesce(_reason, ''))) < 3 then raise exception 'Say why. The person sees the reason.'; end if;
  if char_length(btrim(_reason)) > 300 then raise exception 'Keep the reason under 300 characters.'; end if;
  update public.university_members set suspended_at = now(), suspension_reason = btrim(_reason) where user_id = _user_id;
end $$;
revoke execute on function public.suspend_user(uuid, text) from public, anon;

create function public.reinstate_user(_user_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare m public.university_members;
begin
  select * into m from public.university_members where user_id = _user_id for update;
  if not found or not private.can_manage_university(m.university_id, auth.uid()) then
    raise exception 'That person isn''t at a university you manage.';
  end if;
  if not private.can_suspend(_user_id) then raise exception 'Only platform admins can lift an admin''s suspension.'; end if;
  if m.suspended_at is null then raise exception 'This account isn''t suspended.'; end if;
  update public.university_members set suspended_at = null, suspension_reason = '' where user_id = _user_id;
end $$;
revoke execute on function public.reinstate_user(uuid) from public, anon;

-- Admins find people by name or by exact email address, within universities they manage.
-- Email addresses aren't returned: an admin only learns which account an address they
-- already know belongs to.
create function public.find_people(_university_id uuid, _query text)
returns table(user_id uuid, display_name text, course text, year text, joined_at timestamptz, suspended_at timestamptz, suspension_reason text)
language sql stable security definer set search_path = public as $$
  select m.user_id, p.display_name, p.course, p.year, m.joined_at, m.suspended_at, m.suspension_reason
  from public.university_members m join public.profiles p on p.id = m.user_id
  where m.university_id = _university_id
    and private.can_manage_university(_university_id, auth.uid())
    and char_length(btrim(coalesce(_query, ''))) >= 2
    and case when position('@' in _query) > 0
      then exists (select 1 from auth.users u where u.id = m.user_id and lower(u.email) = lower(btrim(_query)))
      else p.display_name ilike '%' || replace(replace(replace(btrim(_query), '\', '\\'), '%', '\%'), '_', '\_') || '%'
    end
  order by p.display_name
  limit 20
$$;
revoke execute on function public.find_people(uuid, text) from public, anon;

create function private.audit_university_members()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.suspended_at is null and new.suspended_at is not null then
    perform private.audit('person.suspended', new.university_id, null, new.user_id, jsonb_build_object('reason', new.suspension_reason));
  elsif old.suspended_at is not null and new.suspended_at is null then
    perform private.audit('person.reinstated', new.university_id, null, new.user_id, '{}');
  end if;
  return null;
end $$;
revoke execute on function private.audit_university_members() from public, anon, authenticated;
create trigger audit_university_members after update of suspended_at on public.university_members
  for each row execute function private.audit_university_members();

-- ===== The signed-in user's summary =====
-- A suspended account has no roles to show, and sees why it was suspended.
create or replace function public.my_access()
returns json language sql stable security definer set search_path = public as $$
  select json_build_object(
    'is_admin', private.has_role(auth.uid(), 'platform_admin'),
    'university', (select json_build_object('id', u.id, 'slug', u.slug, 'name', u.name, 'short_name', u.short_name)
       from public.university_members m join public.universities u on u.id = m.university_id where m.user_id = auth.uid()),
    'university_admin', exists (select 1 from public.university_admins where user_id = auth.uid()) and not private.is_suspended(auth.uid()),
    'committee', coalesce((select json_agg(json_build_object('society_id', s.id, 'slug', s.slug, 'short_name', s.short_name, 'position', r.position))
       from public.society_roles r join public.societies s on s.id = r.society_id
       where r.user_id = auth.uid() and s.status = 'active' and not private.is_suspended(auth.uid())), '[]'::json),
    'suspended', (select json_build_object('at', suspended_at, 'reason', suspension_reason)
       from public.university_members where user_id = auth.uid() and suspended_at is not null)
  )
$$;
