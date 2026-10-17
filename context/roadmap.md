# Roadmap and audit findings

From the full audit of 2026-10-15. The audit report is a private page (https://claude.ai/artifact/Lfyqs1j3j9QeWVaiY8DLKs) that only its owner can open unless shared. This file is the working copy: update statuses here.

The root `roadmap.md` only points here now (2026-10-16); it used to hold Lovable's earlier phase list.

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
| 10 | No tests for any database rule | `src/test/`, migrations | T2.1 | Fixed 2026-10-16: role-by-table permission matrix, function rule tests, CI job |
| 11 | AI "all" block row in `society_ai_state` never expires | `src/lib/society-ai.functions.ts:8-25` | T1.4 | Fixed: expires after 15 minutes |
| 12 | A pending join request reveals the society's member profiles | 0004:21-23 | T1.3 | Fixed in code (migration 0008) |
| 13 | Recap quota check is racy and duplicates `reserve_society_ai` | `src/lib/calls.functions.ts:21-28` | T1.4 | Fixed in code (migration 0009) |
| 14 | No message moderation; no edit or cancel for events and announcements | 0001:88-94, `src/lib/api/store.tsx` | T2.2, T2.3 | Fixed in code 2026-10-16 (migrations 0014-0016) |
| 15 | Missing indexes on `user_id` lookups and announcements by society and date | 0000, 0001 | T1.5 | Fixed in code (migration 0010) |
| 16 | README described the old browser-only demo | `README.md` | T0.3 | Fixed 2026-10-15 |
| 17 | Committees can rename their society or change its logo | 0006:19-33 | Later | Fixed in code 2026-10-16 (0029): name, short name, category, logo and banner are admin and import only |

### Nice to have

| # | Finding | Where | Status |
|---|---|---|---|
| 18 | `getUser()` network call on every navigation | `src/routes/_authenticated/route.tsx:8-11` | Fixed 2026-10-16: the stored session decides, and a network blip no longer sends people to `/welcome` |
| 19 | "(demo figure)" and demo calendar ids on real data | `societies.$societyId.tsx:228`, `src/lib/ics.ts:21-23` | Fixed 2026-10-16 (T2.4) |
| 20 | 25 unused shadcn components (3,118 lines) and about 20 packages only they use. Keep `input-otp` | `src/components/ui/` | Fixed 2026-10-16 (T2.6): 28 components and 23 packages removed |

Found while fixing: guest captions stopped for everyone once a guest link's last allowed guest joined. Fixed with T1.4.

### Found in Phase 2 (2026-10-16)

Line numbers are from commit `566c72c`.

| # | Finding | Where | Status |
|---|---|---|---|
| 21 | Anyone with a recap's id could share a drop-in room's private recap into the society's general channel: those rooms have no host, and `host_id = auth.uid()` was null, so the check never refused | 0008 `share_recap` | Fixed in code (0013). Found by the permission matrix |
| 22 | Committees could change an announcement's author or date (the audit's "left out" list) | 0001:63 | Fixed in code (0015) |
| 23 | `register_for_event` took registrations for events the caller can't see, such as an archived society's | 0001 `register_for_event` | Fixed in code (0014) |
| 24 | A committee member on two societies could save one society's profile text over the other: the edit form kept the first society's text after switching | `committee.tsx` `EditDialog` | Fixed 2026-10-16 |
| 25 | Picking interests during onboarding could replace the name being typed with the start of the email address | `src/components/profile-form.tsx` | Fixed 2026-10-16. Found by the sign-up journey |
| 26 | Text typed into the sign-in form before the page finishes loading is lost, and pressing Continue on `/auth/confirm` that early does nothing. Only noticeable on slow connections | `welcome.tsx`, `auth.confirm.tsx` | Fixed 2026-10-16: the buttons wait for the page to load and keep what was typed (journey in `sign-in.spec.ts`) |
| 27 | Any signed-in user can save any proposal id, and the error for an unknown id tells them whether it exists | 0001 `saved_proposals` | Fixed in code 2026-10-16 (0030) |

### Found reviewing Phase 2 (2026-10-16)

Two reviews of the merged Phase 2 code (database and app), branch `phase-2-followups`. Line numbers are from commit `7666950`.

| # | Finding | Where | Status |
|---|---|---|---|
| 28 | A committee member whose own message was reported could see who reported it and dismiss the report, which also took it off `/admin`. A committee member who reported a message was notified about their own report | 0016 `message_reports` policy, `dismiss_message_reports`, `report_message` | Fixed in code (0017) |
| 29 | Committees could still delete events through the API (the 0001 delete policy), taking registrations with them and telling nobody | 0001 "Committee delete events" | Fixed in code (0018) |
| 30 | A new announcement could set its own `created_at` and stay above every other post | 0015 left inserts open | Fixed in code (0019) |
| 31 | A call's host could share its recap into #general after leaving the society | 0013 `share_recap` | Fixed in code (0020) |
| 32 | "Remove message" in the reports queue deleted at once, with no confirm step | `src/components/moderation.tsx:212` | Fixed 2026-10-16 |
| 33 | Save buttons in the event, announcement and report dialogs stayed enabled while saving: a double click made two events or posts and notified everyone twice | `event-dialog.tsx`, `announcement-dialog.tsx`, `moderation.tsx` | Fixed 2026-10-16 |
| 34 | Cancelled events still showed as "your next event", in the calendar view, and in the AI's context | `_authenticated/index.tsx:49`, `events.index.tsx`, `society-ai.functions.ts` | Fixed 2026-10-16 |
| 35 | Editing or deleting an announcement someone else had already removed said it worked | `store.tsx` | Fixed 2026-10-16 |
| 36 | After a report was dismissed, "Report" came back for the reporter and then failed | `fetch.ts` | Fixed 2026-10-16 |
| 37 | A report notification opened the first committee seat, not the society it was about | `committee.tsx:68` | Fixed 2026-10-16 (with 0017) |
| 38 | A failed event cancellation closed the dialog and lost the typed reason | `events.$eventId.tsx:318` | Fixed 2026-10-16 |
| 39 | The events journey failed on `main` after the merge: it clicked before the page hydrated | `e2e/*.spec.ts` | Fixed 2026-10-16: every navigation waits for the network to go quiet |
| 40 | `bun run db:*` failed (`Invalid Argument '-s'`) | `package.json` | Fixed 2026-10-16: the scripts call the Supabase CLI directly |

Left as they are: cancellation and change notices follow the "Event updates" setting, which says it covers them; `update_event` sets the tags to the category, as `create_event` does; `src/test/livekit-token.test.ts` imports `jose`, which only resolves through LiveKit's dependencies.

### Found in Phase 4 (2026-10-16)

| # | Finding | Where | Status |
|---|---|---|---|
| 41 | Every page loaded its fonts from Google Fonts, sending each visitor's IP address to Google | `src/routes/__root.tsx` | Fixed 2026-10-16: fonts bundled from `@fontsource-variable` |
| 42 | "Download my data" left out the university membership, reports the person made, their comments on member requests, calls they joined and saved proposals | `settings.tsx` | Fixed 2026-10-16 (`src/lib/api/my-data.ts`) |
| 43 | The 7-day transcript purge had no test | 0003 | Fixed 2026-10-16 (`retention.test.sql`) |
| 44 | Captions were on by default, so joining a call meant consenting to AI processing of your voice unless you noticed the button | `call-experience.tsx` | Fixed 2026-10-16: off until each person turns theirs on |

### Found in Sentry (2026-10-17, branch `claude/changes`)

| # | Finding | Where | Status |
|---|---|---|---|
| 45 | Every AI gateway failure reached the code as a generic "No output generated" with no status, so running out of credits (402/403) never paused AI and a busy gateway (429) never showed its notice | `ai.server.ts` | Fixed 2026-10-17: the original error is kept and rethrown (`ai-errors.test.ts`) |
| 46 | Recommendation explanations took up to about 7 s (`server_fn.slow`): up to three AI calls one after another, with reasoning on, for one sentence each. Overlapping page loads all missed the cache and could use up the 20-an-hour `society_fit` quota | `explainSocietyFits` | Fixed 2026-10-17: one query each for societies and cache, AI calls side by side, reasoning off (`ai.quick_refused` if the model refuses that). Calls that overlap can still both miss the cache |
| 47 | When AI was skipped (paused, out of credits, over the hourly limit) the plain "Matches your interests in ..." line was shown as "Written by AI" | `explainSocietyFits` | Fixed 2026-10-17: only AI-written sentences are returned as reasons |
| 48 | A log line and the Sentry issue it raised had different trace ids, so the issue couldn't be traced back to its log line | `monitoring.server.ts` | Fixed 2026-10-17: one trace id for both |

### Found in the audit of 2026-10-17 (branch `claude/audit-fixes`)

Line numbers are from commit `9af30db`.

| # | Finding | Where | Status |
|---|---|---|---|
| 49 | Sign-up gives an account every unclaimed invite for its address. If Lovable's Microsoft broker trusts the address any Microsoft organisation reports (unverified, go-live step 9), someone can sign in as an invited address before its owner and take a platform admin, university admin or committee seat, not just a student account | `0031_display_names.sql:15`, `welcome.tsx:206` | Open |
| 50 | A call's captions take the speaker's name from the message, so anyone in the call (a guest too) can put words in someone else's mouth, and the AI recap lists them as decisions | `live-call.tsx:109` | Fixed 2026-10-17: the name comes from the sender's LiveKit token, and lines are cut at 2,000 characters, the most a recap accepts |
| 51 | Everyone who leaves a call with captions writes their own recap: a 10-person call makes 10 recaps, 10 AI calls, and uses one of each person's 10 recaps an hour | `call-experience.tsx:322`, `calls.functions.ts:37` | Fixed 2026-10-17 (`calls.server.ts`): the first person to leave writes it, saved before the AI starts, and anyone leaving in the next ten minutes gets the same one and is added to its readers (`call-recaps.test.ts`) |
| 52 | The app loads the newest 500 messages across all your channels and the newest 200 announcements across all your societies, so a quiet channel or society looks empty once a busy one has more | `fetch.ts:120-126` | Fixed in code 2026-10-17 (0039): `recent_messages` (100 per channel) and `recent_announcements` (50 per society, pinned first), with the old query as a fallback until 0039 is in production |
| 53 | A member can set a message's `created_at` (2099 keeps it last in the channel forever); 0019 closed this for announcements only | 0001 `messages`, 0034 insert policy | Fixed in code 2026-10-17 (0038): signed-in users insert only `channel_id`, `author_id` and `body`, as 0019 did for announcements |
| 54 | Someone removed from a society can still write recaps for its rooms for 90 days: `summarizeCall` reads the room past RLS and only asks whether they ever joined it | `calls.functions.ts:48-66` | Fixed 2026-10-17: the room is read through RLS, so only current members and the committee get past it |
| 55 | The 60 s reload fetches every recap's full transcript (up to 600 lines each, the last 7 days' worth), though only the recap page shows it | `fetch.ts:154` | Fixed 2026-10-17: the reload leaves it out, and the recap page reads it when it opens (`loadTranscript`), with loading and retry states |
| 56 | A downloaded `.ics` uses floating times, so a device not set to Dublin time puts the event at the wrong hour | `ics.ts:36-60` | Open |
| 57 | Error reports send the page's path unscrubbed, so a crash on `/api/calendar/<key>` or `/join/<code>` puts that secret in the error tracker | `monitoring.server.ts:91`, `start.ts:15`, `report-error.ts` | Open |
| 58 | Nothing tests the call server functions (who gets a token, who can write a recap), where 51 and 54 were | `calls.functions.ts`, `livekit.functions.ts` | Fixed 2026-10-17 for recaps: `call-recaps.test.ts` covers who may write one, one per call, and the AI failing. Tokens are still untested beyond `livekit-token.test.ts` |
| 59 | Two questions about a recap at the same moment: the second write of the Q&A list wipes the first | `calls.functions.ts:146-180` | Open |
| 60 | Assigning a member request looks the committee member up by display name, so two committee members with the same name can't both be picked | `fetch.ts:192`, `store.tsx:391` | Open |
| 61 | `dev/supabase/apply-*.sql` (2,576 lines) repeat migrations production may already have | `dev/supabase/` | Open: delete once `check-migrations.sql` shows production is up to date |

Found while fixing: a call with more than 600 caption lines (about an hour of talk) couldn't save a recap at all; the server refused the transcript. Fixed 2026-10-17: up to 2,000 lines, and the browser sends the last 2,000 of a longer call.

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
| T1.1 Sign-in | Code done: real error messages, resend countdown, quarantine hint, `/auth/confirm` page, new email wording, 10-minute links (production setting changed by the owner 2026-10-16). Waiting on: custom sending domain, templates in Lovable Cloud, an allow rule from TU Dublin IT |
| T1.2 No admin by email domain | Done (0007). Review existing admins in production |
| T1.3 Hide permission helpers; pending requests | Done (0008) |
| T1.4 AI quotas, block expiry | Done (0009) |
| T1.5 Polling and indexes | Done: 60 s polling, indexes (0010) |
| T1.6 Domain check on email change; CAPTCHA | Email change done (0011). CAPTCHA: Cloudflare Turnstile on the sign-in form (go-live step 19) |
| T1.7 Deletable accounts, export | Done (0012, Settings → Your data) |

**Rollout checklist (production):**

1. Merge `phase-1` and Phase 2 (both done 2026-10-16), then `phase-2-followups`.
2. Make sure migrations 0007 to 0020 are applied to Lovable Cloud **at the same time as the code is published**. Phase 2's code reads columns and calls functions from 0014 to 0016 (`cancelled_at`, `edited_at`, `message_reports`), so the data load fails without them. The recap, question and caption code needs 0009: without it, `reserve_society_ai` refuses those features. Lovable doesn't apply migrations that arrive from GitHub (found 2026-10-16): apply them with `dev/supabase/apply-0007-0030.sql` in the SQL editor.
3. Check in Lovable Cloud's SQL editor: `select proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'private';` should list the 5 helpers.
4. Review platform admins: `select u.email from public.user_roles r join auth.users u on u.id = r.user_id;` and delete rows for anyone who shouldn't be one.
5. Sign-in setup (needs the domain): see the checklist in [sign-in-email-bug.md](sign-in-email-bug.md).

### Phase 2: core and tests (merged 2026-10-16, `Thurlws/student-society-spot#3`; review fixes on `phase-2-followups`)

| Task | Status |
|---|---|
| T2.1 Database tests | Done: `permission_matrix.test.sql` runs every table and function as seven kinds of user (signed out, student, applicant, member, committee, another society's committee, platform admin) and guards against tables without RLS, open read policies and new callable owner-rights functions. Rule tests for the write functions. CI job `database`. Breaking a policy turns CI red (checked) |
| T2.2 Edit and cancel | Done (0014, 0015): committees edit and cancel events (registered people are notified of time or place changes; members and registered people of cancellations; cancelled events refuse registrations) and edit or delete announcements (wording and pin only, marked "edited"). Pinned announcements now come first |
| T2.3 Moderation | Done (0016): authors delete their own messages; the committee and platform admins remove any; members report a message to the committee, which gets a notification and a queue on its dashboard; admins see every open report on `/admin`. A student can't delete someone else's message (tested) |
| T2.4 Demo labels | Done |
| T2.5 Browser journeys | Done: Playwright in `e2e/` against the local stack, with sign-in through Mailpit: new and returning sign-in, join and approve, events, announcements, moderation, the committee's society picker. CI job `journeys` |
| T2.6 Lean cleanup | Done: 28 unused UI components and 23 packages removed; Prettier run once; lint in CI |

### Phase 3: multi-university (code done 2026-10-16, branch `phase-3`)

| Task | Status |
|---|---|
| T3.1 Universities | Done (0021): `universities`, `university_domains`, `university_members` (one university per account, from its email domain), `university_admins` (named for what it holds, instead of the planned `university_roles`), `societies.university_id`. Existing societies and accounts moved to TU Dublin (id `md5('tudublin')`). Society addresses are unique per university |
| T3.2 Tenant-aware rules | Done (0022): `society_visible`, `can_see_profile`, society, tag, committee, resource, proposal and report policies, invites, `join_society`, the count functions, `my_access`, sign-up and email-change triggers. New helpers `private.can_manage_university` / `can_manage_society` replace platform-admin checks on society-scoped rules. Invites grant what their role says (before, any invite without a society made a platform admin) |
| T3.3 Isolation tests | Done: `university_isolation.test.sql`; the permission matrix now has nine kinds of user (added a student at another university and a university admin). They caught one gap before release: editing a collaboration proposal could point it at another university's society, which creating one can't |
| T3.4 University admin console | Done: `/admin` for platform and university admins; platform admins pick the university, add universities and domains, and appoint university admins |
| T3.5 TU Dublin hard-coding | Done in code. Left on purpose: the society data imported from societies.tudublin.ie, the TU Dublin course list (offered to TU Dublin members only), the brand colour, the welcome page's example societies, and the sign-in email templates (see below) |
| T3.6 Yearly re-verification | Done (0023): every sign-in counts as verification; a nightly job ends the sessions of accounts that haven't signed in for a year, so the next sign-in needs the university mailbox again |

**Rollout (with or after Phase 2):**

1. Apply migrations 0021 to 0023 at the same time as the Phase 3 code. The app reads `my_access().university` and creates societies with a `university_id`.
2. In Lovable Cloud's SQL editor, check every account got a university: `select count(*) from public.profiles p where not exists (select 1 from public.university_members m where m.user_id = p.id);` should be 0. Anyone counted can still sign in but sees no societies; ask before fixing them by hand.
3. Check the nightly job exists: `select jobname, schedule from cron.job;` should list `end-lapsed-sessions`.
4. Optional: appoint TU Dublin university admins (for example Students' Union staff) from `/admin` → Universities.
5. Before a second university goes live: decide the sign-in email wording. `dev/supabase/templates/` says "the app for TU Dublin societies", which helps TU Dublin students trust the email but is wrong for anyone else. The templates can't know the recipient's university unless Lovable's template data includes it.

### Phase 4: pilot readiness (code done 2026-10-16, branch `claude/blissful-meitner-4f4ulx`)

| Task | Status |
|---|---|
| T4.1 Privacy pack | Code and drafts done. `/privacy` notice (public, linked from welcome, the account menu, Settings and the suspension notice); `docs/privacy/`: sub-processors, retention schedule, draft DPIA with open decisions, processing agreement template; nightly `purge_expired_data` (0026); captions off by default; fonts bundled; fuller data download. Waiting on: a privacy contact address, the team's legal identity, confirming providers' regions and terms, and the DPO's decisions (D1-D6 in `docs/privacy/dpia.md`, above all the legal basis for sensitive societies) |
| T4.2 Audit log | Done (0024): admin and committee grants, invites, society and university changes, domains, moderation removals, dismissed reports, cancelled events, account deletions, suspensions and imports; read on `/admin` → Activity; nobody can edit it. Membership decisions and removed messages' authors left out on purpose (special-category data) |
| T4.3 Suspension | Done (0025): `suspend_user`, `reinstate_user`, `find_people`; every permission helper treats a suspended account as having no rights; the person sees the reason; `/admin` → People, and "Suspend author" in the reports queue. A suspended account can't delete itself |
| T4.4 Monitoring | Code done: `/api/health`, `/api/health/sign-in` (sign-in link use, 0027), `/api/health/test-alert`; server and browser errors to a Sentry-compatible EU tracker. Waiting on: a tracker account, an uptime monitor and three secrets ([monitoring.md](monitoring.md)) |
| T4.5 Staging | Runbook done ([staging.md](staging.md)) and `dev/supabase/check-migrations.sql`. Waiting on: the owner creating the staging project in Lovable |
| T4.6 Onboarding | Done: CSV society import on `/admin` (0028, same rules as 0006) and the runbook ([onboarding.md](onboarding.md)) |

**Rollout (with or after Phase 3):**

1. Read this first: the first night after 0026 is applied, `purge_expired_data` deletes everything already past its period (read notifications older than 90 days, AI usage older than 30 days, call recaps older than a year, and so on; see `docs/privacy/retention.md`). If anything should be kept, change the periods before applying it.
2. Apply migrations 0024 to 0030 together with the Phase 4 code (0029 and 0030 came after Phase 4; see below). The code works without them (the new admin sections stay hidden and the import says it needs the update), but suspension, the audit log and retention only exist once they're in.
3. Run `dev/supabase/check-migrations.sql` in Lovable Cloud's SQL editor: every row from 0007 to 0030 should say `yes`. This also answers whether 0007 onwards reached production.
4. Check the nightly jobs: `select jobname, schedule from cron.job;` lists `purge-call-transcripts`, `end-lapsed-sessions` and `purge-expired-data`.
5. Set `PRIVACY_CONTACT_EMAIL` in `src/lib/privacy.ts` when there is an address.
6. Monitoring: follow [monitoring.md](monitoring.md) (tracker, secrets, test alert, uptime checks).

### After Phase 4: demo and pilot readiness (2026-10-16, branch `claude/festive-curie-inphrm`)

| Task | Status |
|---|---|
| Re-score readiness | Done: the audit page's scorecard is updated (link at the top of this file) |
| Close the small findings left | Done: 17 (0029), 18, 26, 27 (0030) |
| One go-live checklist | Done: [go-live.md](go-live.md) |
| Demo runbook | Done: [demo.md](demo.md) |

**Production has none of migrations 0007 to 0030** (2026-10-16, `check-migrations.sql` run by the owner in Lovable's SQL editor). Lovable doesn't apply migration files that arrive from GitHub; it only applies changes its own agent makes. That answers the open question about how Lovable treats our migrations. `dev/supabase/apply-0007-0030.sql` applies all of them in one transaction (rehearsed on a local copy at 0006 with sample data: every check says yes and all 1,820 database tests pass). The owner applied it the same day; the checks after it found the three nightly jobs, every account with a university, and no platform admins. From now on, every new migration is applied by pasting it into the SQL editor. An earlier note here said production had 0022 because it answered `email_domain_allowed`; that was wrong, since 0000 already defined that function.

### Owner feedback and EU rules (2026-10-16, branch `claude/festive-curie-inphrm`)

| Change | Status |
|---|---|
| Display names required | Done (0031): sign-up no longer uses the start of the email address (usually a student number) as the name, onboarding asks "What should people call you?", existing student-number names are cleared so those people are asked once, and a trigger refuses a blank name or the email's start. The DPIA already said student numbers aren't collected; the old default contradicted it |
| Discussions grouped by sender | Done: one name and avatar per run of messages, a new group after 7 minutes or a new day, date lines, newest message kept in view (`src/lib/message-groups.ts`, tested) |
| Admin page | Done: tabs (Societies, Reports, People, Activity, University), searchable society list with an Active/Archived filter, committees open per row |
| Settings page | Done: one Profile section with email, university and roles; Interests; Notifications with descriptions; Your data and account (download, sign out, delete) |
| Terms of use | Done: `/terms`, linked from the sign-in card, the welcome footer, the account menu, Settings and the suspension notice. Needs a lawyer's review (go-live step 22) |
| Cookies | Done: `/privacy#cookies` lists everything on the device (`DEVICE_STORAGE`); all strictly necessary, so no banner. The guest call name moved to session storage |
| Digital Services Act | Done (0032): removing someone else's message tells the author what, by whom and why; the terms cover rules, reporting illegal content and moderation |
| AI Act labelling | Done: AI-written society suggestions now say "Written by AI" (recaps, answers and proposals already did) |

Applied to production with `dev/supabase/apply-0031-0032.sql` on 2026-10-16 (go-live step 2b): 4 people had a student-number name and are asked for a name at their next visit.

### Alerts, logging and bot protection (2026-10-16, branch `claude/festive-curie-inphrm`)

| Change | Status |
|---|---|
| Structured server log | Done: `log()` in `monitoring.server.ts`, one JSON line per event; every server function call logged by middleware (name, milliseconds); failing or slow ones (over 5 s, 10 s for AI functions), AI fallbacks and AI pauses go to the error tracker as warnings or errors, tagged by area and function. Checked with a stand-in tracker: a test alert arrives as an error, a refused call as a warning tagged with its function |
| `/admin` → System | Done: platform admins see whether error alerts, uptime checks, AI and calls are set up, sign-in links sent and used in the last 24 hours, and the nightly jobs' last runs (0033, `nightly_job_runs`), and can send a test alert without a terminal |
| Bot check on sign-in (finding 7) | Cloudflare Turnstile, with the site key in `.env` since 2026-10-16. Checked with Cloudflare's test key: invisible, and the token goes with the sign-in request. Enforcement needs the secret key in Lovable Cloud's auth settings, which Lovable's docs don't mention (go-live step 19) |
| Sentry in the privacy notice | Done, ahead of the owner setting it up (EU region) |
| Sign-in emails without budget | Lovable's custom sender needs a paid plan as well as a domain; the options without either are in [sign-in-email-bug.md](sign-in-email-bug.md#without-a-domain-or-a-paid-plan) |
| Video calls | Work in production (the owner, 2026-10-16) |

### Phase 5: when demand justifies it

Realtime notifications, per-page loading and pagination, SSO per university, email digests, analytics for societies officers, links into official membership systems.

## Milestones

What's left for each, in order, is in [go-live.md](go-live.md) (2026-10-16).


- **TU Dublin demo:** finish T1.1 (domain and templates), then roll out Phases 1 and 2 (T2.4 is done).
- **Trinity or UCD demo:** T2.1 and Phase 3 are done in code (2026-10-16). Still needed: that university's society data, its domains and an admin set up in `/admin`, and the sign-in email wording (Phase 3 rollout, step 5).
- **Limited pilot:** all of Phases 0 to 4. Phase 4's code is done (2026-10-16); what's left is outside the code: the DPO's review and decisions, the agreement, provider confirmations, the privacy contact, monitoring and staging accounts, CAPTCHA and the custom sending domain.
