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
