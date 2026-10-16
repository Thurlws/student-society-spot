begin;
create extension if not exists pgtap with schema extensions;
select plan(5);

insert into auth.users (id, email, aud, role) values
  (md5('ann chair')::uuid, 'ann.chair@mytudublin.ie', 'authenticated', 'authenticated');
insert into public.societies (id, slug, name, short_name) values (md5('ann soc')::uuid, 'ann-soc', 'Announcement Test Society', 'AnnSoc');
insert into public.society_roles (society_id, user_id) values (md5('ann soc')::uuid, md5('ann chair')::uuid);
insert into public.announcements (id, society_id, author_id, title, body) values
  (md5('post')::uuid, md5('ann soc')::uuid, md5('ann chair')::uuid, 'AGM', 'The AGM is on Thursday at six.');

set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub', md5('ann chair')::uuid, 'role', 'authenticated')::text, true);

update public.announcements set pinned = true where id = md5('post')::uuid;
select is((select edited_at from public.announcements where id = md5('post')::uuid), null, 'pinning doesn''t mark a post as edited');
update public.announcements set body = 'The AGM is on Thursday at seven.' where id = md5('post')::uuid;
select isnt((select edited_at from public.announcements where id = md5('post')::uuid), null, 'changing the wording does');
select throws_ok($$update public.announcements set edited_at = null where id = md5('post')::uuid$$, '42501', null, 'the edited mark can''t be cleared');
select lives_ok($$delete from public.announcements where id = md5('post')::uuid$$, 'the committee can delete it');
select is((select count(*)::int from public.announcements where id = md5('post')::uuid), 0, 'and it''s gone');

reset role;
select * from finish();
rollback;
