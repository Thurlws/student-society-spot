-- SocConnect: database updates 0038 to 0040 (the database dates messages, the newest messages of
-- each channel, Microsoft sign-in only from the university's own organisation). Generated
-- 2026-10-17 from drizzle/migrations (unchanged). Lovable does not apply migration files that
-- arrive from GitHub, so paste ALL of this into Lovable: More, then Cloud, then SQL editor, click
-- Run and confirm. One transaction: it all goes in, or nothing changes.

begin;

do $check$
begin
  if to_regprocedure('public.check_microsoft_tenant()') is not null then
    raise exception 'These updates are already in this database. Nothing was changed.';
  end if;
  if to_regprocedure('public.remove_member(uuid, text)') is null then
    raise exception 'This database is missing earlier updates (0037: run dev/supabase/apply-0037.sql first). Nothing was changed.';
  end if;
end $check$;

-- ===== 0038_message_insert_columns =====

-- Members post by inserting into messages, and Supabase lets signed-in users write every column,
-- so a message could set its own created_at: one dated 2099 stayed the newest in its channel for
-- good. As for announcements (0019), only these columns can be written; the date and id are the
-- database's.
revoke insert on public.messages from anon, authenticated;
grant insert (channel_id, author_id, body) on public.messages to authenticated;

-- ===== 0039_recent_messages =====

-- The newest messages of each channel, and the newest announcements of each society. The app
-- loaded the newest 500 messages and 200 announcements across everything you can see, so a quiet
-- channel or society looked empty as soon as a busy one had more.
--
-- Invoker's rights: the channels, messages, societies and announcements policies still decide
-- what comes back, exactly as when the app reads the tables.

create function public.recent_messages(_per_channel integer default 100)
returns setof public.messages language sql stable set search_path = public as $$
  select m.* from public.channels c
  cross join lateral (
    select * from public.messages x where x.channel_id = c.id
    order by x.created_at desc
    limit least(greatest(coalesce(_per_channel, 100), 1), 200)
  ) m
$$;
revoke execute on function public.recent_messages(integer) from public, anon;

-- Pinned ones first, so a society's pinned post is never the one left out. Platform admins can
-- read every university's societies; the app asks for its own.
create function public.recent_announcements(_university_id uuid default null, _per_society integer default 50)
returns setof public.announcements language sql stable set search_path = public as $$
  select a.* from public.societies s
  cross join lateral (
    select * from public.announcements x where x.society_id = s.id
    order by x.pinned desc, x.created_at desc
    limit least(greatest(coalesce(_per_society, 50), 1), 200)
  ) a
  where s.status = 'active' and (_university_id is null or s.university_id = _university_id)
$$;
revoke execute on function public.recent_announcements(uuid, integer) from public, anon;

-- ===== 0040_microsoft_tenants =====

-- "Sign in with Microsoft" goes through Lovable's broker, which accepts any Microsoft account from
-- any organisation (its docs: "the tenant cannot be restricted") and passes on the email address
-- that organisation reports. Whoever runs a Microsoft organisation can make an account report a
-- university address, so the address alone proves nothing: signing up with it would make them a
-- member of that university and hand them any invites waiting for it, admin seats included.
--
-- A domain can be verified in only one Microsoft organisation (tenant): its owner's. So each
-- university email domain records the tenant that owns it, and a Microsoft identity is accepted
-- only from that tenant. A domain without one doesn't take Microsoft sign-in; its people use the
-- email link. Platform admins turn it on per domain in /admin (the server asks Microsoft which
-- tenant owns the domain).

alter table public.university_domains add column microsoft_tenant_id uuid;

grant update (microsoft_tenant_id) on public.university_domains to authenticated;
create policy "Platform admins set Microsoft tenants" on public.university_domains for update to authenticated
  using (private.has_role(auth.uid(), 'platform_admin')) with check (private.has_role(auth.uid(), 'platform_admin'));

-- TU Dublin's two domains belong to one tenant (login.microsoftonline.com/<domain>/v2.0/.well-known/openid-configuration).
update public.university_domains set microsoft_tenant_id = '766317cb-e948-4e5f-8cec-dabc8e2fd5da'
  where domain in ('tudublin.ie', 'mytudublin.ie');

-- In public, like the other triggers on auth tables (enforce_email_domain), and callable by nobody.
-- Runs inside the sign-in itself (Supabase Auth saves the user and the identity together), so a
-- refusal leaves no account, no university membership and no claimed invite behind. Identities
-- that aren't Microsoft's pass untouched.
create function public.check_microsoft_tenant()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  iss text := lower(coalesce(new.identity_data->>'iss', ''));
  email text := lower(coalesce(new.identity_data->>'email', (select u.email from auth.users u where u.id = new.user_id), ''));
  expected uuid;
begin
  if new.provider <> 'azure' and iss !~ '^https://(login\.microsoftonline\.com|sts\.windows\.net)/' then
    return new;
  end if;
  select d.microsoft_tenant_id into expected from public.university_domains d
    where d.domain = split_part(email, '@', 2);
  if expected is null
     or substring(iss from '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}') is distinct from expected::text then
    raise exception 'Use your university email: Microsoft sign-in only accepts your university''s own Microsoft accounts.';
  end if;
  return new;
end $$;
revoke execute on function public.check_microsoft_tenant() from public, anon, authenticated;
create trigger check_microsoft_tenant before insert or update of identity_data, provider on auth.identities
  for each row execute function public.check_microsoft_tenant();

-- Turning Microsoft sign-in on or off for a domain is recorded, like adding or removing it.
create or replace function private.audit_university_domains()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    perform private.audit('domain.added', new.university_id, null, null, jsonb_build_object('domain', new.domain));
  elsif tg_op = 'UPDATE' then
    perform private.audit('domain.microsoft_sign_in', new.university_id, null, null,
      jsonb_build_object('domain', new.domain, 'on', new.microsoft_tenant_id is not null));
  elsif exists (select 1 from public.universities where id = old.university_id) then
    perform private.audit('domain.removed', old.university_id, null, null, jsonb_build_object('domain', old.domain));
  end if;
  return null;
end $$;
drop trigger audit_university_domains on public.university_domains;
create trigger audit_university_domains after insert or delete or update of microsoft_tenant_id on public.university_domains
  for each row execute function private.audit_university_domains();

-- ===== Bookkeeping =====
-- If Drizzle (Lovable's migration runner) keeps its record here, note these updates too.
do $record$
begin
  if to_regclass('drizzle.__drizzle_migrations') is not null then
    insert into drizzle.__drizzle_migrations (hash, created_at) values
      ('2e5373b2a35fafe94825685ead335b078a5f7017b073c03997cd87bb37157f1e', 1792269000000),
      ('d4c9465017416a3b052fb29834f4f80b004e3d86d5d5ab1f430898c621f47534', 1792269060000),
      ('13e51f81093ba671ea4c1c553bc3f503047b921c8baab87f70b1ff06e3234025', 1792269120000);
  end if;
end $record$;

commit;
