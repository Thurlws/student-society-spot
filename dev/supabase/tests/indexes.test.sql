begin;
create extension if not exists pgtap with schema extensions;
select plan(4);

select has_index('public', 'society_memberships', 'society_memberships_user_id_idx', array['user_id']);
select has_index('public', 'society_roles', 'society_roles_user_id_idx', array['user_id']);
select has_index('public', 'event_registrations', 'event_registrations_user_id_idx', array['user_id']);
select has_index('public', 'announcements', 'announcements_society_created_idx', array['society_id', 'created_at']);

select * from finish();
rollback;
