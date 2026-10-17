-- Membership fees, before there's a payment provider. A committee sets its society's fee; a
-- member pays it either through a demo checkout, which takes no money and asks for no card or
-- bank details, or for real wherever the society takes payments (for TU Dublin societies,
-- mystudentlife), after which the committee marks them paid. Committees see who has paid and
-- how, so a demo payment is never mistaken for money received.
--
-- Payment status sits on the membership row, so it's read like the membership itself: by the
-- member and by the society's committee (the existing read policy). It goes when the
-- membership goes. Like membership decisions, it stays out of the audit log.

alter table public.societies add column membership_fee_cents integer
  check (membership_fee_cents is null or membership_fee_cents between 1 and 50000);

alter table public.society_memberships
  add column fee_paid_at timestamptz,
  add column fee_paid_cents integer,
  -- 'demo': the demo checkout, no money taken. 'committee': the committee marked it paid.
  add column fee_paid_how text check (fee_paid_how in ('demo', 'committee')),
  add constraint society_memberships_fee_paid_complete check ((fee_paid_at is null) = (fee_paid_how is null));

create function public.pay_membership_fee_demo(_society_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare s public.societies; m public.society_memberships;
begin
  select * into s from public.societies where id = _society_id;
  select * into m from public.society_memberships
    where society_id = _society_id and user_id = auth.uid() and status in ('member', 'pending') for update;
  if not found or private.is_suspended(auth.uid()) then
    raise exception 'Join % before paying its membership fee.', coalesce(s.short_name, 'the society');
  end if;
  if s.membership_fee_cents is null then raise exception '% has no membership fee.', s.short_name; end if;
  if m.fee_paid_at is not null then raise exception 'You''ve already paid for %.', s.short_name; end if;
  update public.society_memberships
    set fee_paid_at = now(), fee_paid_cents = s.membership_fee_cents, fee_paid_how = 'demo'
    where id = m.id;
end $$;
revoke execute on function public.pay_membership_fee_demo(uuid) from public, anon;

-- For payments made outside SocConnect, and for undoing a mistake.
create function public.set_membership_fee_paid(_membership_id uuid, _paid boolean)
returns void language plpgsql security definer set search_path = public as $$
declare m public.society_memberships;
begin
  select * into m from public.society_memberships where id = _membership_id for update;
  if not found or not private.is_society_committee(m.society_id, auth.uid()) then
    raise exception 'Only the society''s committee can mark fees as paid.';
  end if;
  if _paid and m.fee_paid_at is null then
    update public.society_memberships
      set fee_paid_at = now(), fee_paid_how = 'committee',
          fee_paid_cents = (select membership_fee_cents from public.societies where id = m.society_id)
      where id = m.id;
  elsif not _paid then
    update public.society_memberships set fee_paid_at = null, fee_paid_cents = null, fee_paid_how = null
      where id = m.id;
  end if;
end $$;
revoke execute on function public.set_membership_fee_paid(uuid, boolean) from public, anon;
