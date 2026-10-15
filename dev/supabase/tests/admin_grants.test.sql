begin;
create extension if not exists pgtap with schema extensions;
select plan(2);

insert into auth.users (id, email, aud, role) values
  ('00000000-0000-0000-0000-00000000a001', 'staff.member@tudublin.ie', 'authenticated', 'authenticated');
select ok(
  not exists (select 1 from public.user_roles where user_id = '00000000-0000-0000-0000-00000000a001'),
  'a staff sign-up does not become platform admin'
);

insert into public.role_invites (email, role) values ('invited.admin@mytudublin.ie', 'platform_admin');
insert into auth.users (id, email, aud, role) values
  ('00000000-0000-0000-0000-00000000a002', 'invited.admin@mytudublin.ie', 'authenticated', 'authenticated');
select ok(
  exists (select 1 from public.user_roles where user_id = '00000000-0000-0000-0000-00000000a002' and role = 'platform_admin'),
  'an invited address becomes platform admin on sign-up'
);

select * from finish();
rollback;
