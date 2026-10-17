begin;
create extension if not exists pgtap with schema extensions;
select plan(24);

-- Committees adding, changing and deleting channels (0034). Who may call the functions is in
-- the permission matrix; these are the rules inside them. Ids are md5('<name>')::uuid.
insert into auth.users (id, email, aud, role)
  select md5(n)::uuid, n || '.chan@mytudublin.ie', 'authenticated', 'authenticated'
  from unnest('{chair,ann,bob}'::text[]) n;
insert into public.societies (id, slug, name, short_name, university_id) values
  (md5('soc')::uuid, 'chan-soc', 'Channel Test Society', 'ChanSoc', md5('tudublin')::uuid);
insert into public.society_roles (society_id, user_id) values (md5('soc')::uuid, md5('chair')::uuid);
insert into public.society_memberships (society_id, user_id, status) values
  (md5('soc')::uuid, md5('ann')::uuid, 'member'), (md5('soc')::uuid, md5('bob')::uuid, 'member');
insert into public.messages (channel_id, author_id, body)
  select c.id, md5(v.author)::uuid, v.body from public.channels c
  cross join (values ('ann', 'Lift from Bray?'), ('ann', 'Leaving at six'), ('bob', 'Room for one more'), ('chair', 'Thanks all')) v(author, body)
  where c.society_id = md5('soc')::uuid and c.slug = 'events';

create function pg_temp.act_as(_name text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', md5(_name)::uuid, 'role', 'authenticated')::text, true);
end $$;
create function pg_temp.channel(_name text) returns uuid language sql as $$
  select id from public.channels where society_id = md5('soc')::uuid and name = _name
$$;
set local role authenticated;

-- Adding
select pg_temp.act_as('ann');
select throws_ok($$select public.create_channel(md5('soc')::uuid, 'lifts')$$, 'P0001', 'Only the society''s committee can add channels.', 'members can''t add channels');
select pg_temp.act_as('chair');
select lives_ok($$select public.create_channel(md5('soc')::uuid, '  Kit & Lifts! ', 'Who brings what')$$, 'the committee adds a channel');
select results_eq($$select name || ' ' || slug || ' ' || description || ' ' || committee_only from public.channels where id = pg_temp.channel('kit-lifts')$$,
  array['kit-lifts kit-lifts Who brings what false'], 'its name is cleaned into lower case and dashes');
select throws_ok($$select public.create_channel(md5('soc')::uuid, 'KIT lifts')$$, 'P0001', 'There''s already a #kit-lifts channel.', 'names are unique in the society');
select throws_ok($$select public.create_channel(md5('soc')::uuid, '!!!')$$, 'P0001', 'Give the channel a name with letters or numbers.', 'a name needs letters or numbers');
select throws_ok($$select public.create_channel(md5('soc')::uuid, repeat('a', 31))$$, 'P0001', 'Keep the channel name to 30 characters.', 'names are short');
select throws_ok($$select public.create_channel(md5('soc')::uuid, 'notes', repeat('a', 201))$$, 'P0001', 'Keep the description to 200 characters.', 'descriptions are short');

-- Changing
select lives_ok($$select public.update_channel(pg_temp.channel('kit-lifts'), 'Notices', 'From the committee', true)$$, 'the committee renames a channel and makes it committee-only');
select results_eq($$select name || ' ' || slug || ' ' || committee_only from public.channels where id = pg_temp.channel('notices')$$,
  array['notices kit-lifts true'], 'the name changes; the address stays');
select throws_ok($$select public.update_channel(pg_temp.channel('notices'), 'general', '', true)$$, 'P0001', 'There''s already a #general channel.', 'a rename can''t take another channel''s name');
select pg_temp.act_as('ann');
select throws_ok($$select public.update_channel(pg_temp.channel('notices'), 'mine', '', false)$$, 'P0001', 'Only the society''s committee can change channels.', 'members can''t change channels');

-- Committee-only
select throws_ok($$insert into public.messages (channel_id, author_id, body) values (pg_temp.channel('notices'), md5('ann')::uuid, 'Can I post?')$$,
  '42501', 'new row violates row-level security policy for table "messages"', 'members can''t post in a committee-only channel');
select lives_ok($$insert into public.messages (channel_id, author_id, body) values (pg_temp.channel('general'), md5('ann')::uuid, 'Hello')$$, 'but still post elsewhere');
select pg_temp.act_as('chair');
select lives_ok($$insert into public.messages (channel_id, author_id, body) values (pg_temp.channel('notices'), md5('chair')::uuid, 'AGM on Friday')$$, 'the committee posts there');

-- Deleting
select pg_temp.act_as('bob');
select throws_ok($$select public.delete_channel(pg_temp.channel('events'))$$, 'P0001', 'Only the society''s committee can delete channels.', 'members can''t delete channels');
select pg_temp.act_as('chair');
select throws_ok($$select public.delete_channel(pg_temp.channel('general'))$$, 'P0001', '#general can''t be deleted: call recaps are shared there.', '#general stays');
select lives_ok($$select public.update_channel(pg_temp.channel('general'), 'lobby', 'Say hello', false)$$, '#general can be renamed');
select throws_ok($$select public.delete_channel(pg_temp.channel('lobby'))$$, 'P0001', '#lobby can''t be deleted: call recaps are shared there.', 'and still can''t be deleted');
select lives_ok($$select public.delete_channel(pg_temp.channel('events'))$$, 'the committee deletes a channel');
reset role;
select is((select count(*)::int from public.messages m join public.channels c on c.id = m.channel_id where c.society_id = md5('soc')::uuid and c.slug = 'events'), 0,
  'its messages go with it');
-- Digital Services Act, article 17: authors are told their messages were removed.
select results_eq($$select body from public.notifications where title = 'A channel was deleted' and user_id = md5('ann')::uuid$$,
  array['The ChanSoc committee deleted the #events channel, and your messages in it with it. If you think it was a mistake, send the committee a request from the society''s page.'],
  'each author is told once');
select results_eq($$select u from unnest('{ann,bob,chair}'::text[]) u where exists (select 1 from public.notifications where title = 'A channel was deleted' and user_id = md5(u)::uuid)$$,
  array['ann', 'bob'], 'everyone but the committee member who deleted it');
select results_eq($$select action || ' ' || (details->>'channel') || ' ' || (details->>'messages') from public.audit_log where society_id = md5('soc')::uuid and action in ('channel.deleted', 'message.removed')$$,
  array['channel.deleted events 4'], 'the deletion is in the audit log once, without the authors');

-- At most 20 channels: lobby, questions and notices are left.
set local role authenticated;
select pg_temp.act_as('chair');
do $$ begin perform public.create_channel(md5('soc')::uuid, 'extra ' || i) from generate_series(1, 17) i; end $$;
select throws_ok($$select public.create_channel(md5('soc')::uuid, 'one too many')$$, 'P0001', 'A society can have up to 20 channels.', 'a society has at most 20 channels');

select * from finish();
rollback;
