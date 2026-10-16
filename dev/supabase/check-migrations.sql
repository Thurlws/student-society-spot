-- Which of SocConnect's migrations a database has. Read-only: paste it into Lovable Cloud's
-- SQL editor (or psql) and run it. Each migration from 0007 on is recognised by something it
-- created or changed. Migrations apply in order, so everything up to the last "yes" should
-- say yes; a "no" before that means a migration was skipped.
select m.migration, case when m.applied then 'yes' else 'NO' end as applied
from (values
  ('0007 admins by invite only', coalesce(pg_get_functiondef(to_regprocedure('public.handle_new_user()')) not like '%tudublin.ie%', false)),
  ('0008 private permission helpers', to_regprocedure('private.has_role(uuid, public.app_role)') is not null),
  ('0009 one AI quota function', coalesce(pg_get_functiondef(to_regprocedure('public.reserve_society_ai(uuid, text)')) like '%transcribe%', false)),
  ('0010 per-user indexes', to_regclass('public.society_memberships_user_id_idx') is not null),
  ('0011 domain check on email change', coalesce(pg_get_functiondef(to_regprocedure('public.enforce_email_domain()')) like '%email_change%', false)),
  ('0012 deletable accounts', exists (select 1 from pg_constraint where conname = 'messages_author_id_fkey' and confdeltype = 'c')),
  ('0013 share_recap host check', coalesce(pg_get_functiondef(to_regprocedure('public.share_recap(uuid)')) like '%coalesce(rm.host_id = auth.uid(), false)%', false)),
  ('0014 edit and cancel events', exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'events' and column_name = 'cancelled_at')),
  ('0015 announcement edits', exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'announcements' and column_name = 'edited_at')),
  ('0016 message moderation', to_regclass('public.message_reports') is not null),
  ('0017 reports about committee members', coalesce(pg_get_functiondef(to_regprocedure('public.dismiss_message_reports(uuid)')) like '%Reports about your own message%', false)),
  ('0018 events only through functions', not exists (select 1 from pg_policies where tablename = 'events' and policyname = 'Committee delete events')),
  ('0019 announcement insert columns', not has_column_privilege('authenticated', 'public.announcements', 'created_at', 'INSERT')),
  ('0020 recap host still member', coalesce(pg_get_functiondef(to_regprocedure('public.share_recap(uuid)')) like '%false) and private.is_society_member%', false)),
  ('0021 universities', to_regclass('public.universities') is not null),
  ('0022 university rules', to_regprocedure('private.can_manage_university(uuid, uuid)') is not null),
  ('0023 yearly re-verification', exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'university_members' and column_name = 'verified_at')),
  ('0024 audit log', to_regclass('public.audit_log') is not null),
  ('0025 suspension', exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'university_members' and column_name = 'suspended_at')),
  ('0026 retention', to_regprocedure('public.purge_expired_data()') is not null),
  ('0027 sign-in health', to_regprocedure('public.sign_in_health()') is not null),
  ('0028 society import', to_regprocedure('public.import_societies(uuid, jsonb)') is not null),
  ('0029 society identity', coalesce(pg_get_functiondef(to_regprocedure('public.guard_society_update()')) like '%name, category, logo or banner%', false)),
  ('0030 saved proposals visible', exists (select 1 from pg_policies where tablename = 'saved_proposals' and policyname = 'Save own' and with_check like '%collaboration_proposals%')),
  ('0031 display names', to_regprocedure('private.check_display_name()') is not null)
) as m(migration, applied)
order by m.migration;
