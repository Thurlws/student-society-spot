-- Onboarding a university needed a developer: TU Dublin's 67 societies came in through a
-- generated migration (0006). Admins can now import a university's societies from a file
-- (/admin → Import societies), with the same rules as 0006:
--   * each row has the university's own id for the society (or its address), stored as
--     source = the university's slug and source_id, so importing again updates instead of
--     duplicating;
--   * a society an admin already created at the same address is adopted, not duplicated;
--   * names, categories, campus, images and official links are refreshed, but a tagline,
--     description or meeting time the committee has changed since the last import is kept;
--   * interests are added, never removed; societies missing from the file are never deleted.
-- Images and links must be https. The whole file is refused if any row is invalid, with the
-- row number, so nothing is half imported.
create or replace function public.import_societies(_university_id uuid, _rows jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  u public.universities; r jsonb; i int := 0; created int := 0; updated int := 0; tagged int := 0; n int;
  _source_id text; _slug text; _suffix text; _name text; _short text;
  _accents text[] := array['indigo','teal','coral','amber','rose','sky','emerald','plum'];
begin
  if not private.can_manage_university(_university_id, auth.uid()) then
    raise exception 'Only that university''s admins can import its societies.';
  end if;
  select * into u from public.universities where id = _university_id;
  if jsonb_typeof(_rows) is distinct from 'array' or jsonb_array_length(_rows) = 0 then raise exception 'The file has no societies in it.'; end if;
  if jsonb_array_length(_rows) > 500 then raise exception 'Import at most 500 societies at a time.'; end if;

  drop table if exists pg_temp._import;
  create temp table _import (n int, source_id text, suffix text, slug text, name text, short_name text, category text, tagline text,
    description text, meets text, campus text, requires_approval boolean, accent text, join_url text, official_url text,
    contact_email text, logo_url text, banner_url text, interests text[]) on commit drop;

  for r in select value from jsonb_array_elements(_rows) loop
    i := i + 1;
    _name := btrim(coalesce(r->>'name', ''));
    _short := coalesce(nullif(btrim(coalesce(r->>'short_name', '')), ''), left(_name, 30));
    _slug := left(btrim(regexp_replace(lower(coalesce(nullif(btrim(coalesce(r->>'slug', '')), ''), _short)), '[^a-z0-9]+', '-', 'g'), '-'), 40);
    _source_id := coalesce(nullif(btrim(coalesce(r->>'id', '')), ''), _slug);
    _suffix := coalesce(nullif(left(regexp_replace(lower(_source_id), '[^a-z0-9]+', '', 'g'), 20), ''), 'import');
    -- Two rows at one address (the same name on two campuses, say): the second gets its id added.
    if exists (select 1 from _import where slug = _slug) then _slug := left(_slug, 39 - length(_suffix)) || '-' || _suffix; end if;
    if char_length(_name) < 2 or char_length(_name) > 100 then raise exception 'Row %: the name needs 2 to 100 characters.', i; end if;
    if char_length(_short) > 30 then raise exception 'Row %: the short name can be up to 30 characters.', i; end if;
    if _slug !~ '^[a-z0-9-]{2,40}$' then raise exception 'Row %: the address needs at least 2 letters or digits.', i; end if;
    if char_length(coalesce(r->>'tagline', '')) > 140 then raise exception 'Row %: the tagline can be up to 140 characters.', i; end if;
    if char_length(coalesce(r->>'description', '')) > 2000 then raise exception 'Row %: the description can be up to 2,000 characters.', i; end if;
    if char_length(coalesce(r->>'meets', '')) > 140 then raise exception 'Row %: the meeting time can be up to 140 characters.', i; end if;
    if exists (select 1 from unnest(array[r->>'join_url', r->>'official_url', r->>'logo_url', r->>'banner_url']) x
               where coalesce(x, '') <> '' and x !~ '^https://[^\s]+$') then
      raise exception 'Row %: links and images must start with https://.', i;
    end if;
    if coalesce(r->>'contact_email', '') <> '' and r->>'contact_email' !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
      raise exception 'Row %: the contact email doesn''t look like an address.', i;
    end if;
    if exists (select 1 from _import where source_id = _source_id) then raise exception 'Row %: the id % is in the file twice.', i, _source_id; end if;
    insert into _import values (i, _source_id, _suffix, _slug, _name, _short,
      coalesce(nullif(btrim(coalesce(r->>'category', '')), ''), 'Community'),
      btrim(coalesce(r->>'tagline', '')), btrim(coalesce(r->>'description', '')), btrim(coalesce(r->>'meets', '')),
      nullif(btrim(coalesce(r->>'campus', '')), ''),
      coalesce(lower(r->>'requires_approval') in ('true', 'yes', 'y', '1'), false),
      case when r->>'accent' = any(_accents) then r->>'accent' else _accents[1 + (hashtext(_source_id) & 7)] end,
      nullif(r->>'join_url', ''), nullif(r->>'official_url', ''), nullif(btrim(coalesce(r->>'contact_email', '')), ''),
      nullif(r->>'logo_url', ''), nullif(r->>'banner_url', ''),
      array(select btrim(x) from jsonb_array_elements_text(case when jsonb_typeof(r->'interests') = 'array' then r->'interests' else '[]' end) x
            where btrim(x) <> ''));
  end loop;

  -- Adopt societies an admin already created at the same address.
  update public.societies s set source = u.slug, source_id = t.source_id
  from _import t
  where s.university_id = u.id and s.slug = t.slug and s.source_id is null
    and not exists (select 1 from public.societies x where x.source = u.slug and x.source_id = t.source_id);

  -- Refresh; keep text the committee has changed since the last import.
  update public.societies s set
    name = t.name, short_name = t.short_name, category = t.category,
    tagline = case when s.tagline = coalesce(s.source_snapshot->>'tagline', case when s.tagline = '' then '' else null end) then t.tagline else s.tagline end,
    description = case when s.description = coalesce(s.source_snapshot->>'description', case when s.description = '' then '' else null end) then t.description else s.description end,
    meets = case when s.meets = coalesce(s.source_snapshot->>'meets', case when s.meets = '' then '' else null end) then t.meets else s.meets end,
    campus = t.campus, logo_url = t.logo_url, banner_url = t.banner_url, join_url = t.join_url,
    official_url = t.official_url, contact_email = t.contact_email, source_synced_at = now(),
    source_snapshot = jsonb_build_object('tagline', t.tagline, 'description', t.description, 'meets', t.meets)
  from _import t
  where s.source = u.slug and s.source_id = t.source_id and s.university_id = u.id;
  get diagnostics updated = row_count;

  -- New societies; an address another society already uses gets the id added.
  insert into public.societies (university_id, slug, name, short_name, category, tagline, description, meets, campus,
    requires_approval, accent, join_url, official_url, contact_email, logo_url, banner_url,
    source, source_id, source_synced_at, source_snapshot)
  select u.id,
    case when exists (select 1 from public.societies x where x.university_id = u.id and x.slug = t.slug)
         then left(t.slug, 39 - length(t.suffix)) || '-' || t.suffix else t.slug end,
    t.name, t.short_name, t.category, t.tagline, t.description, t.meets, t.campus, t.requires_approval, t.accent,
    t.join_url, t.official_url, t.contact_email, t.logo_url, t.banner_url, u.slug, t.source_id, now(),
    jsonb_build_object('tagline', t.tagline, 'description', t.description, 'meets', t.meets)
  from _import t
  where not exists (select 1 from public.societies s where s.source = u.slug and s.source_id = t.source_id)
  order by t.n;
  get diagnostics created = row_count;

  insert into public.society_tags (society_id, interest_id)
  select s.id, it.id from _import t
  join public.societies s on s.source = u.slug and s.source_id = t.source_id
  cross join lateral unnest(t.interests) wanted(name)
  join public.interests it on lower(it.name) = lower(wanted.name)
  on conflict do nothing;
  get diagnostics tagged = row_count;

  perform private.audit('societies.imported', u.id, null, null,
    jsonb_build_object('created', created, 'updated', updated, 'rows', i));
  return jsonb_build_object('created', created, 'updated', updated, 'tags_added', tagged);
end $$;
revoke execute on function public.import_societies(uuid, jsonb) from public, anon;
