# Returning users don't get the sign-in email

**Status (2026-10-15):** cause found. Microsoft 365 quarantines the sign-in emails as spam. Fix is roadmap task T1.1.

## Symptom

A user who already has an account enters their email on `/welcome`, sees "Check your inbox", and never receives the sign-in **link**, not even in Junk. It keeps happening to existing accounts.

The app sends a link, not a code. The first audit report said "code"; that was a wording mistake in the bug report.

## Cause (confirmed 2026-10-15)

The emails are sent, and TU Dublin's Microsoft 365 puts them in **quarantine**, which is separate from Junk. A student's quarantine page (https://security.microsoft.com/quarantine) showed three of them that day:

| Field | Value |
|---|---|
| Subject | Sign in to your account |
| Sender | `no-reply@auth.lovable.cloud` (Lovable Cloud's shared default sender) |
| Quarantine reason | Spam |
| Policy | Anti-spam policy |
| Release status | Needs review (expires after 30 days) |

Likely reasons: a shared sending domain used by every Lovable app, and a "Sign in to your account" subject with a login link, which matches common phishing patterns.

Still unknown: whether new users' "Confirm signup" emails are quarantined too. Test with a fresh `@mytudublin.ie` address that has never signed up. The fix is the same either way.

## How sign-in works

1. `SignInCard.sendLink` in `src/routes/welcome.tsx:79-88` checks the domain (`emailAllowed`, `src/lib/auth.tsx:6-7`) and calls `supabase.auth.signInWithOtp({ email, options: { emailRedirectTo: window.location.origin } })`. The browser talks to Supabase Auth in Lovable Cloud directly. No server code of ours runs.
2. Supabase Auth (`MagicLink` handler in supabase/auth) branches:
   - new or unconfirmed address: runs sign-up, which inserts into `auth.users` (our triggers `enforce_email_domain` and `handle_new_user` fire) and sends the **Confirm signup** template;
   - existing confirmed account: sends the **Magic link** template. Our triggers are INSERT-only, so nothing of ours runs.
   - both: 60 s per-user cooldown (hosted default) and a project-wide hourly email cap.
3. On success the card shows "Check your inbox. We sent a sign-in link…". Errors are shown via `friendly()` (`welcome.tsx:69-71`), which rewrites anything containing "database error" or "tu dublin" into "Please use your TU Dublin email".

## Ruled out along the way

`npm run db:start` then `npm run db:check-sign-in` (script: `dev/check-sign-in-email.mjs`). Local stack = same 7 migrations, Supabase default templates, confirmations on, 60 s cooldown. Results on 2026-10-15:

| Case | Result |
|---|---|
| New address | 200, email "Confirm your email address" |
| Open the link | session issued |
| Same address again (returning, confirmed) | 200, email "Your sign-in link" |
| Again immediately | 429 `over_email_send_rate_limit`, "For security purposes, you can only request this after 58 seconds." (the card shows this text) |
| Never-confirmed account, again after 62 s | 200, confirmation email re-sent |
| Non-university address | 500 "Please use your TU Dublin email (@mytudublin.ie)" from the trigger |

So our code and migrations send the email. In production the card showed "Check your inbox", which rules out the cooldown and hourly cap (both show an error).

## Fix

**Real fix (roadmap T1.1):**

1. Set up a custom sending domain in Lovable Cloud (Cloud → Emails: managed email or a verified custom domain) on a domain we own, with SPF, DKIM and DMARC records. This also lifts the hourly email cap.
2. Ask TU Dublin IT to allow that domain in their anti-spam policy for the pilot. Don't ask them to allow `auth.lovable.cloud`: every Lovable app can send from it.
3. Make the template clearly ours: a subject like "Your SocConnect sign-in link" and a body that names SocConnect and TU Dublin.
4. Code changes: replace `friendly()` with messages keyed on `error.code`; add "Resend" with a 60 s countdown; on the "Check your inbox" screen, tell students to check Junk and quarantine if nothing arrives in two minutes. 6-digit codes (`verifyOtp({ email, token, type: "email" })`) are optional; they survive Microsoft Defender opening links before the student does.

**Until then (demos):** the student can release the message from the quarantine page. Adding `no-reply@auth.lovable.cloud` to Outlook's Safe senders may let later emails through, because Microsoft honours safe senders for ordinary spam verdicts. That's untested here, and it also lets other Lovable apps' mail through for that student.

**Regression check:** `npm run db:check-sign-in` for our code; one real `@mytudublin.ie` mailbox (new and returning account) before every demo, since quarantine can't be simulated locally.

## Lovable Cloud settings (optional now)

No longer needed to find the cause. Rows 1-3 matter for the fix.

| # | Where | Record | Answer |
|---|---|---|---|
| 1 | Cloud → Emails → Confirm signup | Subject and body | |
| 2 | Cloud → Emails → Magic link | Subject and body | Subject seen in quarantine: "Sign in to your account" |
| 3 | Cloud → Emails | Managed email or custom domain set up? Sender address | Sender seen: `no-reply@auth.lovable.cloud` (default, no custom domain) |
| 4 | Auth settings → Advanced | Rate limit for sending emails (per hour) | |
| 5 | Auth settings | Site URL and redirect URLs; is the published domain listed? | |
