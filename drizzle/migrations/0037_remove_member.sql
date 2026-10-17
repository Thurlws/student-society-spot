-- Committees remove members, from the society page's Members tab. Before, only members could end
-- a membership (leave_society). The person is told, with the reason if one is given, as with a
-- removed message (0032). The membership row goes, and with it any fee payment record. In an
-- open society they can join again, as after leaving. Committee seats are changed by admins, so
-- a committee member's own membership can't be removed here. Like membership decisions, it stays
-- out of the audit log, because it would show admins who belonged to which society.
create function public.remove_member(_membership_id uuid, _reason text default '')
returns void language plpgsql security definer set search_path = public as $$
declare m public.society_memberships; s public.societies; why text := left(btrim(coalesce(_reason, '')), 300);
begin
  select * into m from public.society_memberships where id = _membership_id for update;
  if not found or not private.is_society_committee(m.society_id, auth.uid()) then
    raise exception 'Only the society''s committee can remove members.';
  end if;
  select * into s from public.societies where id = m.society_id;
  if m.status <> 'member' then raise exception 'Only members can be removed. Decline a request instead.'; end if;
  if exists (select 1 from public.society_roles where society_id = m.society_id and user_id = m.user_id) then
    raise exception 'They''re on the % committee. An admin changes the committee.', s.short_name;
  end if;
  delete from public.society_memberships where id = m.id;
  perform public.notify_user(m.user_id, 'requests', 'You were removed from ' || s.short_name,
    'The ' || s.short_name || ' committee removed you from the society'
      || case when why <> '' then '. Reason: ' || why else '' end
      || '. If you think it was a mistake, contact the committee.',
    jsonb_build_object('to', '/societies/$societyId', 'params', jsonb_build_object('societyId', s.slug)), null);
end $$;
revoke execute on function public.remove_member(uuid, text) from public, anon;
