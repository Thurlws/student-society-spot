-- SocConnect: database update 0033 (nightly job status for /admin -> System).
-- Generated 2026-10-16 from drizzle/migrations (unchanged). Lovable does not apply migration
-- files that arrive from GitHub, so paste ALL of this into Lovable: More, then Cloud, then SQL
-- editor, click Run and confirm. One transaction: it goes in, or nothing changes.

begin;

do $check$
begin
  if to_regprocedure('public.nightly_job_runs()') is not null then
    raise exception 'This update is already in this database. Nothing was changed.';
  end if;
  if to_regprocedure('public.delete_message(uuid, text)') is null then
    raise exception 'This database is missing earlier updates (0032). Nothing was changed. Send this message to Claude.';
  end if;
end $check$;

-- ===== 0033_nightly_job_runs =====

-- For the System tab on /admin: when each nightly job last ran and whether it worked. pg_cron
-- keeps its run history in its own schema, which the API can't read, so this reads it for the
-- server (service role only; platform admins see it through a server function).
create or replace function public.nightly_job_runs()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'job', j.jobname,
      'schedule', j.schedule,
      'last_run', r.start_time,
      'status', r.status,
      'message', left(r.return_message, 200)
    ) order by j.jobname), '[]'::jsonb)
  from cron.job j
  left join lateral (
    select d.start_time, d.status, d.return_message from cron.job_run_details d
    where d.jobid = j.jobid order by d.start_time desc limit 1
  ) r on true
$$;
revoke execute on function public.nightly_job_runs() from public, anon, authenticated;
grant execute on function public.nightly_job_runs() to service_role;

-- ===== Bookkeeping =====
-- If Drizzle (Lovable's migration runner) keeps its record here, note this update too.
do $record$
begin
  if to_regclass('drizzle.__drizzle_migrations') is not null then
    insert into drizzle.__drizzle_migrations (hash, created_at) values
      ('addb6ab76b707cbe10a4956caf4964b107fa0e2951349778b77799883313ad4a', 1792120491276);
  end if;
end $record$;

commit;
