begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

-- Committees removing members (0037). Who may call it is in the permission matrix; these are the
-- rules inside it. Ids are md5('<name>')::uuid.
insert into auth.users (id, email, aud, role)
  select md5(n)::uuid, n || '.remove@mytudublin.ie', 'authenticated', 'authenticated'
  from unnest('{chair,treasurer,ann,bob,cara}'::text[]) n;
insert into public.societies (id, slug, name, short_name, requires_approval, university_id) values
  (md5('soc')::uuid, 'remove-soc', 'Remove Test Society', 'RemoveSoc', false, md5('tudublin')::uuid);
insert into public.society_roles (society_id, user_id) values
  (md5('soc')::uuid, md5('chair')::uuid), (md5('soc')::uuid, md5('treasurer')::uuid);
insert into public.society_memberships (id, society_id, user_id, status) values
  (md5('ann at soc')::uuid, md5('soc')::uuid, md5('ann')::uuid, 'member'),
  (md5('bob at soc')::uuid, md5('soc')::uuid, md5('bob')::uuid, 'member'),
  (md5('cara at soc')::uuid, md5('soc')::uuid, md5('cara')::uuid, 'pending'),
  -- The treasurer joined as a member before taking a committee seat.
  (md5('treasurer at soc')::uuid, md5('soc')::uuid, md5('treasurer')::uuid, 'member');

create function pg_temp.act_as(_name text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', md5(_name)::uuid, 'role', 'authenticated')::text, true);
end $$;
set local role authenticated;

select pg_temp.act_as('bob');
select throws_ok($$select public.remove_member(md5('ann at soc')::uuid)$$, 'P0001', 'Only the society''s committee can remove members.', 'members can''t remove each other');
select pg_temp.act_as('chair');
select throws_ok($$select public.remove_member(md5('cara at soc')::uuid)$$, 'P0001', 'Only members can be removed. Decline a request instead.', 'a request is declined, not removed');
select throws_ok($$select public.remove_member(md5('treasurer at soc')::uuid)$$, 'P0001', 'They''re on the RemoveSoc committee. An admin changes the committee.', 'committee members stay');
select lives_ok($$select public.remove_member(md5('ann at soc')::uuid, '  Spamming the channels  ')$$, 'the committee removes a member, saying why');
select is_empty($$select 1 from public.society_memberships where id = md5('ann at soc')::uuid$$, 'the membership is gone');
select throws_ok($$select public.remove_member(md5('ann at soc')::uuid)$$, 'P0001', 'Only the society''s committee can remove members.', 'removing twice is refused');
select lives_ok($$select public.remove_member(md5('bob at soc')::uuid)$$, 'a reason is optional');
reset role;
select results_eq($$select title || ': ' || body from public.notifications where user_id = md5('ann')::uuid$$,
  array['You were removed from RemoveSoc: The RemoveSoc committee removed you from the society. Reason: Spamming the channels. If you think it was a mistake, contact the committee.'],
  'the person is told, and why');
set local role authenticated;
select pg_temp.act_as('ann');
select is(public.join_society(md5('soc')::uuid), 'member', 'in an open society they can join again, as after leaving');

select * from finish();
rollback;
