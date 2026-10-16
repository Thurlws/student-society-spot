-- Audit finding 17: a committee could rename its society, or change its logo and banner,
-- and present itself as, say, the Students' Union inside an official-looking directory. The
-- committee's own form only edits the tagline, description and meeting details, so this only
-- closes the API. A society's name, short name, category, logo and banner now change only
-- through its university's admins, a platform admin or an import (no signed-in user).
create or replace function public.guard_society_update()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and not private.has_role(auth.uid(), 'platform_admin') then
    if new.university_id is distinct from old.university_id then
      raise exception 'Only platform admins can move a society to another university.';
    end if;
    if not private.can_manage_university(old.university_id, auth.uid()) then
      if new.slug is distinct from old.slug or new.status is distinct from old.status then
        raise exception 'Only your university''s admins can change a society''s address or archive it.';
      end if;
      if new.name is distinct from old.name or new.short_name is distinct from old.short_name
         or new.category is distinct from old.category
         or new.logo_url is distinct from old.logo_url or new.banner_url is distinct from old.banner_url then
        raise exception 'Only your university''s admins can change a society''s name, category, logo or banner.';
      end if;
      if new.source is distinct from old.source or new.source_id is distinct from old.source_id
         or new.source_snapshot is distinct from old.source_snapshot or new.source_synced_at is distinct from old.source_synced_at
         or new.join_url is distinct from old.join_url or new.official_url is distinct from old.official_url then
        raise exception 'Official society links can only be changed by an import or an admin.';
      end if;
    end if;
  end if;
  return new;
end $$;
