-- SocConnect: database updates 0034 to 0036 (committees manage channels, demo membership fees,
-- calendar links). Generated 2026-10-17 from drizzle/migrations (unchanged). Lovable does not
-- apply migration files that arrive from GitHub, so paste ALL of this into Lovable: More, then
-- Cloud, then SQL editor, click Run and confirm. One transaction: it all goes in, or nothing
-- changes.

begin;

do $check$
begin
  if to_regprocedure('public.create_channel(uuid, text, text, boolean)') is not null then
    raise exception 'These updates are already in this database. Nothing was changed.';
  end if;
  if to_regprocedure('public.nightly_job_runs()') is null then
    raise exception 'This database is missing earlier updates (0033: run dev/supabase/apply-0033.sql first). Nothing was changed.';
  end if;
end $check$;

-- ===== 0034_channel_management =====

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

-- ===== 0035_membership_fees =====

-- Membership fees, before there's a payment provider. A committee sets its society's fee; a
-- member pays it either through a demo checkout, which takes no money and asks for no card or
-- bank details, or for real wherever the society takes payments (for TU Dublin societies,
-- mystudentlife), after which the committee marks them paid. Committees see who has paid and
-- how, so a demo payment is never mistaken for money received.
--
-- Payment status sits on the membership row, so it's read like the membership itself: by the
-- member and by the society's committee (the existing read policy). It goes when the
-- membership goes. Like membership decisions, it stays out of the audit log.

alter table public.societies add column membership_fee_cents integer
  check (membership_fee_cents is null or membership_fee_cents between 1 and 50000);

alter table public.society_memberships
  add column fee_paid_at timestamptz,
  add column fee_paid_cents integer,
  -- 'demo': the demo checkout, no money taken. 'committee': the committee marked it paid.
  add column fee_paid_how text check (fee_paid_how in ('demo', 'committee')),
  add constraint society_memberships_fee_paid_complete check ((fee_paid_at is null) = (fee_paid_how is null));

create function public.pay_membership_fee_demo(_society_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare s public.societies; m public.society_memberships;
begin
  select * into s from public.societies where id = _society_id;
  select * into m from public.society_memberships
    where society_id = _society_id and user_id = auth.uid() and status in ('member', 'pending') for update;
  if not found or private.is_suspended(auth.uid()) then
    raise exception 'Join % before paying its membership fee.', coalesce(s.short_name, 'the society');
  end if;
  if s.membership_fee_cents is null then raise exception '% has no membership fee.', s.short_name; end if;
  if m.fee_paid_at is not null then raise exception 'You''ve already paid for %.', s.short_name; end if;
  update public.society_memberships
    set fee_paid_at = now(), fee_paid_cents = s.membership_fee_cents, fee_paid_how = 'demo'
    where id = m.id;
end $$;
revoke execute on function public.pay_membership_fee_demo(uuid) from public, anon;

-- For payments made outside SocConnect, and for undoing a mistake.
create function public.set_membership_fee_paid(_membership_id uuid, _paid boolean)
returns void language plpgsql security definer set search_path = public as $$
declare m public.society_memberships;
begin
  select * into m from public.society_memberships where id = _membership_id for update;
  if not found or not private.is_society_committee(m.society_id, auth.uid()) then
    raise exception 'Only the society''s committee can mark fees as paid.';
  end if;
  if _paid and m.fee_paid_at is null then
    update public.society_memberships
      set fee_paid_at = now(), fee_paid_how = 'committee',
          fee_paid_cents = (select membership_fee_cents from public.societies where id = m.society_id)
      where id = m.id;
  elsif not _paid then
    update public.society_memberships set fee_paid_at = null, fee_paid_cents = null, fee_paid_how = null
      where id = m.id;
  end if;
end $$;
revoke execute on function public.set_membership_fee_paid(uuid, boolean) from public, anon;

-- ===== 0036_calendar_feeds =====

-- A personal calendar link: Google Calendar, Apple Calendar or Outlook subscribe to it and keep
-- the events you've registered for up to date, cancellations included.
--
-- Calendar apps fetch the link without signing in, so the link itself is the key. Only a hash
-- of it is stored: it's shown once when it's made, and making a new one turns the old one off.
-- Anyone with the link sees which events you registered for, so it can be turned off at any
-- time, and it stops working while an account is suspended. It goes with the account.

create table public.calendar_feeds (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  token_hash text not null unique,
  created_at timestamptz not null default now()
);
alter table public.calendar_feeds enable row level security;
revoke all on public.calendar_feeds from anon, authenticated;
-- People see whether they have a link and since when; never the hash.
grant select (user_id, created_at) on public.calendar_feeds to authenticated;
grant all on public.calendar_feeds to service_role;
create policy "Read own calendar link" on public.calendar_feeds for select to authenticated
  using (user_id = auth.uid() and not private.is_suspended(auth.uid()));

create function private.calendar_token_hash(_token text)
returns text language sql immutable set search_path = public as $$
  select encode(sha256(convert_to(_token, 'UTF8')), 'hex')
$$;
revoke execute on function private.calendar_token_hash(text) from public, anon, authenticated;

-- Makes a new link and returns it, once. The old one stops working.
create function public.create_calendar_feed()
returns text language plpgsql security definer set search_path = public as $$
declare token text := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
begin
  if auth.uid() is null or private.is_suspended(auth.uid()) then
    raise exception 'You can''t make a calendar link right now.';
  end if;
  insert into public.calendar_feeds (user_id, token_hash) values (auth.uid(), private.calendar_token_hash(token))
    on conflict (user_id) do update set token_hash = excluded.token_hash, created_at = now();
  return token;
end $$;
revoke execute on function public.create_calendar_feed() from public, anon;

create function public.delete_calendar_feed()
returns void language sql security definer set search_path = public as $$
  delete from public.calendar_feeds where user_id = auth.uid()
$$;
revoke execute on function public.delete_calendar_feed() from public, anon;

-- For the server's /api/calendar route only (service role): the events behind a link. Nothing
-- for an unknown link or a suspended account. Cancelled events stay, so calendars remove them.
create function public.calendar_feed_events(_token text)
returns table(id uuid, title text, description text, starts_at timestamptz, ends_at timestamptz,
  venue text, cancelled boolean, society text)
language sql stable security definer set search_path = public as $$
  select e.id, e.title, e.description, e.starts_at, e.ends_at, e.venue, e.cancelled_at is not null, s.name
  from public.calendar_feeds f
  join public.event_registrations r on r.user_id = f.user_id
  join public.events e on e.id = r.event_id
  join public.societies s on s.id = e.society_id and s.status = 'active'
  where f.token_hash = private.calendar_token_hash(_token)
    and not private.is_suspended(f.user_id)
    and e.starts_at > now() - interval '90 days'
  order by e.starts_at
$$;
revoke execute on function public.calendar_feed_events(text) from public, anon, authenticated;
grant execute on function public.calendar_feed_events(text) to service_role;

-- ===== Bookkeeping =====
-- If Drizzle (Lovable's migration runner) keeps its record here, note these updates too.
do $record$
begin
  if to_regclass('drizzle.__drizzle_migrations') is not null then
    insert into drizzle.__drizzle_migrations (hash, created_at) values
      ('033a9c3ff5097d4cf11d1ee1f07e9420fffa81cc38622d2d333f66d4116cb2e7', 1792120551276),
      ('4e383e84d119d06ff178db500612146a13517288921bfe0fe3357a5deb04b9dd', 1792120611276),
      ('c14794fc74571a4968594b5b9bcea69dbd2ffb2c6b38c63cce253970dc969816', 1792120671276);
  end if;
end $record$;

commit;
