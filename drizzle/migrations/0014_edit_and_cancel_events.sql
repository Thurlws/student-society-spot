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
