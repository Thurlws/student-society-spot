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
