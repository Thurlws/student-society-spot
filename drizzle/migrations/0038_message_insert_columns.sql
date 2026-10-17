-- Members post by inserting into messages, and Supabase lets signed-in users write every column,
-- so a message could set its own created_at: one dated 2099 stayed the newest in its channel for
-- good. As for announcements (0019), only these columns can be written; the date and id are the
-- database's.
revoke insert on public.messages from anon, authenticated;
grant insert (channel_id, author_id, body) on public.messages to authenticated;
