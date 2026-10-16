-- Generated 2026-10-16 from drizzle/migrations/0007 to 0030 (unchanged), for production, which had
-- none of them: Lovable does not apply migration files that arrive from GitHub.
-- SocConnect: database updates 0007 to 0030, all at once.
--
-- Paste ALL of this into Lovable: More, then Cloud, then SQL editor. Click Run and confirm.
-- It runs as one transaction: either every update goes in, or nothing changes at all.
-- Running it a second time changes nothing and says the updates are already in.

begin;

do $check$
begin
  if to_regnamespace('private') is not null or to_regclass('public.universities') is not null then
    raise exception 'These updates are already in this database. Nothing was changed.';
  end if;
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'societies' and column_name = 'source_snapshot') then
    raise exception 'This database is missing update 0006. Nothing was changed. Send this message to Claude.';
  end if;
end $check$;

-- ===== 0007_admins_by_invite_only =====

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

-- ===== 0008_private_permission_helpers =====

-- Permission helpers run with owner rights so RLS policies can use them. In the public
-- schema the API exposed them too, so any signed-in user could ask
-- rpc("is_society_member", { _society_id, _uid }) about anyone, including members of
-- sensitive societies. Move them to a schema the API doesn't expose. Policies point at
-- the functions themselves and keep working; functions that call them by name are
-- recreated below with the new names (generated from the 0000-0007 definitions).
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated, service_role;

alter function public.has_role(uuid, public.app_role) set schema private;
alter function public.is_society_committee(uuid, uuid) set schema private;
alter function public.is_society_member(uuid, uuid) set schema private;
alter function public.society_visible(uuid, uuid) set schema private;
alter function public.can_see_profile(uuid, uuid) set schema private;

CREATE OR REPLACE FUNCTION private.is_society_member(_society_id uuid, _uid uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (select 1 from public.society_memberships where society_id = _society_id and user_id = _uid and status = 'member')
      or private.is_society_committee(_society_id, _uid)
$function$

;

CREATE OR REPLACE FUNCTION private.society_visible(_society_id uuid, _uid uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select _uid is not null and (
    exists (select 1 from public.societies where id = _society_id and status = 'active')
    or private.has_role(_uid, 'platform_admin')
    or private.is_society_committee(_society_id, _uid)
  )
$function$

;

CREATE OR REPLACE FUNCTION private.can_see_profile(_profile uuid, _uid uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select _uid is not null and (
    _profile = _uid
    or private.has_role(_uid, 'platform_admin')
    -- committee members are public contacts for their societies
    or exists (select 1 from public.society_roles where user_id = _profile)
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
$function$

;

CREATE OR REPLACE FUNCTION public.assign_support_request(_id uuid, _assignee uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.support_requests; nm text;
begin
  select * into r from public.support_requests where id = _id for update;
  if not found or not private.is_society_committee(r.society_id, auth.uid()) then raise exception 'Only this society''s committee can assign requests.'; end if;
  if _assignee is not null and not private.is_society_committee(r.society_id, _assignee) then raise exception 'Pick someone on this society''s committee.'; end if;
  if r.assigned_to is not distinct from _assignee then return; end if;
  update public.support_requests set assigned_to = _assignee, updated_at = now() where id = _id;
  select display_name into nm from public.profiles where id = _assignee;
  insert into public.support_request_activity(request_id, actor_id, kind, text)
    values (_id, auth.uid(), 'assigned', case when _assignee is null then 'Unassigned' else 'Assigned to ' || nm end);
end $function$

;

CREATE OR REPLACE FUNCTION public.comment_on_support_request(_id uuid, _text text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.support_requests;
begin
  select * into r from public.support_requests where id = _id;
  if not found or not (r.submitted_by = auth.uid() or private.is_society_committee(r.society_id, auth.uid())) then raise exception 'You can''t comment on this request.'; end if;
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
end $function$

;

CREATE OR REPLACE FUNCTION public.create_event(_society_id uuid, _title text, _description text, _date date, _start time without time zone, _end time without time zone, _venue text, _category text, _capacity integer)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.societies; _id uuid; _starts timestamptz;
begin
  select * into s from public.societies where id = _society_id;
  if not found then raise exception 'That society doesn''t exist.'; end if;
  if not private.is_society_committee(_society_id, auth.uid()) then raise exception 'Only the % committee can create events.', s.short_name; end if;
  _starts := (_date + _start) at time zone 'Europe/Dublin';
  if _starts < now() - interval '1 day' then raise exception 'Pick today or a later date.'; end if;
  insert into public.events(society_id, title, description, starts_at, ends_at, venue, category, capacity, tags, created_by)
    values (_society_id, btrim(_title), btrim(coalesce(_description, '')), _starts,
      case when _end is null then null else (_date + _end) at time zone 'Europe/Dublin' end,
      btrim(_venue), _category, _capacity, array[_category], auth.uid())
    returning id into _id;
  return _id;
end $function$

;

CREATE OR REPLACE FUNCTION public.decide_membership(_membership_id uuid, _decision text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m public.society_memberships; s public.societies;
begin
  if _decision not in ('approve','decline') then raise exception 'Unknown decision.'; end if;
  select * into m from public.society_memberships where id = _membership_id for update;
  if not found or m.status <> 'pending' then raise exception 'This request has already been handled.'; end if;
  select * into s from public.societies where id = m.society_id;
  if not private.is_society_committee(m.society_id, auth.uid()) then raise exception 'Only the % committee can review this request.', s.short_name; end if;
  update public.society_memberships set status = case when _decision = 'approve' then 'member' else 'declined' end, decided_at = now(), decided_by = auth.uid() where id = m.id;
  perform public.notify_user(m.user_id, 'requests',
    case when _decision = 'approve' then 'You''re in! Welcome to ' || s.short_name else 'Your request to join ' || s.short_name || ' was declined' end,
    case when _decision = 'approve' then 'Your membership request was approved.' else 'You can contact the committee for more information.' end,
    jsonb_build_object('to', '/societies/$societyId', 'params', jsonb_build_object('societyId', s.slug)), null);
end $function$

;

CREATE OR REPLACE FUNCTION public.guard_society_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not private.has_role(auth.uid(), 'platform_admin') and auth.uid() is not null then
    if new.slug is distinct from old.slug or new.status is distinct from old.status then
      raise exception 'Only platform admins can change a society''s address or archive it';
    end if;
    if new.source is distinct from old.source or new.source_id is distinct from old.source_id
       or new.source_snapshot is distinct from old.source_snapshot or new.source_synced_at is distinct from old.source_synced_at
       or new.join_url is distinct from old.join_url or new.official_url is distinct from old.official_url then
      raise exception 'Official TU Dublin society links can only be changed by an import or a platform admin';
    end if;
  end if;
  return new;
end $function$

;

CREATE OR REPLACE FUNCTION public.join_society(_society_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.societies; cur text; _uid uuid := auth.uid();
begin
  if _uid is null then raise exception 'Please sign in first.'; end if;
  select * into s from public.societies where id = _society_id and status = 'active';
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
end $function$

;

CREATE OR REPLACE FUNCTION public.leave_society(_society_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.societies;
begin
  select * into s from public.societies where id = _society_id;
  if not found then raise exception 'That society doesn''t exist.'; end if;
  if private.is_society_committee(_society_id, auth.uid()) then raise exception 'You''re on the % committee, so you can''t leave it here.', s.short_name; end if;
  delete from public.society_memberships where society_id = _society_id and user_id = auth.uid() and status = 'member';
  if not found then raise exception 'You''re not a member of %.', s.short_name; end if;
end $function$

;

CREATE OR REPLACE FUNCTION public.my_access()
 RETURNS json
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select json_build_object(
    'is_admin', private.has_role(auth.uid(), 'platform_admin'),
    'committee', coalesce((select json_agg(json_build_object('society_id', s.id, 'slug', s.slug, 'short_name', s.short_name, 'position', r.position))
       from public.society_roles r join public.societies s on s.id = r.society_id where r.user_id = auth.uid() and s.status = 'active'), '[]'::json)
  )
$function$

;

CREATE OR REPLACE FUNCTION public.recommend_societies()
 RETURNS TABLE(society_id uuid, slug text, score bigint, matched_interests text[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 SELECT s.id,s.slug,count(pi.interest_id),coalesce(array_agg(i.name ORDER BY i.name) FILTER(WHERE pi.interest_id IS NOT NULL),'{}'::text[])
 FROM public.societies s LEFT JOIN public.society_tags st ON st.society_id=s.id LEFT JOIN public.profile_interests pi ON pi.interest_id=st.interest_id AND pi.profile_id=auth.uid() LEFT JOIN public.interests i ON i.id=pi.interest_id
 WHERE auth.uid() IS NOT NULL AND s.status='active' AND private.society_visible(s.id,auth.uid()) AND NOT EXISTS(SELECT 1 FROM public.society_memberships m WHERE m.society_id=s.id AND m.user_id=auth.uid() AND m.status IN ('member','pending')) AND NOT private.is_society_committee(s.id,auth.uid())
 GROUP BY s.id ORDER BY count(pi.interest_id) DESC,s.name;
$function$

;

CREATE OR REPLACE FUNCTION public.schedule_meeting(_society_id uuid, _name text, _description text, _date date, _start time without time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.societies; _id uuid; _starts timestamptz;
begin
  select * into s from public.societies where id = _society_id;
  if not found then raise exception 'That society doesn''t exist.'; end if;
  if not private.is_society_committee(_society_id, auth.uid()) then raise exception 'Only the % committee can schedule calls.', s.short_name; end if;
  if char_length(btrim(coalesce(_name, ''))) < 2 then raise exception 'Give the call a title.'; end if;
  _starts := (_date + _start) at time zone 'Europe/Dublin';
  if _starts < now() - interval '1 hour' then raise exception 'Pick a time in the future.'; end if;
  insert into public.call_rooms(society_id, slug, name, kind, description, starts_at, host_id, created_by)
    values (_society_id, 'mt-' || substr(gen_random_uuid()::text, 1, 8), btrim(_name), 'meeting', left(btrim(coalesce(_description, '')), 500), _starts, auth.uid(), auth.uid())
    returning id into _id;
  perform public.notify_members(_society_id, auth.uid(), 'events', 'Call scheduled: ' || btrim(_name),
    s.short_name || ' · ' || to_char(_starts at time zone 'Europe/Dublin', 'Dy DD Mon, HH24:MI'),
    jsonb_build_object('to', '/call/$roomId', 'params', jsonb_build_object('roomId', _id)), 'mt:' || _id);
  return _id;
end $function$

;

CREATE OR REPLACE FUNCTION public.set_support_request_status(_id uuid, _to text, _resolution text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.support_requests; lbl jsonb := '{"open":"Open","in_progress":"In progress","resolved":"Resolved"}';
begin
  select * into r from public.support_requests where id = _id for update;
  if not found or not private.is_society_committee(r.society_id, auth.uid()) then raise exception 'Only this society''s committee can change a request''s status.'; end if;
  if not ((r.status = 'open' and _to in ('in_progress','resolved')) or (r.status = 'in_progress' and _to in ('open','resolved')) or (r.status = 'resolved' and _to = 'in_progress')) then
    raise exception 'Can''t move a request from % to %.', lbl->>r.status, coalesce(lbl->>_to, _to);
  end if;
  if _to = 'resolved' and char_length(btrim(coalesce(_resolution, ''))) < 3 then raise exception 'Add a resolution note so the member knows the outcome.'; end if;
  update public.support_requests set status = _to, resolution = case when _to = 'resolved' then btrim(_resolution) else resolution end, updated_at = now() where id = _id;
  insert into public.support_request_activity(request_id, actor_id, kind, text)
    values (_id, auth.uid(), 'status', 'Moved to ' || (lbl->>_to) || case when _to = 'resolved' then ': ' || btrim(_resolution) else '' end);
  perform public.notify_user(r.submitted_by, 'requests', 'Request ' || lower(lbl->>_to) || ': ' || r.title,
    case when _to = 'resolved' then btrim(_resolution) else 'The committee updated your request.' end,
    jsonb_build_object('to', '/requests/$requestId', 'params', jsonb_build_object('requestId', _id)), null);
end $function$

;

CREATE OR REPLACE FUNCTION public.share_recap(_recap_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.call_recaps; rm public.call_rooms; s public.societies; ch uuid; body text;
begin
  select * into r from public.call_recaps where id = _recap_id for update;
  if not found then raise exception 'That recap doesn''t exist.'; end if;
  select * into rm from public.call_rooms where id = r.room_id;
  if not (private.is_society_committee(r.society_id, auth.uid()) or rm.host_id = auth.uid()) then
    raise exception 'Only the committee or the call''s host can share a recap.';
  end if;
  if r.shared then return; end if;
  select * into s from public.societies where id = r.society_id;
  update public.call_recaps set shared = true, shared_at = now() where id = r.id;
  select id into ch from public.channels where society_id = r.society_id and slug = 'general';
  body := left('📋 Call recap — ' || r.title || E'\n' || coalesce(r.summary->>'overview', ''), 1000);
  if ch is not null then insert into public.messages(channel_id, author_id, body) values (ch, auth.uid(), body); end if;
  perform public.notify_members(r.society_id, auth.uid(), 'discussions', 'Call recap shared in ' || s.short_name, r.title,
    jsonb_build_object('to', '/recaps/$recapId', 'params', jsonb_build_object('recapId', r.id)), 'rc:' || r.id);
end $function$

;

CREATE OR REPLACE FUNCTION public.society_members(_society_id uuid)
 RETURNS TABLE(user_id uuid, display_name text, course text, status text, message text, requested_at timestamp with time zone, decided_at timestamp with time zone, membership_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select m.user_id, p.display_name, p.course, m.status, m.message, m.requested_at, m.decided_at, m.id
  from public.society_memberships m join public.profiles p on p.id = m.user_id
  where m.society_id = _society_id and private.is_society_committee(_society_id, auth.uid())
$function$

;

CREATE OR REPLACE FUNCTION public.submit_support_request(_society_id uuid, _title text, _description text, _category text, _priority text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.societies; _id uuid;
begin
  select * into s from public.societies where id = _society_id;
  if not found then raise exception 'That society doesn''t exist.'; end if;
  if not private.is_society_member(_society_id, auth.uid()) then raise exception 'Join % to contact its committee.', s.short_name; end if;
  insert into public.support_requests(society_id, submitted_by, title, description, category, priority)
    values (_society_id, auth.uid(), btrim(_title), btrim(_description), _category, _priority) returning id into _id;
  insert into public.support_request_activity(request_id, actor_id, kind, text) values (_id, auth.uid(), 'created', 'Request submitted');
  perform public.notify_user(r.user_id, 'requests', 'New request: ' || btrim(_title), s.short_name,
    jsonb_build_object('to', '/requests/$requestId', 'params', jsonb_build_object('requestId', _id)), 'sr:' || _id)
    from public.society_roles r where r.society_id = _society_id and r.user_id <> auth.uid();
  return _id;
end $function$

;

-- ===== 0009_one_ai_quota_function =====

-- One locked quota function for every AI call, including call recaps (summary, question),
-- which used to count and insert in two racy requests, and caption transcription, which
-- had no limit. Limits are per user per hour; guest captions count against the person
-- who created the guest link. 600 seven-second clips is about 70 minutes of speech.
CREATE OR REPLACE FUNCTION public.reserve_society_ai(_uid uuid,_feature text) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE used integer; lim integer;
BEGIN
 lim := CASE _feature WHEN 'society_fit' THEN 20 WHEN 'society_ask' THEN 60 WHEN 'society_proposal' THEN 10
                      WHEN 'summary' THEN 10 WHEN 'question' THEN 60 WHEN 'transcribe' THEN 600 ELSE 0 END;
 IF lim=0 THEN RETURN false; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(_uid::text||_feature,0));
 SELECT count(*) INTO used FROM public.ai_usage WHERE user_id=_uid AND feature=_feature AND created_at>now()-interval '1 hour';
 IF used>=lim THEN RETURN false; END IF;
 INSERT INTO public.ai_usage(user_id,feature) VALUES(_uid,_feature); RETURN true;
END; $$;

-- ===== 0010_per_user_indexes =====

-- Lookups by user alone (home page, can_see_profile, recommendations) scanned whole tables:
-- the existing keys start with society_id or event_id. Announcements are read newest first per society.
create index if not exists society_memberships_user_id_idx on public.society_memberships (user_id);
create index if not exists society_roles_user_id_idx on public.society_roles (user_id);
create index if not exists event_registrations_user_id_idx on public.event_registrations (user_id);
create index if not exists announcements_society_created_idx on public.announcements (society_id, created_at desc);

-- ===== 0011_domain_check_on_email_change =====

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

-- ===== 0012_deletable_accounts =====

-- Deleting an account deletes its profile, but these 13 foreign keys had no ON DELETE rule,
-- so Postgres refused while anything still pointed at the person. Their own content goes
-- with them (messages, support requests, guest links they made); society records they were
-- only linked to stay and lose the name.
alter table public.messages drop constraint messages_author_id_fkey,
  add constraint messages_author_id_fkey foreign key (author_id) references public.profiles(id) on delete cascade;
alter table public.support_requests drop constraint support_requests_submitted_by_fkey,
  add constraint support_requests_submitted_by_fkey foreign key (submitted_by) references public.profiles(id) on delete cascade;
alter table public.call_invites drop constraint call_invites_created_by_fkey,
  add constraint call_invites_created_by_fkey foreign key (created_by) references public.profiles(id) on delete cascade;

alter table public.announcements drop constraint announcements_author_id_fkey,
  add constraint announcements_author_id_fkey foreign key (author_id) references public.profiles(id) on delete set null;
alter table public.call_recaps drop constraint call_recaps_created_by_fkey,
  add constraint call_recaps_created_by_fkey foreign key (created_by) references public.profiles(id) on delete set null;
alter table public.call_rooms drop constraint call_rooms_created_by_fkey,
  add constraint call_rooms_created_by_fkey foreign key (created_by) references public.profiles(id) on delete set null;
alter table public.call_rooms drop constraint call_rooms_host_id_fkey,
  add constraint call_rooms_host_id_fkey foreign key (host_id) references public.profiles(id) on delete set null;
alter table public.collaboration_proposals drop constraint collaboration_proposals_created_by_fkey,
  add constraint collaboration_proposals_created_by_fkey foreign key (created_by) references public.profiles(id) on delete set null;
alter table public.events drop constraint events_created_by_fkey,
  add constraint events_created_by_fkey foreign key (created_by) references public.profiles(id) on delete set null;
alter table public.role_invites drop constraint role_invites_invited_by_fkey,
  add constraint role_invites_invited_by_fkey foreign key (invited_by) references public.profiles(id) on delete set null;
alter table public.society_memberships drop constraint society_memberships_decided_by_fkey,
  add constraint society_memberships_decided_by_fkey foreign key (decided_by) references public.profiles(id) on delete set null;
alter table public.support_request_activity drop constraint support_request_activity_actor_id_fkey,
  add constraint support_request_activity_actor_id_fkey foreign key (actor_id) references public.profiles(id) on delete set null;
alter table public.support_requests drop constraint support_requests_assigned_to_fkey,
  add constraint support_requests_assigned_to_fkey foreign key (assigned_to) references public.profiles(id) on delete set null;

-- ===== 0013_share_recap_host_check =====

-- share_recap let anyone share a recap from a drop-in room. Those rooms have no host, so
-- "host_id = auth.uid()" was null, "not (false or null)" was null, and the check never
-- raised. Sharing posts the recap into the society's general channel and notifies its
-- members, so a private call's summary could be pushed to everyone by a stranger.
CREATE OR REPLACE FUNCTION public.share_recap(_recap_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.call_recaps; rm public.call_rooms; s public.societies; ch uuid; body text;
begin
  select * into r from public.call_recaps where id = _recap_id for update;
  if not found then raise exception 'That recap doesn''t exist.'; end if;
  select * into rm from public.call_rooms where id = r.room_id;
  if not (private.is_society_committee(r.society_id, auth.uid()) or coalesce(rm.host_id = auth.uid(), false)) then
    raise exception 'Only the committee or the call''s host can share a recap.';
  end if;
  if r.shared then return; end if;
  select * into s from public.societies where id = r.society_id;
  update public.call_recaps set shared = true, shared_at = now() where id = r.id;
  select id into ch from public.channels where society_id = r.society_id and slug = 'general';
  body := left('📋 Call recap — ' || r.title || E'\n' || coalesce(r.summary->>'overview', ''), 1000);
  if ch is not null then insert into public.messages(channel_id, author_id, body) values (ch, auth.uid(), body); end if;
  perform public.notify_members(r.society_id, auth.uid(), 'discussions', 'Call recap shared in ' || s.short_name, r.title,
    jsonb_build_object('to', '/recaps/$recapId', 'params', jsonb_build_object('recapId', r.id)), 'rc:' || r.id);
end $function$;

-- ===== 0014_edit_and_cancel_events =====

-- Committees can edit and cancel events. Both go through functions so registered people
-- are told, times stay Dublin wall-clock like create_event, and a cancelled event refuses
-- new registrations. Direct updates are closed: the old policy let committees change any
-- column, including created_by and featured, without telling anyone.
alter table public.events
  add column cancelled_at timestamptz,
  add column cancel_reason text not null default '' check (char_length(cancel_reason) <= 300);

drop policy "Committee edit events" on public.events;
revoke update on public.events from anon, authenticated;

create or replace function public.update_event(_event_id uuid, _title text, _description text, _date date, _start time, _end time, _venue text, _category text, _capacity int)
returns void language plpgsql security definer set search_path = public as $$
declare e public.events; s public.societies; _starts timestamptz; _ends timestamptz; n int;
begin
  select * into e from public.events where id = _event_id for update;
  if not found then raise exception 'That event doesn''t exist.'; end if;
  select * into s from public.societies where id = e.society_id;
  if not private.is_society_committee(e.society_id, auth.uid()) then raise exception 'Only the % committee can edit this event.', s.short_name; end if;
  if e.cancelled_at is not null then raise exception 'This event was cancelled, so it can''t be edited.'; end if;
  _starts := (_date + _start) at time zone 'Europe/Dublin';
  _ends := case when _end is null then null else (_date + _end) at time zone 'Europe/Dublin' end;
  if _starts is distinct from e.starts_at and _starts < now() - interval '1 day' then raise exception 'Pick today or a later date.'; end if;
  select count(*) into n from public.event_registrations where event_id = e.id;
  if _capacity is not null and _capacity < n then
    raise exception 'The capacity can''t be lower than the % already registered.', case when n = 1 then '1 person' else n || ' people' end;
  end if;
  update public.events set title = btrim(_title), description = btrim(coalesce(_description, '')), starts_at = _starts, ends_at = _ends,
    venue = btrim(_venue), category = _category, capacity = _capacity, tags = array[_category]
    where id = e.id;
  -- Tell registered people when the time or place changes. One unread notice per event, kept current.
  if _starts is distinct from e.starts_at or _ends is distinct from e.ends_at or btrim(_venue) is distinct from e.venue then
    delete from public.notifications where dedupe_key = 'evu:' || e.id and read_at is null;
    perform public.notify_user(r.user_id, 'events', 'Event changed: ' || btrim(_title),
      to_char(_starts at time zone 'Europe/Dublin', 'Dy DD Mon, HH24:MI') || ', ' || btrim(_venue),
      jsonb_build_object('to', '/events/$eventId', 'params', jsonb_build_object('eventId', e.id)), 'evu:' || e.id)
      from public.event_registrations r where r.event_id = e.id and r.user_id <> auth.uid();
  end if;
end $$;
revoke execute on function public.update_event(uuid, text, text, date, time, time, text, text, int) from public, anon;

create or replace function public.cancel_event(_event_id uuid, _reason text)
returns void language plpgsql security definer set search_path = public as $$
declare e public.events; s public.societies;
begin
  select * into e from public.events where id = _event_id for update;
  if not found then raise exception 'That event doesn''t exist.'; end if;
  select * into s from public.societies where id = e.society_id;
  if not private.is_society_committee(e.society_id, auth.uid()) then raise exception 'Only the % committee can cancel this event.', s.short_name; end if;
  if e.cancelled_at is not null then raise exception 'This event is already cancelled.'; end if;
  if coalesce(e.ends_at, e.starts_at) < now() then raise exception 'This event has already taken place.'; end if;
  if char_length(btrim(coalesce(_reason, ''))) > 300 then raise exception 'Keep the reason under 300 characters.'; end if;
  update public.events set cancelled_at = now(), cancel_reason = btrim(coalesce(_reason, '')) where id = e.id;
  -- Registered people and members; the shared dedupe key stops anyone getting it twice.
  perform public.notify_user(r.user_id, 'events', 'Cancelled: ' || e.title,
      coalesce(nullif(btrim(coalesce(_reason, '')), ''), s.short_name || ' cancelled this event.'),
      jsonb_build_object('to', '/events/$eventId', 'params', jsonb_build_object('eventId', e.id)), 'evc:' || e.id)
    from public.event_registrations r where r.event_id = e.id and r.user_id <> auth.uid();
  perform public.notify_members(e.society_id, auth.uid(), 'events', 'Cancelled: ' || e.title,
    coalesce(nullif(btrim(coalesce(_reason, '')), ''), s.short_name || ' cancelled this event.'),
    jsonb_build_object('to', '/events/$eventId', 'params', jsonb_build_object('eventId', e.id)), 'evc:' || e.id);
end $$;
revoke execute on function public.cancel_event(uuid, text) from public, anon;

-- Cancelled events take no registrations, and neither do events the caller can't see
-- (an archived society's, for example).
create or replace function public.register_for_event(_event_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare e public.events; n int;
begin
  if auth.uid() is null then raise exception 'Please sign in first.'; end if;
  select * into e from public.events where id = _event_id for update;
  if not found or not private.society_visible(e.society_id, auth.uid()) then raise exception 'That event doesn''t exist.'; end if;
  if e.cancelled_at is not null then raise exception 'This event was cancelled.'; end if;
  if coalesce(e.ends_at, e.starts_at) < now() then raise exception 'This event has already taken place.'; end if;
  if exists (select 1 from public.event_registrations where event_id = _event_id and user_id = auth.uid()) then raise exception 'You''re already registered for this event.'; end if;
  if e.capacity is not null then
    select count(*) into n from public.event_registrations where event_id = _event_id;
    if n >= e.capacity then raise exception 'This event is full.'; end if;
  end if;
  insert into public.event_registrations(event_id, user_id) values (_event_id, auth.uid());
end $$;

-- ===== 0015_announcement_edits =====

-- Committees can now edit and delete announcements in the app (the policies already allowed
-- both). An edit may change only the wording and the pin: the update policy covered every
-- column, so a committee could reattribute an announcement to someone else or backdate it.
-- Changed wording is marked, so readers know a post isn't what they first saw.
alter table public.announcements add column edited_at timestamptz;

revoke update on public.announcements from anon, authenticated;
grant update (title, body, pinned) on public.announcements to authenticated;

create or replace function public.mark_announcement_edited()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.title is distinct from old.title or new.body is distinct from old.body then
    new.edited_at := now();
  end if;
  return new;
end $$;
revoke execute on function public.mark_announcement_edited() from public, anon, authenticated;
create trigger announcements_mark_edited before update on public.announcements
  for each row execute function public.mark_announcement_edited();

-- ===== 0016_message_moderation =====

-- Moderation for society discussions. Nobody could delete a message before: an abusive post
-- stayed until a developer edited the database. Authors can now delete their own messages,
-- and a society's committee and platform admins can remove any message in its channels.
-- Members can report a message: its committee is notified and sees it on the committee
-- dashboard, and platform admins see every open report on /admin. A report keeps a short
-- excerpt, because admins can't read society channels.
create table public.message_reports (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.messages(id) on delete cascade,
  society_id uuid not null references public.societies(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  reported_by uuid not null references public.profiles(id) on delete cascade,
  reason text not null default '' check (char_length(reason) <= 300),
  excerpt text not null,
  created_at timestamptz not null default now(),
  dismissed_at timestamptz,
  dismissed_by uuid references public.profiles(id) on delete set null,
  unique (message_id, reported_by)
);
create index message_reports_open_idx on public.message_reports (society_id) where dismissed_at is null;
create index message_reports_reported_by_idx on public.message_reports (reported_by);
alter table public.message_reports enable row level security;
-- Writes go through the functions below.
revoke insert, update, delete, truncate on public.message_reports from anon, authenticated;
grant select on public.message_reports to authenticated;
grant all on public.message_reports to service_role;
create policy "Committee, admins and the reporter read reports" on public.message_reports for select to authenticated
  using (reported_by = auth.uid() or private.is_society_committee(society_id, auth.uid()) or private.has_role(auth.uid(), 'platform_admin'));

create or replace function public.report_message(_message_id uuid, _reason text)
returns void language plpgsql security definer set search_path = public as $$
declare m public.messages; c public.channels; s public.societies;
begin
  select * into m from public.messages where id = _message_id;
  if found then select * into c from public.channels where id = m.channel_id; end if;
  -- Only people who can read the message can report it; others learn nothing.
  if not found or not private.is_society_member(c.society_id, auth.uid()) then raise exception 'That message doesn''t exist.'; end if;
  if m.author_id = auth.uid() then raise exception 'You can''t report your own message. Delete it instead.'; end if;
  if char_length(btrim(coalesce(_reason, ''))) > 300 then raise exception 'Keep the reason under 300 characters.'; end if;
  insert into public.message_reports(message_id, society_id, author_id, reported_by, reason, excerpt)
    values (m.id, c.society_id, m.author_id, auth.uid(), btrim(coalesce(_reason, '')), left(m.body, 280))
    on conflict (message_id, reported_by) do nothing;
  if not found then raise exception 'You''ve already reported this message.'; end if;
  select * into s from public.societies where id = c.society_id;
  perform public.notify_user(r.user_id, 'requests', 'Message reported in ' || s.short_name, '#' || c.name || ': ' || left(m.body, 120),
      jsonb_build_object('to', '/committee'), 'mr:' || m.id)
    from public.society_roles r where r.society_id = c.society_id and r.user_id <> m.author_id;
end $$;
revoke execute on function public.report_message(uuid, text) from public, anon;

create or replace function public.delete_message(_message_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare m public.messages; c public.channels;
begin
  select * into m from public.messages where id = _message_id for update;
  if found then select * into c from public.channels where id = m.channel_id; end if;
  if not found or not (private.is_society_member(c.society_id, auth.uid()) or private.has_role(auth.uid(), 'platform_admin')) then
    raise exception 'That message doesn''t exist.';
  end if;
  if not (coalesce(m.author_id = auth.uid(), false) or private.is_society_committee(c.society_id, auth.uid()) or private.has_role(auth.uid(), 'platform_admin')) then
    raise exception 'You can only delete your own messages.';
  end if;
  delete from public.messages where id = m.id;
end $$;
revoke execute on function public.delete_message(uuid) from public, anon;

-- Keep the message and close its reports.
create or replace function public.dismiss_message_reports(_message_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare sid uuid;
begin
  select society_id into sid from public.message_reports where message_id = _message_id limit 1;
  if sid is null or not (private.is_society_committee(sid, auth.uid()) or private.has_role(auth.uid(), 'platform_admin')) then
    raise exception 'Only the society''s committee or a platform admin can dismiss reports.';
  end if;
  update public.message_reports set dismissed_at = now(), dismissed_by = auth.uid() where message_id = _message_id and dismissed_at is null;
  if not found then raise exception 'There are no open reports for this message.'; end if;
end $$;
revoke execute on function public.dismiss_message_reports(uuid) from public, anon;

-- ===== 0017_reports_about_committee_members =====

-- A committee member whose own message was reported could see on the committee dashboard who
-- reported it, and could dismiss the report, which also took it off the /admin queue. The
-- committee now sees reports about everyone but themselves, and reports about a committee
-- member's message are for the rest of the committee and platform admins to handle. A
-- committee member who files a report is no longer notified about it either, and the
-- notification opens the right society for people on two committees.
drop policy "Committee, admins and the reporter read reports" on public.message_reports;
create policy "Committee, admins and the reporter read reports" on public.message_reports for select to authenticated
  using (reported_by = auth.uid()
    or (private.is_society_committee(society_id, auth.uid()) and author_id <> auth.uid())
    or private.has_role(auth.uid(), 'platform_admin'));

create or replace function public.dismiss_message_reports(_message_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare r public.message_reports;
begin
  select * into r from public.message_reports where message_id = _message_id limit 1;
  if not found or not (private.is_society_committee(r.society_id, auth.uid()) or private.has_role(auth.uid(), 'platform_admin')) then
    raise exception 'Only the society''s committee or a platform admin can dismiss reports.';
  end if;
  if r.author_id = auth.uid() and not private.has_role(auth.uid(), 'platform_admin') then
    raise exception 'Reports about your own message are for the rest of the committee to handle.';
  end if;
  update public.message_reports set dismissed_at = now(), dismissed_by = auth.uid() where message_id = _message_id and dismissed_at is null;
  if not found then raise exception 'There are no open reports for this message.'; end if;
end $$;
revoke execute on function public.dismiss_message_reports(uuid) from public, anon;

create or replace function public.report_message(_message_id uuid, _reason text)
returns void language plpgsql security definer set search_path = public as $$
declare m public.messages; c public.channels; s public.societies;
begin
  select * into m from public.messages where id = _message_id;
  if found then select * into c from public.channels where id = m.channel_id; end if;
  -- Only people who can read the message can report it; others learn nothing.
  if not found or not private.is_society_member(c.society_id, auth.uid()) then raise exception 'That message doesn''t exist.'; end if;
  if m.author_id = auth.uid() then raise exception 'You can''t report your own message. Delete it instead.'; end if;
  if char_length(btrim(coalesce(_reason, ''))) > 300 then raise exception 'Keep the reason under 300 characters.'; end if;
  insert into public.message_reports(message_id, society_id, author_id, reported_by, reason, excerpt)
    values (m.id, c.society_id, m.author_id, auth.uid(), btrim(coalesce(_reason, '')), left(m.body, 280))
    on conflict (message_id, reported_by) do nothing;
  if not found then raise exception 'You''ve already reported this message.'; end if;
  select * into s from public.societies where id = c.society_id;
  perform public.notify_user(r.user_id, 'requests', 'Message reported in ' || s.short_name, '#' || c.name || ': ' || left(m.body, 120),
      jsonb_build_object('to', '/committee', 'search', jsonb_build_object('society', s.slug)), 'mr:' || m.id)
    from public.society_roles r where r.society_id = c.society_id and r.user_id <> m.author_id and r.user_id <> auth.uid();
end $$;
revoke execute on function public.report_message(uuid, text) from public, anon;

-- ===== 0018_events_only_through_functions =====

-- Events change only through update_event and cancel_event, which tell registered people.
-- The delete policy from 0001 still let a committee remove an event through the API: its
-- registrations went with it and nobody was told. The app never deletes events; cancel them.
drop policy "Committee delete events" on public.events;
revoke delete on public.events from anon, authenticated;

-- ===== 0019_announcement_insert_columns =====

-- 0015 limited announcement edits to the wording and the pin, but a new announcement could
-- still set its own created_at or edited_at, so a committee could date a post in the future
-- and keep it above every other one.
revoke insert on public.announcements from anon, authenticated;
grant insert (society_id, author_id, title, body, pinned) on public.announcements to authenticated;

-- ===== 0020_recap_host_still_member =====

-- A call's host could share its recap into the society's general channel, and notify every
-- member, even after leaving the society. The host now has to still be a member.
CREATE OR REPLACE FUNCTION public.share_recap(_recap_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.call_recaps; rm public.call_rooms; s public.societies; ch uuid; body text;
begin
  select * into r from public.call_recaps where id = _recap_id for update;
  if not found then raise exception 'That recap doesn''t exist.'; end if;
  select * into rm from public.call_rooms where id = r.room_id;
  if not (private.is_society_committee(r.society_id, auth.uid())
          or (coalesce(rm.host_id = auth.uid(), false) and private.is_society_member(r.society_id, auth.uid()))) then
    raise exception 'Only the committee or the call''s host can share a recap.';
  end if;
  if r.shared then return; end if;
  select * into s from public.societies where id = r.society_id;
  update public.call_recaps set shared = true, shared_at = now() where id = r.id;
  select id into ch from public.channels where society_id = r.society_id and slug = 'general';
  body := left('📋 Call recap — ' || r.title || E'\n' || coalesce(r.summary->>'overview', ''), 1000);
  if ch is not null then insert into public.messages(channel_id, author_id, body) values (ch, auth.uid(), body); end if;
  perform public.notify_members(r.society_id, auth.uid(), 'discussions', 'Call recap shared in ' || s.short_name, r.title,
    jsonb_build_object('to', '/recaps/$recapId', 'params', jsonb_build_object('recapId', r.id)), 'rc:' || r.id);
end $function$;

-- ===== 0021_universities =====

-- SocConnect was built for TU Dublin alone: its email domains were in code and every society
-- belonged to it implicitly. To take on a second university, universities are now rows. A
-- university has the email domains its people sign in with, members (everyone who signed up
-- with one of those domains), and admins who manage its societies. Every society belongs to
-- one university, and society addresses only need to be unique within it.
-- TU Dublin gets the fixed id md5('tudublin') so tests and imports can name it.
create table public.universities (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9-]{2,40}$'),
  name text not null check (char_length(name) between 2 and 100),
  short_name text not null check (char_length(short_name) between 1 and 30),
  created_at timestamptz not null default now()
);

create table public.university_domains (
  domain text primary key check (domain ~ '^[a-z0-9-]+(\.[a-z0-9-]+)+$'),
  university_id uuid not null references public.universities(id) on delete cascade
);
create index university_domains_university_idx on public.university_domains (university_id);

-- One university per account: the one its email domain belongs to. Filled by handle_new_user.
create table public.university_members (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  university_id uuid not null references public.universities(id) on delete cascade,
  joined_at timestamptz not null default now()
);
create index university_members_university_idx on public.university_members (university_id);

create table public.university_admins (
  university_id uuid not null references public.universities(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  primary key (university_id, user_id)
);
create index university_admins_user_idx on public.university_admins (user_id);

insert into public.universities (id, slug, name, short_name)
  values (md5('tudublin')::uuid, 'tudublin', 'Technological University Dublin', 'TU Dublin');
insert into public.university_domains (domain, university_id)
  values ('mytudublin.ie', md5('tudublin')::uuid), ('tudublin.ie', md5('tudublin')::uuid);
insert into public.university_members (user_id, university_id)
  select p.id, d.university_id from public.profiles p
  join auth.users u on u.id = p.id
  join public.university_domains d on d.domain = split_part(lower(u.email), '@', 2);

alter table public.societies add column university_id uuid references public.universities(id);
update public.societies set university_id = md5('tudublin')::uuid;
alter table public.societies alter column university_id set not null;
alter table public.societies drop constraint societies_slug_key;
alter table public.societies add constraint societies_university_slug_key unique (university_id, slug);

-- Readers and writers are set in the next migration, with the rules that use these tables.
alter table public.universities enable row level security;
alter table public.university_domains enable row level security;
alter table public.university_members enable row level security;
alter table public.university_admins enable row level security;
revoke all on public.universities, public.university_domains, public.university_members, public.university_admins from anon, authenticated;
grant all on public.universities, public.university_domains, public.university_members, public.university_admins to service_role;

-- ===== 0022_university_rules =====

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

-- ===== 0023_yearly_reverification =====

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

-- ===== 0024_audit_log =====

-- A record of privileged actions: who gave or took away admin rights and committee seats,
-- who invited whom, who created, renamed, moved or archived a society or a university,
-- which domains were added or removed, which messages a committee or admin removed, which
-- reports were dismissed, which events were cancelled and which accounts were deleted.
-- Before, none of this was kept, so nobody could answer "who made this person an admin?".
--
-- Triggers fill it, so every path counts: the app, the API, invites claimed at sign-up and
-- hand-written SQL. Nobody can change or delete an entry through the API. Platform admins
-- read every entry; university admins read their own university's.
--
-- Left out on purpose: membership decisions. Being approved into the LGBTQ+, Islamic or
-- Christian Union society reveals special-category data (GDPR Art. 9), and university admins
-- can't see society members today. A removed message's author is left out for the same
-- reason: committees and admins act on the content, and the entry shouldn't tell admins who
-- belongs to which society.
--
-- Entries have no foreign keys: they outlive the people, societies and universities they
-- mention. When an account or a society is deleted, the rows that go with it (committee
-- seats, domains) aren't logged one by one; the deletion itself is.
create table public.audit_log (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  actor_id uuid,
  -- What the actor was when they acted: platform_admin, university_admin, committee,
  -- member, or system (sign-up, imports, nightly jobs and the service role).
  actor_role text not null,
  action text not null,
  -- Whose admins can read it. Null: platform admins only (platform admin grants, for example).
  university_id uuid,
  society_id uuid,
  -- The person the action was about, if any.
  subject_id uuid,
  details jsonb not null default '{}'
);
create index audit_log_university_idx on public.audit_log (university_id, at desc);
create index audit_log_at_idx on public.audit_log (at);
alter table public.audit_log enable row level security;
revoke all on public.audit_log from anon, authenticated;
revoke insert, update, delete, truncate on public.audit_log from service_role;
grant select on public.audit_log to authenticated, service_role;
create policy "Admins read the audit log" on public.audit_log for select to authenticated
  using (private.can_manage_university(university_id, auth.uid()));

create function private.audit(_action text, _university_id uuid, _society_id uuid, _subject_id uuid, _details jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare _uid uuid := auth.uid();
begin
  insert into public.audit_log (actor_id, actor_role, action, university_id, society_id, subject_id, details)
  values (_uid,
    case
      when _uid is null then 'system'
      when exists (select 1 from public.user_roles where user_id = _uid and role = 'platform_admin') then 'platform_admin'
      when exists (select 1 from public.university_admins where user_id = _uid and university_id = _university_id) then 'university_admin'
      when exists (select 1 from public.society_roles where user_id = _uid and society_id = _society_id) then 'committee'
      else 'member'
    end,
    _action, _university_id, _society_id, _subject_id, coalesce(_details, '{}'));
end $$;

-- ===== Platform and university admins =====
create function private.audit_user_roles()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    perform private.audit('platform_admin.added', null, null, new.user_id, '{}');
  elsif exists (select 1 from auth.users where id = old.user_id) then
    perform private.audit('platform_admin.removed', null, null, old.user_id, '{}');
  end if;
  return null;
end $$;
create trigger audit_user_roles after insert or delete on public.user_roles
  for each row execute function private.audit_user_roles();

create function private.audit_university_admins()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    perform private.audit('university_admin.added', new.university_id, null, new.user_id, '{}');
  elsif exists (select 1 from public.profiles where id = old.user_id)
    and exists (select 1 from public.universities where id = old.university_id) then
    perform private.audit('university_admin.removed', old.university_id, null, old.user_id, '{}');
  end if;
  return null;
end $$;
create trigger audit_university_admins after insert or delete on public.university_admins
  for each row execute function private.audit_university_admins();

-- ===== Committee seats and invites =====
create function private.audit_society_roles()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    perform private.audit('committee.added', private.society_university(new.society_id), new.society_id, new.user_id,
      jsonb_build_object('position', new.position, 'role', new.role));
  elsif tg_op = 'UPDATE' then
    if new.position is distinct from old.position or new.role is distinct from old.role then
      perform private.audit('committee.changed', private.society_university(new.society_id), new.society_id, new.user_id,
        jsonb_build_object('from', jsonb_build_object('position', old.position, 'role', old.role),
                           'to', jsonb_build_object('position', new.position, 'role', new.role)));
    end if;
  elsif exists (select 1 from public.profiles where id = old.user_id)
    and exists (select 1 from public.societies where id = old.society_id) then
    perform private.audit('committee.removed', private.society_university(old.society_id), old.society_id, old.user_id,
      jsonb_build_object('position', old.position));
  end if;
  return null;
end $$;
create trigger audit_society_roles after insert or update or delete on public.society_roles
  for each row execute function private.audit_society_roles();

-- Claimed invites aren't logged: the seat or role they grant is.
create function private.audit_role_invites()
returns trigger language plpgsql security definer set search_path = public as $$
declare r public.role_invites := case when tg_op = 'INSERT' then new else old end;
begin
  if tg_op = 'DELETE' and (r.claimed_at is not null
      or (r.society_id is not null and not exists (select 1 from public.societies where id = r.society_id))
      or (r.university_id is not null and not exists (select 1 from public.universities where id = r.university_id))) then
    return null;
  end if;
  perform private.audit(case when tg_op = 'INSERT' then 'invite.created' else 'invite.cancelled' end,
    coalesce(r.university_id, private.society_university(r.society_id)), r.society_id, null,
    jsonb_build_object('email', r.email, 'role', r.role, 'position', r.position));
  return null;
end $$;
create trigger audit_role_invites after insert or delete on public.role_invites
  for each row execute function private.audit_role_invites();

-- ===== Societies =====
-- Committee edits to the tagline, description and meeting times aren't privileged and
-- aren't logged. Renames are (audit finding 17: committees can rename their society).
create function private.audit_societies()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    perform private.audit('society.created', new.university_id, new.id, null,
      jsonb_build_object('name', new.name, 'slug', new.slug));
  elsif tg_op = 'DELETE' then
    perform private.audit('society.deleted', old.university_id, old.id, null,
      jsonb_build_object('name', old.name, 'slug', old.slug));
  else
    if new.status is distinct from old.status then
      perform private.audit(case when new.status = 'archived' then 'society.archived' else 'society.restored' end,
        new.university_id, new.id, null, jsonb_build_object('name', new.name));
    end if;
    if (new.name, new.short_name, new.slug) is distinct from (old.name, old.short_name, old.slug) then
      perform private.audit('society.renamed', new.university_id, new.id, null,
        jsonb_build_object('from', jsonb_build_object('name', old.name, 'short_name', old.short_name, 'slug', old.slug),
                           'to', jsonb_build_object('name', new.name, 'short_name', new.short_name, 'slug', new.slug)));
    end if;
    if (new.join_url, new.official_url) is distinct from (old.join_url, old.official_url) then
      perform private.audit('society.links_changed', new.university_id, new.id, null,
        jsonb_build_object('from', jsonb_build_object('join_url', old.join_url, 'official_url', old.official_url),
                           'to', jsonb_build_object('join_url', new.join_url, 'official_url', new.official_url)));
    end if;
    if new.university_id is distinct from old.university_id then
      perform private.audit('society.moved', new.university_id, new.id, null,
        jsonb_build_object('name', new.name, 'from', old.university_id, 'to', new.university_id));
    end if;
  end if;
  return null;
end $$;
create trigger audit_societies after insert or update or delete on public.societies
  for each row execute function private.audit_societies();

-- ===== Universities and their domains =====
create function private.audit_universities()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    perform private.audit('university.created', new.id, null, null, jsonb_build_object('name', new.name, 'slug', new.slug));
  elsif tg_op = 'DELETE' then
    perform private.audit('university.deleted', null, null, null, jsonb_build_object('id', old.id, 'name', old.name, 'slug', old.slug));
  elsif (new.name, new.short_name, new.slug) is distinct from (old.name, old.short_name, old.slug) then
    perform private.audit('university.renamed', new.id, null, null,
      jsonb_build_object('from', jsonb_build_object('name', old.name, 'short_name', old.short_name, 'slug', old.slug),
                         'to', jsonb_build_object('name', new.name, 'short_name', new.short_name, 'slug', new.slug)));
  end if;
  return null;
end $$;
create trigger audit_universities after insert or update or delete on public.universities
  for each row execute function private.audit_universities();

create function private.audit_university_domains()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    perform private.audit('domain.added', new.university_id, null, null, jsonb_build_object('domain', new.domain));
  elsif exists (select 1 from public.universities where id = old.university_id) then
    perform private.audit('domain.removed', old.university_id, null, null, jsonb_build_object('domain', old.domain));
  end if;
  return null;
end $$;
create trigger audit_university_domains after insert or delete on public.university_domains
  for each row execute function private.audit_university_domains();

-- ===== Moderation =====
-- Someone other than the author removed a message. Before delete, so its reports are still there.
create function private.audit_messages()
returns trigger language plpgsql security definer set search_path = public as $$
declare c public.channels;
begin
  if auth.uid() is not null and old.author_id is distinct from auth.uid() then
    select * into c from public.channels where id = old.channel_id;
    if found then
      perform private.audit('message.removed', private.society_university(c.society_id), c.society_id, null,
        jsonb_build_object('channel', c.name,
          'reported', exists (select 1 from public.message_reports where message_id = old.id)));
    end if;
  end if;
  return old;
end $$;
create trigger audit_messages before delete on public.messages
  for each row execute function private.audit_messages();

-- One entry per message, however many reports were closed with it.
create function private.audit_message_reports()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform private.audit('reports.dismissed', private.society_university(n.society_id), n.society_id, null,
      jsonb_build_object('reports', count(*)))
    from new_rows n join old_rows o on o.id = n.id
    where o.dismissed_at is null and n.dismissed_at is not null
    group by n.message_id, n.society_id;
  return null;
end $$;
create trigger audit_message_reports after update on public.message_reports
  referencing old table as old_rows new table as new_rows
  for each statement execute function private.audit_message_reports();

create function private.audit_events()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.cancelled_at is null and new.cancelled_at is not null then
    perform private.audit('event.cancelled', private.society_university(new.society_id), new.society_id, null,
      jsonb_build_object('event_id', new.id, 'title', new.title, 'reason', new.cancel_reason));
  end if;
  return null;
end $$;
create trigger audit_events after update of cancelled_at on public.events
  for each row execute function private.audit_events();

-- ===== Accounts =====
-- Before delete, while the account's university is still recorded.
create function private.audit_profiles()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform private.audit('account.deleted', private.user_university(old.id), null, old.id, '{}');
  return old;
end $$;
create trigger audit_profiles before delete on public.profiles
  for each row execute function private.audit_profiles();

-- Only the triggers above run these.
revoke execute on function private.audit(text, uuid, uuid, uuid, jsonb), private.audit_user_roles(),
  private.audit_university_admins(), private.audit_society_roles(), private.audit_role_invites(),
  private.audit_societies(), private.audit_universities(), private.audit_university_domains(),
  private.audit_messages(), private.audit_message_reports(), private.audit_events(), private.audit_profiles()
  from public, anon, authenticated;

-- ===== 0025_suspension =====

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

-- ===== 0026_retention =====

-- Retention: personal data that only serves a short-term purpose is deleted when that purpose
-- is over. Before, only call transcripts had a limit (7 days, migration 0003); summaries,
-- notifications, AI usage, call participation and closed reports were kept forever. The
-- periods are in docs/privacy/retention.md and are the defaults to agree with each
-- university's Data Protection Officer. Change them there and here together.
--
-- What isn't here is kept while the account or the society exists: profiles, memberships,
-- committee seats, messages, announcements, events and member requests that are still open.
create or replace function public.purge_expired_data()
returns jsonb language plpgsql security definer set search_path = public as $$
declare n jsonb := '{}'; c int;
begin
  -- Call recaps (summary, Q&A, who took part): a year after the call. Transcripts go after 7 days (0003).
  delete from public.call_recaps where created_at < now() - interval '12 months';
  get diagnostics c = row_count; n := n || jsonb_build_object('call_recaps', c);
  -- Who joined which call: only needed to write the recap and count guest link uses.
  delete from public.call_participants where joined_at < now() - interval '90 days';
  get diagnostics c = row_count; n := n || jsonb_build_object('call_participants', c);
  -- Guest links stop working when they expire; keep them a month for questions about them.
  delete from public.call_invites where expires_at < now() - interval '30 days';
  get diagnostics c = row_count; n := n || jsonb_build_object('call_invites', c);
  -- AI quotas look back one hour; a month is enough to review cost or abuse.
  delete from public.ai_usage where created_at < now() - interval '30 days';
  get diagnostics c = row_count; n := n || jsonb_build_object('ai_usage', c);
  -- The fit explanations are a daily cache.
  delete from public.society_fit_cache where created_at < now() - interval '30 days';
  get diagnostics c = row_count; n := n || jsonb_build_object('society_fit_cache', c);
  -- Notifications: read ones after 90 days, any after a year.
  delete from public.notifications
    where (read_at is not null and created_at < now() - interval '90 days') or created_at < now() - interval '12 months';
  get diagnostics c = row_count; n := n || jsonb_build_object('notifications', c);
  -- Who went to an event: a year after it ended. The event itself stays as society history.
  delete from public.event_registrations r using public.events e
    where e.id = r.event_id and coalesce(e.ends_at, e.starts_at) < now() - interval '12 months';
  get diagnostics c = row_count; n := n || jsonb_build_object('event_registrations', c);
  -- Closed reports: a year after they were dismissed. Open ones stay until someone handles them.
  delete from public.message_reports where dismissed_at < now() - interval '12 months';
  get diagnostics c = row_count; n := n || jsonb_build_object('message_reports', c);
  -- Resolved member requests and their history: two years after the last change.
  delete from public.support_requests where status = 'resolved' and updated_at < now() - interval '24 months';
  get diagnostics c = row_count; n := n || jsonb_build_object('support_requests', c);
  -- The audit log: two years, long enough to answer questions about a committee's year.
  delete from public.audit_log where at < now() - interval '24 months';
  get diagnostics c = row_count; n := n || jsonb_build_object('audit_log', c);
  return n;
end $$;
revoke execute on function public.purge_expired_data() from public, anon, authenticated;
select cron.schedule('purge-expired-data', '30 3 * * *', 'select public.purge_expired_data()');

-- ===== 0027_sign_in_health =====

-- Sign-in emails failed for weeks without anyone noticing: they went to Microsoft 365
-- quarantine, and the only signal was students saying so. This counts, for the last day,
-- how many sign-in links were sent and how many were followed by a sign-in, for new
-- accounts (confirmation links) and returning ones (magic links). Links sent in the last 30
-- minutes are left out, to give people time to open them. When enough links go out and
-- few are used, emails are probably not arriving, and /api/health/sign-in returns 503 so an
-- uptime monitor alerts. Only the server's service role can call it.
--
-- Supabase Auth keeps only the latest link per account (confirmation_sent_at for new ones,
-- recovery_sent_at for magic links), so this counts accounts, not emails.
create or replace function public.sign_in_health()
returns jsonb language sql stable security definer set search_path = public as $$
  with sent as (
    select
      count(*) filter (where confirmation_sent_at between now() - interval '24 hours' and now() - interval '30 minutes') as new_sent,
      count(*) filter (where confirmation_sent_at between now() - interval '24 hours' and now() - interval '30 minutes'
                         and email_confirmed_at >= confirmation_sent_at) as new_used,
      count(*) filter (where recovery_sent_at between now() - interval '24 hours' and now() - interval '30 minutes') as returning_sent,
      count(*) filter (where recovery_sent_at between now() - interval '24 hours' and now() - interval '30 minutes'
                         and last_sign_in_at >= recovery_sent_at) as returning_used
    from auth.users
  )
  select jsonb_build_object(
    'new_accounts', jsonb_build_object('sent', new_sent, 'used', new_used),
    'returning', jsonb_build_object('sent', returning_sent, 'used', returning_used),
    -- At least 5 links of a kind, and fewer than 3 in 10 used.
    'status', case when (new_sent >= 5 and new_used * 10 < new_sent * 3)
                     or (returning_sent >= 5 and returning_used * 10 < returning_sent * 3)
                   then 'degraded' else 'ok' end)
  from sent
$$;
revoke execute on function public.sign_in_health() from public, anon, authenticated;
grant execute on function public.sign_in_health() to service_role;

-- ===== 0028_society_import =====

-- Onboarding a university needed a developer: TU Dublin's 67 societies came in through a
-- generated migration (0006). Admins can now import a university's societies from a file
-- (/admin → Import societies), with the same rules as 0006:
--   * each row has the university's own id for the society (or its address), stored as
--     source = the university's slug and source_id, so importing again updates instead of
--     duplicating;
--   * a society an admin already created at the same address is adopted, not duplicated;
--   * names, categories, campus, images and official links are refreshed, but a tagline,
--     description or meeting time the committee has changed since the last import is kept;
--   * interests are added, never removed; societies missing from the file are never deleted.
-- Images and links must be https. The whole file is refused if any row is invalid, with the
-- row number, so nothing is half imported.
create or replace function public.import_societies(_university_id uuid, _rows jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  u public.universities; r jsonb; i int := 0; created int := 0; updated int := 0; tagged int := 0; n int;
  _source_id text; _slug text; _suffix text; _name text; _short text;
  _accents text[] := array['indigo','teal','coral','amber','rose','sky','emerald','plum'];
begin
  if not private.can_manage_university(_university_id, auth.uid()) then
    raise exception 'Only that university''s admins can import its societies.';
  end if;
  select * into u from public.universities where id = _university_id;
  if jsonb_typeof(_rows) is distinct from 'array' or jsonb_array_length(_rows) = 0 then raise exception 'The file has no societies in it.'; end if;
  if jsonb_array_length(_rows) > 500 then raise exception 'Import at most 500 societies at a time.'; end if;

  drop table if exists pg_temp._import;
  create temp table _import (n int, source_id text, suffix text, slug text, name text, short_name text, category text, tagline text,
    description text, meets text, campus text, requires_approval boolean, accent text, join_url text, official_url text,
    contact_email text, logo_url text, banner_url text, interests text[]) on commit drop;

  for r in select value from jsonb_array_elements(_rows) loop
    i := i + 1;
    _name := btrim(coalesce(r->>'name', ''));
    _short := coalesce(nullif(btrim(coalesce(r->>'short_name', '')), ''), left(_name, 30));
    _slug := left(btrim(regexp_replace(lower(coalesce(nullif(btrim(coalesce(r->>'slug', '')), ''), _short)), '[^a-z0-9]+', '-', 'g'), '-'), 40);
    _source_id := coalesce(nullif(btrim(coalesce(r->>'id', '')), ''), _slug);
    _suffix := coalesce(nullif(left(regexp_replace(lower(_source_id), '[^a-z0-9]+', '', 'g'), 20), ''), 'import');
    -- Two rows at one address (the same name on two campuses, say): the second gets its id added.
    if exists (select 1 from _import where slug = _slug) then _slug := left(_slug, 39 - length(_suffix)) || '-' || _suffix; end if;
    if char_length(_name) < 2 or char_length(_name) > 100 then raise exception 'Row %: the name needs 2 to 100 characters.', i; end if;
    if char_length(_short) > 30 then raise exception 'Row %: the short name can be up to 30 characters.', i; end if;
    if _slug !~ '^[a-z0-9-]{2,40}$' then raise exception 'Row %: the address needs at least 2 letters or digits.', i; end if;
    if char_length(coalesce(r->>'tagline', '')) > 140 then raise exception 'Row %: the tagline can be up to 140 characters.', i; end if;
    if char_length(coalesce(r->>'description', '')) > 2000 then raise exception 'Row %: the description can be up to 2,000 characters.', i; end if;
    if char_length(coalesce(r->>'meets', '')) > 140 then raise exception 'Row %: the meeting time can be up to 140 characters.', i; end if;
    if exists (select 1 from unnest(array[r->>'join_url', r->>'official_url', r->>'logo_url', r->>'banner_url']) x
               where coalesce(x, '') <> '' and x !~ '^https://[^\s]+$') then
      raise exception 'Row %: links and images must start with https://.', i;
    end if;
    if coalesce(r->>'contact_email', '') <> '' and r->>'contact_email' !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
      raise exception 'Row %: the contact email doesn''t look like an address.', i;
    end if;
    if exists (select 1 from _import where source_id = _source_id) then raise exception 'Row %: the id % is in the file twice.', i, _source_id; end if;
    insert into _import values (i, _source_id, _suffix, _slug, _name, _short,
      coalesce(nullif(btrim(coalesce(r->>'category', '')), ''), 'Community'),
      btrim(coalesce(r->>'tagline', '')), btrim(coalesce(r->>'description', '')), btrim(coalesce(r->>'meets', '')),
      nullif(btrim(coalesce(r->>'campus', '')), ''),
      coalesce(lower(r->>'requires_approval') in ('true', 'yes', 'y', '1'), false),
      case when r->>'accent' = any(_accents) then r->>'accent' else _accents[1 + (hashtext(_source_id) & 7)] end,
      nullif(r->>'join_url', ''), nullif(r->>'official_url', ''), nullif(btrim(coalesce(r->>'contact_email', '')), ''),
      nullif(r->>'logo_url', ''), nullif(r->>'banner_url', ''),
      array(select btrim(x) from jsonb_array_elements_text(case when jsonb_typeof(r->'interests') = 'array' then r->'interests' else '[]' end) x
            where btrim(x) <> ''));
  end loop;

  -- Adopt societies an admin already created at the same address.
  update public.societies s set source = u.slug, source_id = t.source_id
  from _import t
  where s.university_id = u.id and s.slug = t.slug and s.source_id is null
    and not exists (select 1 from public.societies x where x.source = u.slug and x.source_id = t.source_id);

  -- Refresh; keep text the committee has changed since the last import.
  update public.societies s set
    name = t.name, short_name = t.short_name, category = t.category,
    tagline = case when s.tagline = coalesce(s.source_snapshot->>'tagline', case when s.tagline = '' then '' else null end) then t.tagline else s.tagline end,
    description = case when s.description = coalesce(s.source_snapshot->>'description', case when s.description = '' then '' else null end) then t.description else s.description end,
    meets = case when s.meets = coalesce(s.source_snapshot->>'meets', case when s.meets = '' then '' else null end) then t.meets else s.meets end,
    campus = t.campus, logo_url = t.logo_url, banner_url = t.banner_url, join_url = t.join_url,
    official_url = t.official_url, contact_email = t.contact_email, source_synced_at = now(),
    source_snapshot = jsonb_build_object('tagline', t.tagline, 'description', t.description, 'meets', t.meets)
  from _import t
  where s.source = u.slug and s.source_id = t.source_id and s.university_id = u.id;
  get diagnostics updated = row_count;

  -- New societies; an address another society already uses gets the id added.
  insert into public.societies (university_id, slug, name, short_name, category, tagline, description, meets, campus,
    requires_approval, accent, join_url, official_url, contact_email, logo_url, banner_url,
    source, source_id, source_synced_at, source_snapshot)
  select u.id,
    case when exists (select 1 from public.societies x where x.university_id = u.id and x.slug = t.slug)
         then left(t.slug, 39 - length(t.suffix)) || '-' || t.suffix else t.slug end,
    t.name, t.short_name, t.category, t.tagline, t.description, t.meets, t.campus, t.requires_approval, t.accent,
    t.join_url, t.official_url, t.contact_email, t.logo_url, t.banner_url, u.slug, t.source_id, now(),
    jsonb_build_object('tagline', t.tagline, 'description', t.description, 'meets', t.meets)
  from _import t
  where not exists (select 1 from public.societies s where s.source = u.slug and s.source_id = t.source_id)
  order by t.n;
  get diagnostics created = row_count;

  insert into public.society_tags (society_id, interest_id)
  select s.id, it.id from _import t
  join public.societies s on s.source = u.slug and s.source_id = t.source_id
  cross join lateral unnest(t.interests) wanted(name)
  join public.interests it on lower(it.name) = lower(wanted.name)
  on conflict do nothing;
  get diagnostics tagged = row_count;

  perform private.audit('societies.imported', u.id, null, null,
    jsonb_build_object('created', created, 'updated', updated, 'rows', i));
  return jsonb_build_object('created', created, 'updated', updated, 'tags_added', tagged);
end $$;
revoke execute on function public.import_societies(uuid, jsonb) from public, anon;

-- ===== 0029_society_identity =====

-- Audit finding 17: a committee could rename its society, or change its logo and banner,
-- and present itself as, say, the Students' Union inside an official-looking directory. The
-- committee's own form only edits the tagline, description and meeting details, so this only
-- closes the API. A society's name, short name, category, logo and banner now change only
-- through its university's admins, a platform admin or an import (no signed-in user).
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
      if new.name is distinct from old.name or new.short_name is distinct from old.short_name
         or new.category is distinct from old.category
         or new.logo_url is distinct from old.logo_url or new.banner_url is distinct from old.banner_url then
        raise exception 'Only your university''s admins can change a society''s name, category, logo or banner.';
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

-- ===== 0030_saved_proposals_visible =====

-- Audit finding 27: anyone signed in could save any proposal id, and the error for an
-- unknown id (a foreign key violation, unlike the policy error for a known one) told them
-- whether it existed. Only proposals the person can read can be saved now; the check runs
-- before the foreign key, so unknown and hidden ids get the same refusal.
drop policy "Save own" on public.saved_proposals;
create policy "Save own" on public.saved_proposals for insert to authenticated
  with check (
    user_id = auth.uid()
    and exists (select 1 from public.collaboration_proposals p where p.id = proposal_id)
  );

-- ===== Bookkeeping =====
-- Lovable runs migrations with Drizzle. If Drizzle keeps its record in this database, note these
-- updates there too, so it never tries to run them a second time.
do $record$
begin
  if to_regclass('drizzle.__drizzle_migrations') is not null then
    insert into drizzle.__drizzle_migrations (hash, created_at) values
      ('474ce10e305d15aca3e644e580bbae0d53f281ccf110f970bc626044e1a1584a', 1792105221924),
      ('3f2d281e13ce11ca28d5a27a51bdfe63cfeb626ec41c342573c57785b44928bb', 1792105334563),
      ('6b9f56e08bab728367004396d05a9eed39c9ad199e9283878514501370e06307', 1792105528976),
      ('f5cdbc3b8799d8ba843a307c4f71c7d33f9a12716d095183472f77791c684c71', 1792105584160),
      ('5156cd05b75ac1e38eacee57714d469352399b9ee2a21bf61d6c8bce8f62dba2', 1792105644065),
      ('ebd80b59a5d988dede69b847181cdf1e3764983eef208e5545f1ac94c7800937', 1792105720174),
      ('b136829ab184e55a1e34cb096ae9664e455a4ab70c892169a7d767e55737dc08', 1792108173880),
      ('7199ee1bfa6e687aa4341e472aa18c08b62c8392b8bce50eeb76fc20253a2725', 1792108496112),
      ('2f9827302190b5ce86bf5d2fa952b6ee76553fd437a3a3e0b6d7ee30f87cac1d', 1792108754778),
      ('6963d6d4634beb50e36eeb6f2bad657241963da2f47e865fc4c669e1a7c82f77', 1792108934701),
      ('b7b7c18eaa33b404af4acc76b7d06490f215424c0966b185915f191f56cb4ce7', 1792113315828),
      ('b97b4f9118e813882369f13e95943abbb3d5526679bacdcec1c2f0992d86617b', 1792113369856),
      ('6c4999544bd56dcf9a48ae9bb3ac44d63ed51226b84a99732cda9448b5987164', 1792113369885),
      ('6ed87b89a529ed3333884d5c04fa644288afb895df2bb16694a2e0ab2525dece', 1792113369915),
      ('00beba55a1df80c2f45e7c888118b319acde338cd0578b83e84b64425135838e', 1792113631752),
      ('466c21198bd50e24d218037bdff72f5ca66153bee601528d7079cb64ade6a5f5', 1792113695656),
      ('282d1e41389c6c9aea02af8bd29d8fbf3a215c61129dc1aba17ae2b427cb3a9e', 1792113760296),
      ('fb58d6fb8a33d5f82d22301989878b08a23bbfc56a6fa7fe0c3e896269d46f21', 1792118026697),
      ('d6c39047a4db65eb3d82362e413381b952155618252c6ecdbff02b19c9fd77ce', 1792118503742),
      ('b38da689ebb4c3f2dadef9cb6d8540e57aa9fc46d1a2b9ca290cb94e67067d35', 1792119119684),
      ('e37db470907e3f0e00de6a203f6d9f106085a3018d019d3a7d320f298524bd5f', 1792119781722),
      ('25c5f05c48e299c712f06297c07b3f0ca7e7a8fe7b062f0af71e4dc7c04ed960', 1792120191276),
      ('db600d4c0256cdabfbb4e110222f9ec8edab18c0e643daa38657ba0ad5469734', 1792120251276),
      ('8b74b9f6a13290364800d187b1fc19951beb7011749d3d0fe8fe2899d8284df2', 1792120311276);
  end if;
end $record$;

commit;
