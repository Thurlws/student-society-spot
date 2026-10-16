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
