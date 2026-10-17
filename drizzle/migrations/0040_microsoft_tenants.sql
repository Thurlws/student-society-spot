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
