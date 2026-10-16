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
