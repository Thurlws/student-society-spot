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
