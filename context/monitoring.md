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

Reports to the tracker carry the error, its stack and the page's path without the query string. Email addresses, JWTs, bearer tokens and Supabase keys are scrubbed; request bodies, headers, cookies and user ids are never sent. At most 20 reports a minute per server instance.

The tracker client speaks Sentry's protocol without Sentry's SDK, so it works on Cloudflare Workers, Vercel and Node alike, and a self-hosted GlitchTip works too.

## Setting it up

Needs the owner: accounts, and secrets in Lovable Cloud.

1. **Error tracker.** Create a project in Sentry's EU region (sentry.io, data stored in Frankfurt), or another Sentry-compatible tracker hosted in the EU. Add it to [docs/privacy/sub-processors.md](../docs/privacy/sub-processors.md) and the notice's provider list (`src/lib/privacy.ts`) first.
2. **Secrets** (Lovable Cloud → secrets; on another host, its environment):
   - `SENTRY_DSN`: the project's DSN, `https://<key>@<host>/<project id>`.
   - `SENTRY_ENVIRONMENT`: `production` (the default), or `staging` on the staging project.
   - `MONITORING_TOKEN`: a long random string, for example from `openssl rand -hex 32`. Keep it in the uptime monitor and the password manager only.
3. **Check alerts arrive:**
   ```bash
   curl -X POST -H "Authorization: Bearer $MONITORING_TOKEN" https://<app>/api/health/test-alert
   ```
   Expect `{"sent":true}` and an issue "Test alert from SocConnect" in the tracker.
4. **Alert rules in the tracker:** email (or Slack) on every new issue; immediately on any event tagged `area:sign-in`; on a spike in an existing issue.
5. **Uptime monitor** with an EU option (for example Better Stack or UptimeRobot):
   - `GET https://<app>/api/health` every 3 minutes; alert after two failures.
   - `GET https://<app>/api/health/sign-in` with header `Authorization: Bearer <MONITORING_TOKEN>` every 30 minutes; alert on any non-200.
6. Write down in this file who gets the alerts and the date it was set up.

## When an alert fires

- **`/api/health` down:** check Lovable's status page and the Lovable Cloud project. If the database is paused or out of resources, that's in Lovable Cloud → Overview.
- **`/api/health/sign-in` degraded:** ask someone to request a link to a real university mailbox and see whether it arrives, then follow [sign-in-email-bug.md](sign-in-email-bug.md): auth logs in Lovable Cloud, the sending domain, quarantine.
- **`area:sign-in` errors:** usually the hourly email cap (finding 7) or the email service. The error message says which.
- **Server errors:** the stack shows the file. Reproduce on the local stack (`bun run db:start`), fix, and add a test.

## Not covered yet

- Database load and slow queries: Lovable Cloud's own dashboard only.
- Failed nightly jobs (`purge-expired-data`, `end-lapsed-sessions`, `purge-call-transcripts`): `select jobname, status, return_message, start_time from cron.job_run_details order by start_time desc limit 20;` in the SQL editor. A job that alerts on failure needs `pg_net` and a webhook; not worth it before the pilot.
