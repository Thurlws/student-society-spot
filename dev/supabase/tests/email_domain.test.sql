begin;
create extension if not exists pgtap with schema extensions;
select plan(5);

select throws_ok(
  $$insert into auth.users (id, email, aud, role) values ('00000000-0000-0000-0000-00000000d001', 'someone@gmail.com', 'authenticated', 'authenticated')$$,
  'P0001', 'Please use your TU Dublin email (@mytudublin.ie)', 'sign-up with a personal address is refused');

insert into auth.users (id, email, aud, role) values
  ('00000000-0000-0000-0000-00000000d002', 'student@mytudublin.ie', 'authenticated', 'authenticated');

select throws_ok(
  $$update auth.users set email_change = 'me@gmail.com' where id = '00000000-0000-0000-0000-00000000d002'$$,
  'P0001', 'Please use your TU Dublin email (@mytudublin.ie)', 'requesting a change to a personal address is refused');
select throws_ok(
  $$update auth.users set email = 'me@gmail.com' where id = '00000000-0000-0000-0000-00000000d002'$$,
  'P0001', 'Please use your TU Dublin email (@mytudublin.ie)', 'changing to a personal address is refused');
select lives_ok(
  $$update auth.users set email_change = 'new.address@mytudublin.ie' where id = '00000000-0000-0000-0000-00000000d002'$$,
  'changing to another university address works');
select lives_ok(
  $$update auth.users set email = email, raw_user_meta_data = '{"x":1}' where id = '00000000-0000-0000-0000-00000000d002'$$,
  'updates that keep the email work');

select * from finish();
rollback;
