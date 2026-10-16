-- A record of privileged actions: who gave or took away admin rights and committee seats,
-- who invited whom, who created, renamed, moved or archived a society or a university,
-- which domains were added or removed, which messages a committee or admin removed, which
-- reports were dismissed, which events were cancelled and which accounts were deleted.
-- Before, none of this was kept, so nobody could answer "who made this person an admin?".
--
-- Triggers fill it, so every path counts: the app, the API, invites claimed at sign-up and
-- hand-written SQL. Nobody can change or delete an entry through the API. Platform admins
-- read every entry; university admins read their own university's.
--
-- Left out on purpose: membership decisions. Being approved into the LGBTQ+, Islamic or
-- Christian Union society reveals special-category data (GDPR Art. 9), and university admins
-- can't see society members today. A removed message's author is left out for the same
-- reason: committees and admins act on the content, and the entry shouldn't tell admins who
-- belongs to which society.
--
-- Entries have no foreign keys: they outlive the people, societies and universities they
-- mention. When an account or a society is deleted, the rows that go with it (committee
-- seats, domains) aren't logged one by one; the deletion itself is.
create table public.audit_log (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  actor_id uuid,
  -- What the actor was when they acted: platform_admin, university_admin, committee,
  -- member, or system (sign-up, imports, nightly jobs and the service role).
  actor_role text not null,
  action text not null,
  -- Whose admins can read it. Null: platform admins only (platform admin grants, for example).
  university_id uuid,
  society_id uuid,
  -- The person the action was about, if any.
  subject_id uuid,
  details jsonb not null default '{}'
);
create index audit_log_university_idx on public.audit_log (university_id, at desc);
create index audit_log_at_idx on public.audit_log (at);
alter table public.audit_log enable row level security;
revoke all on public.audit_log from anon, authenticated;
revoke insert, update, delete, truncate on public.audit_log from service_role;
grant select on public.audit_log to authenticated, service_role;
create policy "Admins read the audit log" on public.audit_log for select to authenticated
  using (private.can_manage_university(university_id, auth.uid()));

create function private.audit(_action text, _university_id uuid, _society_id uuid, _subject_id uuid, _details jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare _uid uuid := auth.uid();
begin
  insert into public.audit_log (actor_id, actor_role, action, university_id, society_id, subject_id, details)
  values (_uid,
    case
      when _uid is null then 'system'
      when exists (select 1 from public.user_roles where user_id = _uid and role = 'platform_admin') then 'platform_admin'
      when exists (select 1 from public.university_admins where user_id = _uid and university_id = _university_id) then 'university_admin'
      when exists (select 1 from public.society_roles where user_id = _uid and society_id = _society_id) then 'committee'
      else 'member'
    end,
    _action, _university_id, _society_id, _subject_id, coalesce(_details, '{}'));
end $$;

-- ===== Platform and university admins =====
create function private.audit_user_roles()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    perform private.audit('platform_admin.added', null, null, new.user_id, '{}');
  elsif exists (select 1 from auth.users where id = old.user_id) then
    perform private.audit('platform_admin.removed', null, null, old.user_id, '{}');
  end if;
  return null;
end $$;
create trigger audit_user_roles after insert or delete on public.user_roles
  for each row execute function private.audit_user_roles();

create function private.audit_university_admins()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    perform private.audit('university_admin.added', new.university_id, null, new.user_id, '{}');
  elsif exists (select 1 from public.profiles where id = old.user_id)
    and exists (select 1 from public.universities where id = old.university_id) then
    perform private.audit('university_admin.removed', old.university_id, null, old.user_id, '{}');
  end if;
  return null;
end $$;
create trigger audit_university_admins after insert or delete on public.university_admins
  for each row execute function private.audit_university_admins();

-- ===== Committee seats and invites =====
create function private.audit_society_roles()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    perform private.audit('committee.added', private.society_university(new.society_id), new.society_id, new.user_id,
      jsonb_build_object('position', new.position, 'role', new.role));
  elsif tg_op = 'UPDATE' then
    if new.position is distinct from old.position or new.role is distinct from old.role then
      perform private.audit('committee.changed', private.society_university(new.society_id), new.society_id, new.user_id,
        jsonb_build_object('from', jsonb_build_object('position', old.position, 'role', old.role),
                           'to', jsonb_build_object('position', new.position, 'role', new.role)));
    end if;
  elsif exists (select 1 from public.profiles where id = old.user_id)
    and exists (select 1 from public.societies where id = old.society_id) then
    perform private.audit('committee.removed', private.society_university(old.society_id), old.society_id, old.user_id,
      jsonb_build_object('position', old.position));
  end if;
  return null;
end $$;
create trigger audit_society_roles after insert or update or delete on public.society_roles
  for each row execute function private.audit_society_roles();

-- Claimed invites aren't logged: the seat or role they grant is.
create function private.audit_role_invites()
returns trigger language plpgsql security definer set search_path = public as $$
declare r public.role_invites := case when tg_op = 'INSERT' then new else old end;
begin
  if tg_op = 'DELETE' and (r.claimed_at is not null
      or (r.society_id is not null and not exists (select 1 from public.societies where id = r.society_id))
      or (r.university_id is not null and not exists (select 1 from public.universities where id = r.university_id))) then
    return null;
  end if;
  perform private.audit(case when tg_op = 'INSERT' then 'invite.created' else 'invite.cancelled' end,
    coalesce(r.university_id, private.society_university(r.society_id)), r.society_id, null,
    jsonb_build_object('email', r.email, 'role', r.role, 'position', r.position));
  return null;
end $$;
create trigger audit_role_invites after insert or delete on public.role_invites
  for each row execute function private.audit_role_invites();

-- ===== Societies =====
-- Committee edits to the tagline, description and meeting times aren't privileged and
-- aren't logged. Renames are (audit finding 17: committees can rename their society).
create function private.audit_societies()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    perform private.audit('society.created', new.university_id, new.id, null,
      jsonb_build_object('name', new.name, 'slug', new.slug));
  elsif tg_op = 'DELETE' then
    perform private.audit('society.deleted', old.university_id, old.id, null,
      jsonb_build_object('name', old.name, 'slug', old.slug));
  else
    if new.status is distinct from old.status then
      perform private.audit(case when new.status = 'archived' then 'society.archived' else 'society.restored' end,
        new.university_id, new.id, null, jsonb_build_object('name', new.name));
    end if;
    if (new.name, new.short_name, new.slug) is distinct from (old.name, old.short_name, old.slug) then
      perform private.audit('society.renamed', new.university_id, new.id, null,
        jsonb_build_object('from', jsonb_build_object('name', old.name, 'short_name', old.short_name, 'slug', old.slug),
                           'to', jsonb_build_object('name', new.name, 'short_name', new.short_name, 'slug', new.slug)));
    end if;
    if (new.join_url, new.official_url) is distinct from (old.join_url, old.official_url) then
      perform private.audit('society.links_changed', new.university_id, new.id, null,
        jsonb_build_object('from', jsonb_build_object('join_url', old.join_url, 'official_url', old.official_url),
                           'to', jsonb_build_object('join_url', new.join_url, 'official_url', new.official_url)));
    end if;
    if new.university_id is distinct from old.university_id then
      perform private.audit('society.moved', new.university_id, new.id, null,
        jsonb_build_object('name', new.name, 'from', old.university_id, 'to', new.university_id));
    end if;
  end if;
  return null;
end $$;
create trigger audit_societies after insert or update or delete on public.societies
  for each row execute function private.audit_societies();

-- ===== Universities and their domains =====
create function private.audit_universities()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    perform private.audit('university.created', new.id, null, null, jsonb_build_object('name', new.name, 'slug', new.slug));
  elsif tg_op = 'DELETE' then
    perform private.audit('university.deleted', null, null, null, jsonb_build_object('id', old.id, 'name', old.name, 'slug', old.slug));
  elsif (new.name, new.short_name, new.slug) is distinct from (old.name, old.short_name, old.slug) then
    perform private.audit('university.renamed', new.id, null, null,
      jsonb_build_object('from', jsonb_build_object('name', old.name, 'short_name', old.short_name, 'slug', old.slug),
                         'to', jsonb_build_object('name', new.name, 'short_name', new.short_name, 'slug', new.slug)));
  end if;
  return null;
end $$;
create trigger audit_universities after insert or update or delete on public.universities
  for each row execute function private.audit_universities();

create function private.audit_university_domains()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    perform private.audit('domain.added', new.university_id, null, null, jsonb_build_object('domain', new.domain));
  elsif exists (select 1 from public.universities where id = old.university_id) then
    perform private.audit('domain.removed', old.university_id, null, null, jsonb_build_object('domain', old.domain));
  end if;
  return null;
end $$;
create trigger audit_university_domains after insert or delete on public.university_domains
  for each row execute function private.audit_university_domains();

-- ===== Moderation =====
-- Someone other than the author removed a message. Before delete, so its reports are still there.
create function private.audit_messages()
returns trigger language plpgsql security definer set search_path = public as $$
declare c public.channels;
begin
  if auth.uid() is not null and old.author_id is distinct from auth.uid() then
    select * into c from public.channels where id = old.channel_id;
    if found then
      perform private.audit('message.removed', private.society_university(c.society_id), c.society_id, null,
        jsonb_build_object('channel', c.name,
          'reported', exists (select 1 from public.message_reports where message_id = old.id)));
    end if;
  end if;
  return old;
end $$;
create trigger audit_messages before delete on public.messages
  for each row execute function private.audit_messages();

-- One entry per message, however many reports were closed with it.
create function private.audit_message_reports()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform private.audit('reports.dismissed', private.society_university(n.society_id), n.society_id, null,
      jsonb_build_object('reports', count(*)))
    from new_rows n join old_rows o on o.id = n.id
    where o.dismissed_at is null and n.dismissed_at is not null
    group by n.message_id, n.society_id;
  return null;
end $$;
create trigger audit_message_reports after update on public.message_reports
  referencing old table as old_rows new table as new_rows
  for each statement execute function private.audit_message_reports();

create function private.audit_events()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.cancelled_at is null and new.cancelled_at is not null then
    perform private.audit('event.cancelled', private.society_university(new.society_id), new.society_id, null,
      jsonb_build_object('event_id', new.id, 'title', new.title, 'reason', new.cancel_reason));
  end if;
  return null;
end $$;
create trigger audit_events after update of cancelled_at on public.events
  for each row execute function private.audit_events();

-- ===== Accounts =====
-- Before delete, while the account's university is still recorded.
create function private.audit_profiles()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform private.audit('account.deleted', private.user_university(old.id), null, old.id, '{}');
  return old;
end $$;
create trigger audit_profiles before delete on public.profiles
  for each row execute function private.audit_profiles();

-- Only the triggers above run these.
revoke execute on function private.audit(text, uuid, uuid, uuid, jsonb), private.audit_user_roles(),
  private.audit_university_admins(), private.audit_society_roles(), private.audit_role_invites(),
  private.audit_societies(), private.audit_universities(), private.audit_university_domains(),
  private.audit_messages(), private.audit_message_reports(), private.audit_events(), private.audit_profiles()
  from public, anon, authenticated;
