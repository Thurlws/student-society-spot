# Monitoring and alerts

Written 2026-10-16 (roadmap T4.4). The code is in place; the accounts aren't. Nothing is sent anywhere until the variables below are set.

## What exists

| Check | What it tells you | How |
|---|---|---|
| `GET /api/health` | The app server is up and the database answers | Public. 200 `{"status":"ok"}`, or 503 when the database doesn't answer within 5 seconds. Says nothing else |
| `GET /api/health/sign-in` | Sign-in emails are arriving | Needs `Authorization: Bearer <MONITORING_TOKEN>`. Counts sign-in links sent between 24 hours and 30 minutes ago and how many were followed by a sign-in (`sign_in_health`, migration 0027). 503 when at least 5 links of one kind (new accounts or returning) went out and fewer than 3 in 10 were used. That is what the Microsoft 365 quarantine looked like ([sign-in-email-bug.md](sign-in-email-bug.md)) |
| `POST /api/health/test-alert` | Alerts reach someone | Needs the same token. Sends a test error to the error tracker |
| Server errors | Crashes while rendering a page or running a server function | `src/server.ts` and `src/start.ts` send them to the tracker (`src/lib/monitoring.server.ts`) |
| Browser errors | Pages that crash, and sign-in emails that fail to send because of us (the hourly email cap, a sending failure) | `reportFromBrowser` → server function `reportClientError` → the tracker. A person's own cooldown or a wrong address isn't reported |
| Server log (2026-10-16) | What the server did | `log()` in `monitoring.server.ts` writes one JSON line per event to the host's log and, with `SENTRY_DSN` set, sends it to Sentry's Logs (Explore → Logs; `src/server.ts` sends each request's lines after its response, inside `waitUntil` on Workers, at most 100 per envelope): `server_fn` (every server function call, with its name and milliseconds), `server_fn.slow` (over 5 s), `server_fn.failed`, `ai.fallback` (an AI feature fell back to its plain version), `ai.paused` (the AI gateway refused, usually out of credits). Warnings and errors also go to the tracker, tagged with the area and the function, so the same problem groups into one issue |
| `/admin` → System (2026-10-16) | Everything at a glance, for platform admins | Whether error alerts, the uptime token, AI and calls are set up; sign-in links sent and used in the last 24 hours; when each nightly job last ran and whether it worked (`nightly_job_runs`, migration 0033); and a **Send test alert** button, so nobody needs a terminal |

Reports to the tracker carry the error, its stack, the page's path without the query string and, for server functions, the function's name. Email addresses, JWTs, bearer tokens and Supabase keys are scrubbed; request bodies, headers, cookies and user ids are never sent. At most 20 reports a minute per server instance.

The tracker client speaks Sentry's protocol without Sentry's SDK, so it works on Cloudflare Workers, Vercel and Node alike, and a self-hosted GlitchTip works too.

## Setting it up

Free accounts are enough: Sentry's Developer plan (one person, 5,000 errors and 5 GB of logs a month) and an uptime checker's free plan. Every server function call is one log line of a few hundred bytes, so a pilot stays far below the logs allowance.

1. **Error tracker.** Sign up at sentry.io and, when it asks where to store data, pick **EU (Frankfurt)**; that can't be changed later. Create a project (any JavaScript platform; the app doesn't use Sentry's SDK), tracking **Error monitoring** and **Logging** only: session replay would record people's screens, which the privacy notice doesn't cover. The DSN's host has `.de.` in it when the data is in the EU and copy its DSN from Project settings → Client Keys (DSN). Sentry is already in the notice's provider list and [sub-processors.md](../docs/privacy/sub-processors.md).
2. **Secrets** (Lovable → More → Cloud → Secrets; on another host, its environment):
   - `SENTRY_DSN`: the DSN, `https://<key>@<host>/<project id>`.
   - `SENTRY_ENVIRONMENT`: `production` (the default), or `staging` on the staging project.
   - `MONITORING_TOKEN`: a long random string, for example from a password manager. Keep it in the uptime monitor and the password manager only.
3. **Publish**, then open `/admin` → **System** as a platform admin: "Error alerts" should say on. Press **Send test alert**, and the issue "Test alert from SocConnect" should appear in Sentry within a minute.
4. **Alert rules in Sentry** (Alerts → Create alert → Issues): email on every new issue; immediately on any event tagged `area:sign-in` or `area:ai`; on a spike in an existing issue.
5. **Uptime monitor** with a free plan (for example UptimeRobot or Better Stack):
   - `GET https://<app>/api/health` every 5 minutes, expecting `ok`; alert after two failures.
   - Optionally `GET https://<app>/api/health/sign-in` with header `Authorization: Bearer <MONITORING_TOKEN>` every 30 minutes; alert on any non-200. Free plans don't always allow headers; the System tab shows the same numbers.
6. Write down here who gets the alerts and the date it was set up.

From a terminal, the same test alert: `curl -X POST -H "Authorization: Bearer $MONITORING_TOKEN" https://<app>/api/health/test-alert`.

## When an alert fires

- **`/api/health` down:** check Lovable's status page and the Lovable Cloud project. If the database is paused or out of resources, that's in Lovable Cloud → Overview.
- **`/api/health/sign-in` degraded:** ask someone to request a link to a real university mailbox and see whether it arrives, then follow [sign-in-email-bug.md](sign-in-email-bug.md): auth logs in Lovable Cloud, the sending domain, quarantine.
- **`area:sign-in` errors:** usually the hourly email cap (finding 7) or the email service. The error message says which.
- **Server errors:** the stack shows the file. Reproduce on the local stack (`bun run db:start`), fix, and add a test.

## Not covered yet

- Database load and slow queries: Lovable Cloud's own dashboard only.
- Failed nightly jobs (`purge-expired-data`, `end-lapsed-sessions`, `purge-call-transcripts`): `select jobname, status, return_message, start_time from cron.job_run_details order by start_time desc limit 20;` in the SQL editor. A job that alerts on failure needs `pg_net` and a webhook; not worth it before the pilot.
