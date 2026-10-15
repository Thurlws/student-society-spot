# Roadmap and audit findings

From the full audit of 2026-10-15. The audit report is a private page (https://claude.ai/artifact/Lfyqs1j3j9QeWVaiY8DLKs) that only its owner can open unless shared. This file is the working copy: update statuses here.

The root `roadmap.md` is Lovable's earlier phase list and is out of date.

## Findings

Line numbers are from commit `e83c5c6`. "Fixed in code" means merged code and migrations; production only changes once the migrations reach Lovable Cloud (see the rollout checklist under Phase 1).

### Must fix

| # | Finding | Where | Task | Status |
|---|---|---|---|---|
| 1 | Returning users don't receive the sign-in email | see [sign-in-email-bug.md](sign-in-email-bug.md) | T1.1 | Cause found (Microsoft 365 quarantine). App side fixed in code 2026-10-16; needs the custom sending domain and email templates in Lovable Cloud |
| 2 | Every `@tudublin.ie` account becomes platform admin | `drizzle/migrations/0000_identity_roles_societies.sql:264-266` | T1.2 | Fixed in code (migration 0007). Existing admin rows still need a manual review |
| 3 | SECURITY DEFINER helpers (`is_society_member`, `is_society_committee`, `has_role`, `society_visible`, `can_see_profile`) can be called through the API, so any student can probe membership of sensitive societies (GDPR Art. 9) | 0000:119-127, 0002:5-8, 0004:2-33 | T1.3 | Fixed in code (migration 0008: `private` schema) |
| 4 | AI caption transcription has no quota | `src/lib/calls.functions.ts:130-142` | T1.4 | Fixed in code (migration 0009) |
| 5 | Every tab reloads all data every 15 s | `src/lib/api/store.tsx:40`, `src/lib/api/fetch.ts:42-68` | T1.5 | Eased: 60 s in visible tabs. Realtime still needed before a large pilot |
| 6 | Users who posted anything can't be deleted (13 foreign keys without ON DELETE); no delete or export in the app | 0000:113, 200; 0001:15, 52, 83, 187, 193, 207, 230; 0003:11, 12, 57, 88 | T1.7 | Fixed in code (migration 0012, Settings → Your data) |
| 7 | Anyone can exhaust the hourly sign-in email cap; no CAPTCHA | `src/routes/welcome.tsx:84`, Lovable Cloud | T1.6 | Open: needs a CAPTCHA account and the custom domain (which raises the cap) |
| 8 | Email change skips the domain trigger (INSERT only) | 0000:256 | T1.6 | Fixed in code (migration 0011) |

### Should fix

| # | Finding | Where | Task | Status |
|---|---|---|---|---|
| 9 | `friendly()` turns server errors into "use your TU Dublin email" | `src/routes/welcome.tsx:69-71` | T1.1 | Fixed 2026-10-16 (`signInError` in `src/lib/auth.tsx`) |
| 10 | No tests for any database rule | `src/test/`, migrations | T2.1 | Started: pgTAP tests in `dev/supabase/tests` cover the Phase 1 changes (`bun run db:test`) |
| 11 | AI "all" block row in `society_ai_state` never expires | `src/lib/society-ai.functions.ts:8-25` | T1.4 | Fixed: expires after 15 minutes |
| 12 | A pending join request reveals the society's member profiles | 0004:21-23 | T1.3 | Fixed in code (migration 0008) |
| 13 | Recap quota check is racy and duplicates `reserve_society_ai` | `src/lib/calls.functions.ts:21-28` | T1.4 | Fixed in code (migration 0009) |
| 14 | No message moderation; no edit or cancel for events and announcements | 0001:88-94, `src/lib/api/store.tsx` | T2.2, T2.3 | Open |
| 15 | Missing indexes on `user_id` lookups and announcements by society and date | 0000, 0001 | T1.5 | Fixed in code (migration 0010) |
| 16 | README described the old browser-only demo | `README.md` | T0.3 | Fixed 2026-10-15 |
| 17 | Committees can rename their society or change its logo | 0006:19-33 | Later | Open |

### Nice to have

| # | Finding | Where | Status |
|---|---|---|---|
| 18 | `getUser()` network call on every navigation | `src/routes/_authenticated/route.tsx:8-11` | Open |
| 19 | "(demo figure)" and demo calendar ids on real data | `societies.$societyId.tsx:228`, `src/lib/ics.ts:21-23` | Open (T2.4) |
| 20 | 25 unused shadcn components (3,118 lines) and about 20 packages only they use. Keep `input-otp` | `src/components/ui/` | Open (T2.6) |

Found while fixing: guest captions stopped for everyone once a guest link's last allowed guest joined. Fixed with T1.4.

## Phases

Effort in working days for one developer who knows the code: XS up to half a day, S 1-2, M 3-5, L 1-2 weeks, XL more.

### Phase 0: baseline (done 2026-10-15)

| Task | Status |
|---|---|
| T0.1 Local Supabase stack replaying the migrations | Done: `dev/supabase/`, `db:*` scripts; `db:check-sign-in` passes |
| T0.2 Find the sign-in email cause | Done: the emails were in Microsoft 365 quarantine |
| T0.3 Rewrite README | Done |
| T0.4 CI: typecheck, tests, build | Done: passed on Thurlws/SocConnect-SC-#7 and on that repo's `main` |

Hosting: we stay on Lovable until a university pilot provides infrastructure. See [hosting.md](hosting.md).

### Phase 1: critical fixes (code done 2026-10-16, branch `phase-1`)

| Task | Status |
|---|---|
| T1.1 Sign-in | Code done: real error messages, resend countdown, quarantine hint, `/auth/confirm` page, new email wording, 10-minute links (local). Waiting on: custom sending domain, templates and expiry in Lovable Cloud, an allow rule from TU Dublin IT |
| T1.2 No admin by email domain | Done (0007). Review existing admins in production |
| T1.3 Hide permission helpers; pending requests | Done (0008) |
| T1.4 AI quotas, block expiry | Done (0009) |
| T1.5 Polling and indexes | Done: 60 s polling, indexes (0010) |
| T1.6 Domain check on email change; CAPTCHA | Email change done (0011). CAPTCHA waits for a Cloudflare Turnstile (or hCaptcha) account |
| T1.7 Deletable accounts, export | Done (0012, Settings → Your data) |

**Rollout checklist (production):**

1. Merge `phase-1`.
2. Make sure migrations 0007 to 0012 are applied to Lovable Cloud **at the same time as the code is published**. The recap, question and caption code needs 0009: without it, `reserve_society_ai` refuses those features. We still haven't seen how Lovable treats migrations that arrive from GitHub; if they aren't applied, ask Lovable to apply the pending migrations in `drizzle/migrations`.
3. Check in Lovable Cloud's SQL editor: `select proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'private';` should list the 5 helpers.
4. Review platform admins: `select u.email from public.user_roles r join auth.users u on u.id = r.user_id;` and delete rows for anyone who shouldn't be one.
5. Sign-in setup (needs the domain): see the checklist in [sign-in-email-bug.md](sign-in-email-bug.md).

### Phase 2: core and tests

T2.1 database test suite, a role-by-table permission matrix (P0, M; started in `dev/supabase/tests`). T2.2 edit and cancel events and announcements (P1, M). T2.3 message moderation (P1, S-M). T2.4 remove demo labels (P2, XS). T2.5 Playwright journeys in CI, plus a CI job for `db:test` (P1, M). T2.6 lean cleanup and a Prettier pass (P3, XS).

### Phase 3: multi-university

T3.1 tables `universities`, `university_domains`, `university_members`, `university_roles`, plus `societies.university_id` with a TU Dublin backfill (P0, M, needs T2.1). T3.2 tenant-aware `private.society_visible`, society policies, `private.can_see_profile`, invites, `my_access`, sign-up trigger (P0, M, needs T3.1). T3.3 cross-university isolation tests (P0, M). T3.4 university admin console (P1, M). T3.5 remove TU Dublin hard-coding (P1, M). T3.6 yearly re-verification (P2, S).

### Phase 4: pilot readiness

T4.1 privacy notice, sub-processors, retention, DPIA, processing-agreement template (P0, M). T4.2 audit log (P1, S). T4.3 suspension (P1, S). T4.4 monitoring and alerts (P1, S). T4.5 staging project (P1, M). T4.6 onboarding runbook and society import (P2, M).

### Phase 5: when demand justifies it

Realtime notifications, per-page loading and pagination, SSO per university, email digests, analytics for societies officers, links into official membership systems.

## Milestones

- **TU Dublin demo:** finish T1.1 (domain and templates), roll out Phase 1, then T2.4.
- **Trinity or UCD demo:** add T2.1, T3.1-T3.3, T3.5. About 3 to 5 more developer-weeks.
- **Limited pilot:** all of Phases 0 to 4. About 7 to 12 more developer-weeks plus time with the university's DPO and IT team.
