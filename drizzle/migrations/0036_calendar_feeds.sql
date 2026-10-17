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
