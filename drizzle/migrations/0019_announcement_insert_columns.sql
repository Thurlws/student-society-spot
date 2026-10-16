-- 0015 limited announcement edits to the wording and the pin, but a new announcement could
-- still set its own created_at or edited_at, so a committee could date a post in the future
-- and keep it above every other one.
revoke insert on public.announcements from anon, authenticated;
grant insert (society_id, author_id, title, body, pinned) on public.announcements to authenticated;
