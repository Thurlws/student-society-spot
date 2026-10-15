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

