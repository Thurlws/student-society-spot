-- Lookups by user alone (home page, can_see_profile, recommendations) scanned whole tables:
-- the existing keys start with society_id or event_id. Announcements are read newest first per society.
create index if not exists society_memberships_user_id_idx on public.society_memberships (user_id);
create index if not exists society_roles_user_id_idx on public.society_roles (user_id);
create index if not exists event_registrations_user_id_idx on public.event_registrations (user_id);
create index if not exists announcements_society_created_idx on public.announcements (society_id, created_at desc);
