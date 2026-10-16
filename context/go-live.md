# Go-live checklist

Written 2026-10-16, after Phases 0 to 4. The code for the TU Dublin demo, the second-university demo and a limited pilot is done; what's left is mostly settings, accounts and agreements that only the owner can do. This puts the rollout steps from [roadmap.md](roadmap.md) and the runbooks in one order. Tick them off here, with the date.

## Before the first demo

| # | Step | Where | Status |
|---|---|---|---|
| 1 | Merge the open branch into `main` and publish in Lovable | GitHub, Lovable | Done 2026-10-16 (Thurlws/student-society-spot#10); publish in Lovable after each merge |
| 2 | Apply migrations 0007 to 0030: paste [`dev/supabase/apply-0007-0030.sql`](../dev/supabase/apply-0007-0030.sql) into Lovable → More → Cloud → SQL editor and run it. One transaction, so all or nothing; a second run changes nothing. Lovable doesn't apply migration files that arrive from GitHub. The first night's purge (0026) finds nothing old enough to delete, because the backend started on 2026-10-10 | Lovable Cloud SQL editor | Done 2026-10-16 by the owner (the run ended with `schedule 3`) |
| 2b | Apply migrations 0031 and 0032 (display names, removal notices): paste [`dev/supabase/apply-0031-0032.sql`](../dev/supabase/apply-0031-0032.sql) into the SQL editor and run it, when the code that uses them is merged and published. It clears names that are only the start of an email address, so those people are asked for a name at their next visit | Lovable Cloud SQL editor | Done 2026-10-16 by the owner: both checks true; 4 people had a student-number name and will be asked for one |
| 2c | Apply migration 0033 (nightly job status for the System tab): paste [`dev/supabase/apply-0033.sql`](../dev/supabase/apply-0033.sql) into the SQL editor. Until then the System tab says it's waiting for it | Lovable Cloud SQL editor | |
| 3 | Run [`dev/supabase/check-migrations.sql`](../dev/supabase/check-migrations.sql) in the SQL editor: every row `yes` | Lovable Cloud SQL editor | Done 2026-10-16: the owner's checks after each bundle came back yes/true |
| 4 | `select jobname, schedule from cron.job;` lists `purge-call-transcripts`, `end-lapsed-sessions` and `purge-expired-data` | SQL editor | Done 2026-10-16: 3 jobs |
| 5 | Every account has a university: the Phase 3 rollout query returns 0 | SQL editor | Done 2026-10-16: 0 |
| 6 | Platform admins are who you expect: the Phase 1 rollout query, step 4 | SQL editor | Done 2026-10-16: nobody is a platform admin. The owner makes themselves one with a `platform_admin` row in `role_invites` (claimed at once for an existing account, at first sign-in otherwise) |
| 7 | Sign-in sender: custom domain, the two email templates, Site URL and redirect URLs, then a test with a new and a returning real mailbox ([sign-in-email-bug.md](sign-in-email-bug.md), steps 2 to 5). Until then, demos rely on releasing the email from quarantine ([demo.md](demo.md)) | Lovable Cloud → Emails, Auth | Waiting: Lovable's custom email sender needs a paid Lovable plan and a domain (2026-10-16). Options without either are in [sign-in-email-bug.md](sign-in-email-bug.md#without-a-domain-or-a-paid-plan) |
| 8 | Ask TU Dublin IT to allow the new sender domain ([sign-in-email-bug.md](sign-in-email-bug.md), step 6) | TU Dublin IT | |
| 9 | Microsoft sign-in: decide whether to keep it (see below) | Lovable Cloud | |
| 10 | Calls in the demo? Set `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`; `/calls` should say "Live calls are on" | Lovable Cloud secrets | Done: the owner confirmed calls work (2026-10-16) |
| 11 | The week-before list in [demo.md](demo.md) | | |

## Before a second university's demo

| # | Step | Status |
|---|---|---|
| 12 | Decide the sign-in email wording: the templates say "the app for TU Dublin societies" ([roadmap.md](roadmap.md), Phase 3 rollout, step 5) | |
| 13 | Their society list as a spreadsheet from their Students' Union, if the demo should show their own societies ([onboarding.md](onboarding.md)) | |

## Before a pilot

| # | Step | Where | Status |
|---|---|---|---|
| 14 | Privacy contact address in `PRIVACY_CONTACT_EMAIL` (`src/lib/privacy.ts`), the team's legal identity, and the providers' regions and terms confirmed | Code, [docs/privacy](../docs/privacy/README.md) | |
| 15 | The university's DPO decides D1 to D6 in [dpia.md](../docs/privacy/dpia.md). If D1 is explicit consent for sensitive societies, that's about two developer-days of code (a "sensitive" flag and a consent step) | DPO | |
| 16 | Processing agreement signed ([processing-agreement.md](../docs/privacy/processing-agreement.md)) | University | |
| 17 | Error alerts: a free Sentry account in the EU region, the three secrets, then **Send test alert** on `/admin` → System, and a free uptime monitor on `/api/health` ([monitoring.md](monitoring.md#setting-it-up)) | Sentry (EU), uptime monitor, Lovable secrets | Code done 2026-10-16 (structured log, warnings, System tab) |
| 18 | Staging project, and every migration through it first ([staging.md](staging.md)) | Lovable | |
| 19 | Bot check on sign-in (audit finding 7), code done 2026-10-16 with Cloudflare Turnstile: (a) free Cloudflare account → Turnstile → add a widget for the published hostname, Managed mode; (b) put the **site key** in `.env` as `VITE_TURNSTILE_SITE_KEY` (public), merge and publish: the check appears and the privacy notice lists Cloudflare; (c) only then turn on enforcement with the **secret key** in Lovable → Cloud → Users → Auth settings (CAPTCHA/bot protection, provider Turnstile), or ask Lovable's chat to enable Supabase Auth CAPTCHA with Turnstile. Doing (c) before (b) stops all email sign-ins. Without (c), bots that use the form are stopped but ones calling the sign-in API directly aren't | Cloudflare, `.env`, Lovable Cloud | (a) and (b) done 2026-10-16: widget in Managed mode, site key in `.env`. (c) waits until that's merged and published |
| 20 | Onboard the university from `/admin` ([onboarding.md](onboarding.md)) | `/admin` | |
| 21 | Load: the app reloads its data every 60 s in each visible tab. Fine for a demo and probably for a small pilot; nobody has load-tested it. Before Freshers' week at full scale, measure on staging or move to realtime updates (Phase 5) | Staging | |
| 22 | A lawyer reviews `/terms` and `/privacy` together; `OPERATOR` in `src/lib/privacy.ts` gets the team's legal name and address | Lawyer, code | |
| 23 | Someone owns reports of illegal content sent to the contact address: confirm receipt, decide, reply (Digital Services Act, article 16; the terms promise it) | Team | |
| 24 | If the university runs SocConnect itself, it needs an accessibility statement (Ireland's S.I. 358/2020 for public bodies). Ask the university | University | |

## Microsoft sign-in

"Sign in with Microsoft" goes through Lovable's sign-in broker, and nobody has checked how it's set up. The risk the audit raised: if it accepts any Microsoft tenant and trusts the email address the tenant reports, someone who controls a tenant could sign in as a student. Since migration 0007 the worst case is a student account, not an admin. Either:

- test it with a Microsoft tenant you control (sign in with an account whose email is set to a university address it doesn't own); if that's refused, keep it and note the date here; or
- ask Lovable to turn the Microsoft provider off, and remove the button from `src/routes/welcome.tsx`.

Hiding the button alone doesn't close the risk, because the provider stays reachable.
