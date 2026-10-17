begin;
create extension if not exists pgtap with schema extensions;
select plan(7);

-- Microsoft sign-in (0040): an identity from Microsoft is accepted only from the tenant that owns
-- the address's domain. TU Dublin's domains have theirs; msnone.test is a university domain
-- without one.
insert into public.universities (id, slug, name, short_name) values (md5('msnone')::uuid, 'msnone', 'No Microsoft University', 'NoMS');
insert into public.university_domains (domain, university_id) values ('msnone.test', md5('msnone')::uuid);
insert into auth.users (id, email, aud, role) values
  (md5('ms student')::uuid, 'ms.student@mytudublin.ie', 'authenticated', 'authenticated'),
  (md5('ms second')::uuid, 'ms.second@mytudublin.ie', 'authenticated', 'authenticated'),
  (md5('ms elsewhere')::uuid, 'ms.student@msnone.test', 'authenticated', 'authenticated');

-- A Microsoft identity for _user, issued by _tenant, saying its address is _email.
create function pg_temp.microsoft(_user text, _tenant text, _email text) returns void language sql as $$
  insert into auth.identities (provider_id, user_id, provider, identity_data)
  values (md5(_user || _tenant), md5(_user)::uuid, 'azure', jsonb_build_object(
    'iss', 'https://login.microsoftonline.com/' || _tenant || '/v2.0', 'sub', md5(_user || _tenant), 'email', _email))
$$;

select lives_ok($$select pg_temp.microsoft('ms student', '766317cb-e948-4e5f-8cec-dabc8e2fd5da', 'ms.student@mytudublin.ie')$$,
  'a TU Dublin account from TU Dublin''s own tenant signs in');
select throws_ok($$select pg_temp.microsoft('ms student', '0b0b0b0b-1111-4222-8333-444444444444', 'ms.student@mytudublin.ie')$$,
  'P0001', 'Use your university email: Microsoft sign-in only accepts your university''s own Microsoft accounts.',
  'another organisation claiming a TU Dublin address is refused');
select throws_ok($$select pg_temp.microsoft('ms student', '9188040d-6c67-4c5b-b112-36a304b66dad', 'ms.student@mytudublin.ie')$$,
  'P0001', null, 'a personal Microsoft account is refused');
select throws_ok($$select pg_temp.microsoft('ms elsewhere', '766317cb-e948-4e5f-8cec-dabc8e2fd5da', 'ms.student@msnone.test')$$,
  'P0001', null, 'a domain without a tenant doesn''t take Microsoft sign-in');
select throws_ok($$update auth.identities set identity_data = identity_data || '{"iss": "https://login.microsoftonline.com/0b0b0b0b-1111-4222-8333-444444444444/v2.0"}'
  where user_id = md5('ms student')::uuid and provider = 'azure'$$,
  'P0001', null, 'a returning sign-in from another tenant is refused');
select lives_ok($$insert into auth.identities (provider_id, user_id, provider, identity_data)
  values (md5('ms elsewhere')::text, md5('ms elsewhere')::uuid, 'email', '{"sub": "x", "email": "ms.student@msnone.test"}')$$,
  'email sign-in is untouched');

update public.university_domains set microsoft_tenant_id = null where domain = 'mytudublin.ie';
select throws_ok($$select pg_temp.microsoft('ms second', '766317cb-e948-4e5f-8cec-dabc8e2fd5da', 'ms.second@mytudublin.ie')$$,
  'P0001', null, 'turning it off for a domain stops new Microsoft sign-ins');

select * from finish();
rollback;
