-- Committees can now edit and delete announcements in the app (the policies already allowed
-- both). An edit may change only the wording and the pin: the update policy covered every
-- column, so a committee could reattribute an announcement to someone else or backdate it.
-- Changed wording is marked, so readers know a post isn't what they first saw.
alter table public.announcements add column edited_at timestamptz;

revoke update on public.announcements from anon, authenticated;
grant update (title, body, pinned) on public.announcements to authenticated;

create or replace function public.mark_announcement_edited()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.title is distinct from old.title or new.body is distinct from old.body then
    new.edited_at := now();
  end if;
  return new;
end $$;
revoke execute on function public.mark_announcement_edited() from public, anon, authenticated;
create trigger announcements_mark_edited before update on public.announcements
  for each row execute function public.mark_announcement_edited();
