begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

-- Membership fees and the demo checkout (0035). Who may call the functions is in the permission
-- matrix; these are the rules inside them. Ids are md5('<name>')::uuid.
insert into auth.users (id, email, aud, role)
  select md5(n)::uuid, n || '.fees@mytudublin.ie', 'authenticated', 'authenticated'
  from unnest('{treasurer,ann,bob,cara,dan}'::text[]) n;
insert into public.societies (id, slug, name, short_name, requires_approval, university_id, membership_fee_cents) values
  (md5('paid')::uuid, 'fees-paid', 'Fees Paid Society', 'PaidSoc', false, md5('tudublin')::uuid, 500),
  (md5('free')::uuid, 'fees-free', 'Fees Free Society', 'FreeSoc', false, md5('tudublin')::uuid, null);
insert into public.society_roles (society_id, user_id) values (md5('paid')::uuid, md5('treasurer')::uuid);
insert into public.society_memberships (id, society_id, user_id, status) values
  (md5('ann at paid')::uuid, md5('paid')::uuid, md5('ann')::uuid, 'member'),
  (md5('bob at paid')::uuid, md5('paid')::uuid, md5('bob')::uuid, 'pending'),
  (md5('cara at paid')::uuid, md5('paid')::uuid, md5('cara')::uuid, 'member'),
  (md5('ann at free')::uuid, md5('free')::uuid, md5('ann')::uuid, 'member');

create function pg_temp.act_as(_name text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', md5(_name)::uuid, 'role', 'authenticated')::text, true);
end $$;
create function pg_temp.paid(_membership text) returns text language sql as $$
  select coalesce(fee_paid_how || ' ' || fee_paid_cents, 'unpaid') from public.society_memberships where id = md5(_membership)::uuid
$$;

select throws_ok($$update public.societies set membership_fee_cents = 0 where id = md5('free')::uuid$$, '23514', null, 'a fee is at least one cent');
select throws_ok($$update public.societies set membership_fee_cents = 50001 where id = md5('free')::uuid$$, '23514', null, 'and at most €500');

set local role authenticated;
-- The demo checkout
select pg_temp.act_as('ann');
select lives_ok($$select public.pay_membership_fee_demo(md5('paid')::uuid)$$, 'a member pays through the demo checkout');
select is(pg_temp.paid('ann at paid'), 'demo 500', 'it''s recorded as a demo payment of the fee');
select throws_ok($$select public.pay_membership_fee_demo(md5('paid')::uuid)$$, 'P0001', 'You''ve already paid for PaidSoc.', 'paying twice is refused');
select throws_ok($$select public.pay_membership_fee_demo(md5('free')::uuid)$$, 'P0001', 'FreeSoc has no membership fee.', 'free societies take no payment');
select pg_temp.act_as('bob');
select lives_ok($$select public.pay_membership_fee_demo(md5('paid')::uuid)$$, 'someone waiting for approval can pay');
select pg_temp.act_as('dan');
select throws_ok($$select public.pay_membership_fee_demo(md5('paid')::uuid)$$, 'P0001', 'Join PaidSoc before paying its membership fee.', 'people who haven''t joined can''t pay');
select pg_temp.act_as('cara');
select is_empty($$select 1 from public.society_memberships where user_id <> md5('cara')::uuid and fee_paid_at is not null$$, 'members don''t see who else has paid');

-- The committee
select throws_ok($$select public.set_membership_fee_paid(md5('cara at paid')::uuid, true)$$, 'P0001', 'Only the society''s committee can mark fees as paid.', 'members can''t mark themselves paid');
select pg_temp.act_as('treasurer');
select set_eq($$select user_id, fee_paid_how from public.society_memberships where society_id = md5('paid')::uuid$$,
  $$values (md5('ann')::uuid, 'demo'), (md5('bob')::uuid, 'demo'), (md5('cara')::uuid, null)$$, 'the committee sees who has paid, and how');
select lives_ok($$select public.set_membership_fee_paid(md5('cara at paid')::uuid, true)$$, 'the committee marks a payment made elsewhere');
select is(pg_temp.paid('cara at paid'), 'committee 500', 'it''s recorded as marked by the committee');
select lives_ok($$select public.set_membership_fee_paid(md5('ann at paid')::uuid, false)$$, 'the committee can undo a payment');
select is(pg_temp.paid('ann at paid'), 'unpaid', 'and it''s gone');
select pg_temp.act_as('ann');
select lives_ok($$select public.pay_membership_fee_demo(md5('paid')::uuid)$$, 'after an undo, the member can pay again');
select lives_ok($$select public.leave_society(md5('paid')::uuid)$$, 'a member who paid can leave');
select is((select count(*)::int from public.society_memberships where id = md5('ann at paid')::uuid), 0, 'and the payment record goes with the membership');

select * from finish();
rollback;
