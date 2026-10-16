# Demo runbook

Written 2026-10-16. For showing SocConnect to a university, a Students' Union or a society. The production database holds real students' data, so a demo uses real accounts and real (or clearly yours) content, never invented people. Once staging exists ([staging.md](staging.md)), demos with made-up societies and events belong there.

## The week before

- **Production is up to date.** `main` is published, and [`dev/supabase/check-migrations.sql`](../dev/supabase/check-migrations.sql) says `yes` on every row in Lovable Cloud's SQL editor. The app's edit, cancel, moderation, admin and privacy features need those migrations; without them parts of the app fail to load ([go-live.md](go-live.md), step 2).
- **Sign-in reaches a real mailbox.** With a real `@mytudublin.ie` address, sign in once as a returning account and once as a new one. Check the inbox, then Junk, then quarantine (https://security.microsoft.com/quarantine). Until the custom sending domain is set up, expect quarantine ([sign-in-email-bug.md](sign-in-email-bug.md)).
- **Accounts**, each signed in on its own browser profile:
  - a student account;
  - a committee member of a society you run or have permission to use (seats come from an invite on `/admin`);
  - a platform or university admin, for `/admin`.
- **Content** in that society, made by its committee: one upcoming event, one pinned announcement, a message in `#general`. An empty society looks broken; a fake one misleads.
- **Calls:** `/calls` says either "Live calls are on" or "Calls aren't available yet". If it's the second, leave calls out of the demo.
- **AI:** open Society Pulse and ask for recommendations. If AI is off (credits ran out), it comes back by itself 15 minutes after credits are topped up.
- **Health:** `https://<published site>/api/health` says `{"status":"ok"}`.

## An hour before

- Sign in on every device and browser profile now. Sessions last; links last only 10 minutes, and email can be slow.
- Have the quarantine page open in a tab in case anyone signs in live.
- One browser window per role, other tabs closed, notifications off.

## The demo, about 10 minutes

1. **Welcome page:** only university addresses get in, and every account belongs to the university of its address. Accounts that haven't signed in for a year need the mailbox again.
2. **Student:** Discover societies → filter by interest or campus → a society page (official logo and banner) → Join society, or Request to join where the committee approves members.
3. **Events:** register, see places left, Add to calendar (.ics).
4. **Committee:** approve the join request; post an announcement; create an event, then change its time (registered people are notified) and show a cancelled event stays listed and refuses registrations.
5. **Moderation:** as the student, report a message; as the committee, remove it from the reports queue.
6. **Society Pulse:** societies placed by the interests they list; AI recommendations from real records.
7. **Calls** (only if live): a drop-in room; captions start off and each person turns their own on; the recap afterwards.
8. **Admin:** `/admin` → societies and committees, Import societies (CSV), People (suspend and lift), Activity (who changed what).
9. **Privacy:** `/privacy`, and Settings → Your data → Download my data and Delete my account.

For another university (Trinity, UCD): they'd get their own university in `/admin`, their own email domains, societies from a spreadsheet their Students' Union provides, and admins who see only their university. Don't show TU Dublin students' data as an example of isolation; say what the tests prove (`university_isolation.test.sql`, the permission matrix's student at another university).

## If something goes wrong

| What happens | Do this |
|---|---|
| The sign-in email doesn't arrive | Check quarantine and release it; otherwise switch to a profile that's already signed in |
| "This link has expired or was already used" | Links work once, for 10 minutes. Ask for a new one |
| `/calls` says calls aren't available | LiveKit isn't configured in production. Move on |
| AI says it's unavailable | Credits or the gateway. Plain recaps still work. Move on |
| A page shows an error | Reload once. If error tracking is set up, the error is already reported ([monitoring.md](monitoring.md)) |

## Don't claim

- Single sign-on with the university (it's email links; Microsoft sign-in is unverified, see [go-live.md](go-live.md)).
- Live chat: discussions refresh every minute.
- That it replaces the university's official membership system: it links to it.
- That a data protection officer has approved it, until one has ([docs/privacy/dpia.md](../docs/privacy/dpia.md)).
