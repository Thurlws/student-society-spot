# Go-live checklist

Written 2026-10-16, after Phases 0 to 4. The code for the TU Dublin demo, the second-university demo and a limited pilot is done; what's left is mostly settings, accounts and agreements that only the owner can do. This puts the rollout steps from [roadmap.md](roadmap.md) and the runbooks in one order. Tick them off here, with the date.

## Before the first demo

| # | Step | Where | Status |
|---|---|---|---|
| 1 | Merge the open branch into `main` and publish in Lovable | GitHub, Lovable | Done 2026-10-16 (Thurlws/student-society-spot#10); publish in Lovable after each merge |
| 2 | Apply migrations 0007 to 0030: paste [`dev/supabase/apply-0007-0030.sql`](../dev/supabase/apply-0007-0030.sql) into Lovable → More → Cloud → SQL editor and run it. One transaction, so all or nothing; a second run changes nothing. Lovable doesn't apply migration files that arrive from GitHub. The first night's purge (0026) finds nothing old enough to delete, because the backend started on 2026-10-10 | Lovable Cloud SQL editor | Done 2026-10-16 by the owner (the run ended with `schedule 3`) |
| 2b | Apply migrations 0031 and 0032 (display names, removal notices): paste [`dev/supabase/apply-0031-0032.sql`](../dev/supabase/apply-0031-0032.sql) into the SQL editor and run it, when the code that uses them is merged and published. It clears names that are only the start of an email address, so those people are asked for a name at their next visit | Lovable Cloud SQL editor | Done 2026-10-16 by the owner: both checks true; 4 people had a student-number name and will be asked for one |
| 2c | Apply migration 0033 (nightly job status for the System tab): paste [`dev/supabase/apply-0033.sql`](../dev/supabase/apply-0033.sql) into the SQL editor. Until then the System tab says it's waiting for it | Lovable Cloud SQL editor | Done 2026-10-16 by the owner |
| 3 | Run [`dev/supabase/check-migrations.sql`](../dev/supabase/check-migrations.sql) in the SQL editor: every row `yes` | Lovable Cloud SQL editor | Done 2026-10-16: the owner's checks after each bundle came back yes/true |
| 4 | `select jobname, schedule from cron.job;` lists `purge-call-transcripts`, `end-lapsed-sessions` and `purge-expired-data` | SQL editor | Done 2026-10-16: 3 jobs |
| 5 | Every account has a university: the Phase 3 rollout query returns 0 | SQL editor | Done 2026-10-16: 0 |
| 6 | Platform admins are who you expect: the Phase 1 rollout query, step 4 | SQL editor | Done 2026-10-16: nobody is a platform admin. The owner makes themselves one with a `platform_admin` row in `role_invites` (claimed at once for an existing account, at first sign-in otherwise) |
| 7 | Sign-in sender: custom domain, the two email templates, Site URL and redirect URLs, then a test with a new and a returning real mailbox ([sign-in-email-bug.md](sign-in-email-bug.md), steps 2 to 5). Until then, demos rely on releasing the email from quarantine ([demo.md](demo.md)) | Lovable Cloud → Emails, Auth | Waiting: Lovable's custom email sender needs a paid Lovable plan and a domain (2026-10-16). Options without either are in [sign-in-email-bug.md](sign-in-email-bug.md#without-a-domain-or-a-paid-plan) |
| 8 | Ask TU Dublin IT to allow the new sender domain ([sign-in-email-bug.md](sign-in-email-bug.md), step 6) | TU Dublin IT | |
| 9 | Microsoft sign-in stays on, limited to each university's own Microsoft organisation (0040): apply the migration, then run the two checks under [Microsoft sign-in](#microsoft-sign-in) | Lovable Cloud SQL editor | Code done 2026-10-17 (`claude/audit-fixes`); the checks need the owner |
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
| 17 | Error alerts and logs: a free Sentry account in the EU region (Error monitoring and Logging, no session replay), the three secrets, then **Send test alert** on `/admin` → System, and a free uptime monitor on `/api/health` ([monitoring.md](monitoring.md#setting-it-up)) | Sentry (EU), uptime monitor, Lovable secrets | Code done 2026-10-16 (structured log, warnings, System tab) |
| 18 | Staging project, and every migration through it first ([staging.md](staging.md)) | Lovable | |
| 19 | Bot check on sign-in (audit finding 7), code done 2026-10-16 with Cloudflare Turnstile: (a) free Cloudflare account → Turnstile → add a widget for the published hostname, Managed mode; (b) put the **site key** in `.env` as `VITE_TURNSTILE_SITE_KEY` (public), merge and publish: the check appears and the privacy notice lists Cloudflare; (c) only then turn on enforcement with the **secret key** in Lovable → Cloud → Users → Auth settings (CAPTCHA/bot protection, provider Turnstile), or ask Lovable's chat to enable Supabase Auth CAPTCHA with Turnstile. Doing (c) before (b) stops all email sign-ins. Without (c), bots that use the form are stopped but ones calling the sign-in API directly aren't | Cloudflare, `.env`, Lovable Cloud | (a) and (b) done 2026-10-16: widget in Managed mode, site key in `.env`. (c) waits until that's merged and published. Lovable's Auth settings screen has no CAPTCHA option (its sign-in methods, sign-up switches and Advanced: Site URL, redirect URLs), so (c) goes through Lovable's chat. If Lovable can't set it, the form check stays, and the hourly email limit (Auth settings → Email → Advanced) bounds direct API calls |
| 20 | Onboard the university from `/admin` ([onboarding.md](onboarding.md)) | `/admin` | |
| 21 | Load: the app reloads its data every 60 s in each visible tab. Fine for a demo and probably for a small pilot; nobody has load-tested it. Before Freshers' week at full scale, measure on staging or move to realtime updates (Phase 5) | Staging | Public pages measured 2026-10-17 on production, from one machine: 12,000 visitors at 40 a second, each loading `/welcome` and `/api/health` (24,000 requests), got p50 0.10 s, p95 0.57 s, p99 1.2 s and no HTTP errors; one 5-second burst of 44 connection resets (0.2%). At 80 a second, responses queued and p95 passed 5 s, still without errors. Signed-in load isn't measured: each open tab makes about 23 requests a minute, so 12,000 people with the app open would be about 4,600 a second at the database |
| 22 | A lawyer reviews `/terms` and `/privacy` together; `OPERATOR` in `src/lib/privacy.ts` gets the team's legal name and address | Lawyer, code | |
| 23 | Someone owns reports of illegal content sent to the contact address: confirm receipt, decide, reply (Digital Services Act, article 16; the terms promise it) | Team | |
| 24 | If the university runs SocConnect itself, it needs an accessibility statement (Ireland's S.I. 358/2020 for public bodies). Ask the university | University | |

## Microsoft sign-in

"Sign in with Microsoft" goes through Lovable's broker, which accepts any Microsoft account from any organisation; its docs say the tenant can't be restricted in managed mode. On its own, the address such an account reports proves nothing: whoever runs a Microsoft organisation can make an account report a university address. Signing up with it would make them a member of that university and give them any invite waiting for that address, platform admin, university admin and committee seats included (audit finding 49).

Since migration 0040, each university email domain records the Microsoft organisation (tenant) that owns it, and the database refuses a Microsoft identity from any other tenant, inside the sign-in itself, so nothing is created. A domain can only be verified in its owner's tenant, so this works for every university without limiting it to one. TU Dublin's two domains are set by the migration. For another university, a platform admin turns on **Microsoft sign-in** next to each domain in `/admin` → Universities; the server asks Microsoft which tenant owns the domain. Domains without it use the email link.

The check sees what Supabase Auth saves about each sign-in, so confirm the broker saves Microsoft sign-ins as Microsoft. After applying 0040, in the SQL editor:

```sql
-- 1. Microsoft sign-ins are saved as Microsoft: expect an "azure" row (or one with
--    microsoft_issuer > 0) once anyone has used the button.
select provider, count(*) as identities,
  count(*) filter (where identity_data->>'iss' ~ '^https://(login\.microsoftonline\.com|sts\.windows\.net)/') as microsoft_issuer
from auth.identities group by provider;

-- 2. No Microsoft identity from before 0040 came from the wrong organisation: expect 0.
select count(*) from auth.identities i
where (i.provider = 'azure' or i.identity_data->>'iss' ~ '^https://login\.microsoftonline\.com/')
  and not exists (select 1 from public.university_domains d
    where d.domain = split_part(lower(i.identity_data->>'email'), '@', 2)
      and lower(i.identity_data->>'iss') like '%' || d.microsoft_tenant_id::text || '%');
```

If check 1 shows Microsoft sign-ins under `email`, or without an issuer, the broker hides who signed them in and 0040 can't tell them apart. Then switch Lovable's Microsoft sign-in to **Your own credentials** (More → Cloud → Users → Auth settings → Microsoft) with an Azure app registered for "Accounts in any organizational directory", Tenant ID `organizations`, and the default that leaves unverified addresses out of the token. If check 2 isn't 0, look at those accounts before anything else.

A live test anyone can do: make a personal Microsoft account with a university address (Microsoft verifies it with a code), then use "Sign in with Microsoft" with it. It should be refused, because personal accounts belong to Microsoft's consumer tenant, not the university's.
