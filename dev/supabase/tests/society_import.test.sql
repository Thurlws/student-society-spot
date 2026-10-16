begin;
create extension if not exists pgtap with schema extensions;
select plan(17);

-- Importing a university's societies from a file. ImportU is a new university with one
-- society an admin already made by hand. Ids are md5('<name>')::uuid.
insert into public.universities (id, slug, name, short_name) values (md5('importu')::uuid, 'importu', 'Import University', 'ImportU');
insert into public.university_domains values ('importu.test', md5('importu')::uuid);
insert into auth.users (id, email, aud, role) values
  (md5('iadmin')::uuid, 'iadmin@importu.test', 'authenticated', 'authenticated'),
  (md5('tudadmin')::uuid, 'tudadmin.import@tudublin.ie', 'authenticated', 'authenticated');
insert into public.university_admins values (md5('importu')::uuid, md5('iadmin')::uuid), (md5('tudublin')::uuid, md5('tudadmin')::uuid);
insert into public.societies (id, slug, name, short_name, university_id) values
  (md5('handmade')::uuid, 'chess', 'Chess', 'Chess', md5('importu')::uuid);

create function pg_temp.act_as(_name text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', md5(_name)::uuid, 'role', 'authenticated')::text, true);
end $$;
set local role authenticated;

select pg_temp.act_as('tudadmin');
select throws_ok($$select public.import_societies(md5('importu')::uuid, '[{"id": "1", "name": "Chess Society"}]')$$,
  'P0001', 'Only that university''s admins can import its societies.', 'another university''s admin can''t import');

select pg_temp.act_as('iadmin');
select throws_ok($$select public.import_societies(md5('importu')::uuid, '[{"id": "1", "name": "Chess"}, {"id": "2", "name": "X"}]')$$,
  'P0001', 'Row 2: the name needs 2 to 100 characters.', 'a bad row is refused with its number');
select throws_ok($$select public.import_societies(md5('importu')::uuid, '[{"id": "1", "name": "Chess", "join_url": "javascript:alert(1)"}]')$$,
  'P0001', 'Row 1: links and images must start with https://.', 'links must be https');
select throws_ok($$select public.import_societies(md5('importu')::uuid, '[{"id": "1", "name": "Chess"}, {"id": "1", "name": "Drama"}]')$$,
  'P0001', 'Row 2: the id 1 is in the file twice.', 'ids must be unique');
select is((select count(*)::int from public.societies where university_id = md5('importu')::uuid), 1, 'a refused file imports nothing');

select is(public.import_societies(md5('importu')::uuid, $$[
  {"id": "101", "name": "Chess", "short_name": "Chess", "tagline": "Checkmate", "interests": ["Gaming", "Science", "Nonsense"]},
  {"id": "102", "name": "Drama Society", "short_name": "Drama", "requires_approval": "yes", "join_url": "https://importu.test/join/102"},
  {"id": "103", "name": "Drama Society (North campus)", "short_name": "Drama", "campus": "North"}
]$$), '{"created": 2, "updated": 1, "tags_added": 2}'::jsonb, 'the first import adopts one society and creates two');
select results_eq($$select slug || ' ' || coalesce(source_id, '-') from public.societies where university_id = md5('importu')::uuid order by slug$$,
  array['chess 101', 'drama 102', 'drama-103 103'], 'the hand-made society is adopted, and a second Drama gets its id in its address');
select is((select id from public.societies where source = 'importu' and source_id = '101'), md5('handmade')::uuid, 'keeping its id, members and events');
select ok((select requires_approval from public.societies where source_id = '102' and source = 'importu'), 'requires_approval reads yes');
select results_eq($$select i.name from public.society_tags t join public.interests i on i.id = t.interest_id where t.society_id = md5('handmade')::uuid order by 1$$,
  array['Gaming', 'Science'], 'known interests are added, unknown ones ignored');

-- The committee edits the tagline; the next import changes the name and drops a tag.
reset role;
update public.societies set tagline = 'Our own words' where id = md5('handmade')::uuid;
set local role authenticated;
select pg_temp.act_as('iadmin');
select is(public.import_societies(md5('importu')::uuid, $$[
  {"id": "101", "name": "Chess Club", "short_name": "Chess", "tagline": "Checkmate!", "interests": ["Gaming"]},
  {"id": "102", "name": "Drama Society", "short_name": "Drama"}
]$$), '{"created": 0, "updated": 2, "tags_added": 0}'::jsonb, 'importing again updates instead of duplicating');
select is((select name || ', ' || tagline from public.societies where id = md5('handmade')::uuid), 'Chess Club, Our own words',
  'the name is refreshed but the committee''s tagline stays');
select is((select count(*)::int from public.society_tags where society_id = md5('handmade')::uuid), 2, 'tags are never removed');
select is((select count(*)::int from public.societies where source = 'importu' and source_id = '103'), 1, 'a society missing from the file stays');
select is((select join_url from public.societies where source = 'importu' and source_id = '102'), null, 'a link removed in the file is removed');
reset role;
select results_eq($$select action from public.audit_log where university_id = md5('importu')::uuid and action in ('societies.imported', 'society.created', 'society.renamed') order by id$$,
  array['society.created', 'society.created', 'society.created', 'societies.imported', 'society.renamed', 'societies.imported'],
  'imports are in the audit log, with the societies they create and rename');
set local role authenticated;
select pg_temp.act_as('iadmin');
select throws_ok($$select public.import_societies(md5('importu')::uuid, (select jsonb_agg(jsonb_build_object('id', g, 'name', 'Society ' || g)) from generate_series(1, 501) g))$$,
  'P0001', 'Import at most 500 societies at a time.', 'at most 500 at a time');

select * from finish();
rollback;
