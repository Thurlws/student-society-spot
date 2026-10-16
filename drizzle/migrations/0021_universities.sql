-- SocConnect was built for TU Dublin alone: its email domains were in code and every society
-- belonged to it implicitly. To take on a second university, universities are now rows. A
-- university has the email domains its people sign in with, members (everyone who signed up
-- with one of those domains), and admins who manage its societies. Every society belongs to
-- one university, and society addresses only need to be unique within it.
-- TU Dublin gets the fixed id md5('tudublin') so tests and imports can name it.
create table public.universities (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9-]{2,40}$'),
  name text not null check (char_length(name) between 2 and 100),
  short_name text not null check (char_length(short_name) between 1 and 30),
  created_at timestamptz not null default now()
);

create table public.university_domains (
  domain text primary key check (domain ~ '^[a-z0-9-]+(\.[a-z0-9-]+)+$'),
  university_id uuid not null references public.universities(id) on delete cascade
);
create index university_domains_university_idx on public.university_domains (university_id);

-- One university per account: the one its email domain belongs to. Filled by handle_new_user.
create table public.university_members (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  university_id uuid not null references public.universities(id) on delete cascade,
  joined_at timestamptz not null default now()
);
create index university_members_university_idx on public.university_members (university_id);

create table public.university_admins (
  university_id uuid not null references public.universities(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  primary key (university_id, user_id)
);
create index university_admins_user_idx on public.university_admins (user_id);

insert into public.universities (id, slug, name, short_name)
  values (md5('tudublin')::uuid, 'tudublin', 'Technological University Dublin', 'TU Dublin');
insert into public.university_domains (domain, university_id)
  values ('mytudublin.ie', md5('tudublin')::uuid), ('tudublin.ie', md5('tudublin')::uuid);
insert into public.university_members (user_id, university_id)
  select p.id, d.university_id from public.profiles p
  join auth.users u on u.id = p.id
  join public.university_domains d on d.domain = split_part(lower(u.email), '@', 2);

alter table public.societies add column university_id uuid references public.universities(id);
update public.societies set university_id = md5('tudublin')::uuid;
alter table public.societies alter column university_id set not null;
alter table public.societies drop constraint societies_slug_key;
alter table public.societies add constraint societies_university_slug_key unique (university_id, slug);

-- Readers and writers are set in the next migration, with the rules that use these tables.
alter table public.universities enable row level security;
alter table public.university_domains enable row level security;
alter table public.university_members enable row level security;
alter table public.university_admins enable row level security;
revoke all on public.universities, public.university_domains, public.university_members, public.university_admins from anon, authenticated;
grant all on public.universities, public.university_domains, public.university_members, public.university_admins to service_role;
