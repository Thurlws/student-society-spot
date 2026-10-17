-- Committees manage their society's discussion channels: add one, rename it or change its
-- description, make it committee-only (members read, only the committee posts), and delete it.
-- Before, every society had the same three channels and nobody could change them.
--
-- Changes go through functions, never direct writes, so the rules hold for every caller:
-- - names are lower case letters, numbers and dashes, up to 30, unique in the society;
-- - a society has at most 20 channels;
-- - #general can't be deleted, because call recaps are shared there (share_recap). Its address
--   (slug) never changes, even when it's renamed, for the same reason;
-- - deleting a channel deletes its messages, and their authors are told, like a removed message
--   (Digital Services Act, article 17; 0032). It's recorded in the audit log, without the authors.
-- Admins can't read society channels, so they don't manage them either.

alter table public.channels add column committee_only boolean not null default false;
alter table public.channels add column created_at timestamptz not null default now();

-- Committee-only channels refuse members' messages; the committee still posts.
drop policy "Members post messages" on public.messages;
create policy "Members post messages" on public.messages for insert to authenticated
  with check (author_id = auth.uid() and exists (
    select 1 from public.channels c where c.id = channel_id
      and private.is_society_member(c.society_id, auth.uid())
      and (not c.committee_only or private.is_society_committee(c.society_id, auth.uid()))));

-- "Kit & Lifts!" → "kit-lifts". Null when nothing usable is left.
create function private.channel_name(_name text)
returns text language sql immutable set search_path = public as $$
  select nullif(btrim(regexp_replace(regexp_replace(lower(coalesce(_name, '')), '[^a-z0-9]+', '-', 'g'), '-+', '-', 'g'), '-'), '')
$$;
revoke execute on function private.channel_name(text) from public, anon, authenticated;

create function public.create_channel(_society_id uuid, _name text, _description text default '', _committee_only boolean default false)
returns uuid language plpgsql security definer set search_path = public as $$
declare n text := private.channel_name(_name); d text := btrim(coalesce(_description, '')); new_id uuid;
begin
  if not private.is_society_committee(_society_id, auth.uid()) then
    raise exception 'Only the society''s committee can add channels.';
  end if;
  if not exists (select 1 from public.societies where id = _society_id and status = 'active') then
    raise exception 'This society is archived.';
  end if;
  if n is null then raise exception 'Give the channel a name with letters or numbers.'; end if;
  if char_length(n) > 30 then raise exception 'Keep the channel name to 30 characters.'; end if;
  if char_length(d) > 200 then raise exception 'Keep the description to 200 characters.'; end if;
  if (select count(*) from public.channels where society_id = _society_id) >= 20 then
    raise exception 'A society can have up to 20 channels.';
  end if;
  if exists (select 1 from public.channels where society_id = _society_id and (name = n or slug = n)) then
    raise exception 'There''s already a #% channel.', n;
  end if;
  insert into public.channels (society_id, slug, name, description, committee_only)
    values (_society_id, n, n, d, coalesce(_committee_only, false))
    returning id into new_id;
  return new_id;
end $$;
revoke execute on function public.create_channel(uuid, text, text, boolean) from public, anon;

create function public.update_channel(_channel_id uuid, _name text, _description text, _committee_only boolean)
returns void language plpgsql security definer set search_path = public as $$
declare c public.channels; n text := private.channel_name(_name); d text := btrim(coalesce(_description, ''));
begin
  select * into c from public.channels where id = _channel_id for update;
  if not found or not private.is_society_committee(c.society_id, auth.uid()) then
    raise exception 'Only the society''s committee can change channels.';
  end if;
  if n is null then raise exception 'Give the channel a name with letters or numbers.'; end if;
  if char_length(n) > 30 then raise exception 'Keep the channel name to 30 characters.'; end if;
  if char_length(d) > 200 then raise exception 'Keep the description to 200 characters.'; end if;
  if exists (select 1 from public.channels where society_id = c.society_id and id <> c.id and name = n) then
    raise exception 'There''s already a #% channel.', n;
  end if;
  update public.channels set name = n, description = d, committee_only = coalesce(_committee_only, false)
    where id = c.id;
end $$;
revoke execute on function public.update_channel(uuid, text, text, boolean) from public, anon;

create function public.delete_channel(_channel_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare c public.channels; s public.societies; authors uuid[]; n int;
begin
  select * into c from public.channels where id = _channel_id for update;
  if not found or not private.is_society_committee(c.society_id, auth.uid()) then
    raise exception 'Only the society''s committee can delete channels.';
  end if;
  if c.slug = 'general' then
    raise exception '#% can''t be deleted: call recaps are shared there.', c.name;
  end if;
  select * into s from public.societies where id = c.society_id;
  select count(*), coalesce(array_agg(distinct author_id) filter (where author_id is not null and author_id <> auth.uid()), '{}')
    into n, authors from public.messages where channel_id = c.id;
  -- Its messages go with it (on delete cascade). The per-message audit trigger finds no channel
  -- by then, so the deletion is recorded once, here.
  delete from public.channels where id = c.id;
  perform private.audit('channel.deleted', s.university_id, s.id, null,
    jsonb_build_object('channel', c.name, 'messages', n));
  -- 'requests' notices are always delivered, like other removals.
  perform public.notify_user(a, 'requests', 'A channel was deleted',
    'The ' || s.short_name || ' committee deleted the #' || c.name || ' channel, and your messages in it with it. '
      || 'If you think it was a mistake, send the committee a request from the society''s page.',
    jsonb_build_object('to', '/societies/$societyId', 'params', jsonb_build_object('societyId', s.slug)), null)
  from unnest(authors) a;
end $$;
revoke execute on function public.delete_channel(uuid) from public, anon;
