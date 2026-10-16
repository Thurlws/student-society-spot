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
