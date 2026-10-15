-- Deleting an account deletes its profile, but these 13 foreign keys had no ON DELETE rule,
-- so Postgres refused while anything still pointed at the person. Their own content goes
-- with them (messages, support requests, guest links they made); society records they were
-- only linked to stay and lose the name.
alter table public.messages drop constraint messages_author_id_fkey,
  add constraint messages_author_id_fkey foreign key (author_id) references public.profiles(id) on delete cascade;
alter table public.support_requests drop constraint support_requests_submitted_by_fkey,
  add constraint support_requests_submitted_by_fkey foreign key (submitted_by) references public.profiles(id) on delete cascade;
alter table public.call_invites drop constraint call_invites_created_by_fkey,
  add constraint call_invites_created_by_fkey foreign key (created_by) references public.profiles(id) on delete cascade;

alter table public.announcements drop constraint announcements_author_id_fkey,
  add constraint announcements_author_id_fkey foreign key (author_id) references public.profiles(id) on delete set null;
alter table public.call_recaps drop constraint call_recaps_created_by_fkey,
  add constraint call_recaps_created_by_fkey foreign key (created_by) references public.profiles(id) on delete set null;
alter table public.call_rooms drop constraint call_rooms_created_by_fkey,
  add constraint call_rooms_created_by_fkey foreign key (created_by) references public.profiles(id) on delete set null;
alter table public.call_rooms drop constraint call_rooms_host_id_fkey,
  add constraint call_rooms_host_id_fkey foreign key (host_id) references public.profiles(id) on delete set null;
alter table public.collaboration_proposals drop constraint collaboration_proposals_created_by_fkey,
  add constraint collaboration_proposals_created_by_fkey foreign key (created_by) references public.profiles(id) on delete set null;
alter table public.events drop constraint events_created_by_fkey,
  add constraint events_created_by_fkey foreign key (created_by) references public.profiles(id) on delete set null;
alter table public.role_invites drop constraint role_invites_invited_by_fkey,
  add constraint role_invites_invited_by_fkey foreign key (invited_by) references public.profiles(id) on delete set null;
alter table public.society_memberships drop constraint society_memberships_decided_by_fkey,
  add constraint society_memberships_decided_by_fkey foreign key (decided_by) references public.profiles(id) on delete set null;
alter table public.support_request_activity drop constraint support_request_activity_actor_id_fkey,
  add constraint support_request_activity_actor_id_fkey foreign key (actor_id) references public.profiles(id) on delete set null;
alter table public.support_requests drop constraint support_requests_assigned_to_fkey,
  add constraint support_requests_assigned_to_fkey foreign key (assigned_to) references public.profiles(id) on delete set null;
