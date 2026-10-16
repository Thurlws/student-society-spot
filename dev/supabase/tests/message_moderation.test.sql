begin;
create extension if not exists pgtap with schema extensions;
select plan(21);

-- Reporting, removing and dismissing messages. Ids are md5('<name>')::uuid.
insert into auth.users (id, email, aud, role)
  select md5(n)::uuid, n || '.mod@mytudublin.ie', 'authenticated', 'authenticated'
  from unnest('{chair,cochair,troll,reader,outsider,admin}'::text[]) n;
insert into public.user_roles (user_id, role) values (md5('admin')::uuid, 'platform_admin');
insert into public.societies (id, slug, name, short_name, university_id) values (md5('soc')::uuid, 'mod-soc', 'Moderation Test Society', 'ModSoc', md5('tudublin')::uuid);
insert into public.society_roles (society_id, user_id) values (md5('soc')::uuid, md5('chair')::uuid), (md5('soc')::uuid, md5('cochair')::uuid);
insert into public.society_memberships (society_id, user_id, status) values
  (md5('soc')::uuid, md5('troll')::uuid, 'member'), (md5('soc')::uuid, md5('reader')::uuid, 'member');
insert into public.messages (id, channel_id, author_id, body)
  select md5(v.id)::uuid, c.id, md5(v.author)::uuid, v.body from public.channels c
  cross join (values ('rude', 'troll', 'You are all idiots'), ('fine', 'reader', 'See you Thursday'), ('typo', 'reader', 'Se you Thursday'),
    ('chairpost', 'chair', 'Committee only, no plebs'), ('spam', 'troll', 'Buy followers here')) v(id, author, body)
  where c.society_id = md5('soc')::uuid and c.slug = 'general';

create function pg_temp.act_as(_name text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', md5(_name)::uuid, 'role', 'authenticated')::text, true);
end $$;
set local role authenticated;

-- Reporting
select pg_temp.act_as('outsider');
select throws_ok($$select public.report_message(md5('rude')::uuid, '')$$, 'P0001', 'That message doesn''t exist.', 'people outside the society can''t report its messages');
select pg_temp.act_as('reader');
select lives_ok($$select public.report_message(md5('rude')::uuid, 'Insulting everyone')$$, 'a member reports a message');
select throws_ok($$select public.report_message(md5('rude')::uuid, '')$$, 'P0001', 'You''ve already reported this message.', 'reporting twice is refused');
select throws_ok($$select public.report_message(md5('fine')::uuid, '')$$, 'P0001', 'You can''t report your own message. Delete it instead.', 'you can''t report yourself');
select throws_ok($$select public.delete_message(md5('rude')::uuid)$$, 'P0001', 'You can only delete your own messages.', 'a member can''t delete someone else''s message');
select lives_ok($$select public.delete_message(md5('typo')::uuid)$$, 'authors can delete their own messages');
select pg_temp.act_as('troll');
select is_empty($$select 1 from public.message_reports$$, 'the author can''t see who reported them');

-- The committee and admins
select pg_temp.act_as('chair');
select results_eq($$select title from public.notifications where user_id = md5('chair')::uuid and dedupe_key = 'mr:' || md5('rude')::uuid$$,
  array['Message reported in ModSoc'], 'the committee is notified');
select results_eq($$select excerpt || ' / ' || reason from public.message_reports where dismissed_at is null$$,
  array['You are all idiots / Insulting everyone'], 'and sees the report with an excerpt');
select pg_temp.act_as('admin');
select is((select count(*)::int from public.message_reports where society_id = md5('soc')::uuid), 1, 'platform admins see reports from any society');
select lives_ok($$select public.dismiss_message_reports(md5('rude')::uuid)$$, 'an admin can dismiss them');
select throws_ok($$select public.dismiss_message_reports(md5('rude')::uuid)$$, 'P0001', 'There are no open reports for this message.', 'dismissing twice is refused');
select pg_temp.act_as('chair');
select lives_ok($$select public.delete_message(md5('rude')::uuid)$$, 'the committee removes the message');
reset role;
select is((select count(*)::int from public.message_reports where message_id = md5('rude')::uuid), 0, 'its reports go with it');


-- Reports about a committee member's own message go to the rest of the committee.
set local role authenticated;
select pg_temp.act_as('reader');
select lives_ok($$select public.report_message(md5('chairpost')::uuid, 'Rude to members')$$, 'a member reports a committee member''s message');
select pg_temp.act_as('chair');
select is_empty($$select 1 from public.message_reports where message_id = md5('chairpost')::uuid$$, 'the committee member it''s about can''t see who reported it');
select throws_ok($$select public.dismiss_message_reports(md5('chairpost')::uuid)$$, 'P0001',
  'Reports about your own message are for the rest of the committee to handle.', 'or dismiss it');
reset role;
select results_eq($$select user_id from public.notifications where dedupe_key = 'mr:' || md5('chairpost')::uuid$$,
  array[md5('cochair')::uuid], 'only the rest of the committee is notified');
select is((select link->'search'->>'society' from public.notifications where dedupe_key = 'mr:' || md5('chairpost')::uuid),
  'mod-soc', 'the notification opens that society''s dashboard');
set local role authenticated;
select pg_temp.act_as('cochair');
select lives_ok($$select public.report_message(md5('spam')::uuid, '')$$, 'a committee member reports a message');
reset role;
select results_eq($$select user_id from public.notifications where dedupe_key = 'mr:' || md5('spam')::uuid$$,
  array[md5('chair')::uuid], 'and isn''t notified about their own report');

select * from finish();
rollback;
