# Returning users don't get the sign-in email

**Status (2026-10-16):** cause found (Microsoft 365 quarantines the emails as spam). App side fixed and merged (Phase 1), and production links now last 10 minutes. The rest needs the custom sending domain and templates in Lovable Cloud (checklist below). Since Phase 4, `/api/health/sign-in` notices when sign-in links go out but aren't used, which is what this bug looked like ([monitoring.md](monitoring.md)), and failed sends from `/welcome` reach the error tracker once it's set up.

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

**Done in code (branch `phase-1`, 2026-10-16):**

- `signInError` in `src/lib/auth.tsx` replaces `friendly()`, so errors come from Supabase's error codes (unit-tested in `src/test/sign-in-errors.test.ts`).
- The "Check your inbox" screen says the link lasts 10 minutes, points to Junk and to Microsoft quarantine, and has "Resend link" with a 60 s countdown.
- New page `/auth/confirm` (`src/routes/auth.confirm.tsx`). Links can now point at our own site, which Lovable lists as a deliverability factor. The token is used only when the person presses Continue, so mail scanners that open links can't use it up. Used or expired links get a clear message and a "Get a new link" button.
- The wording we want is in `dev/supabase/templates/` (`magic-link.html`, `confirm-signup.html`) with the subjects "Your SocConnect sign-in link" and "Confirm your SocConnect account". It names SocConnect and TU Dublin, says why the email arrived and how long the link lasts, and avoids "Sign in to your account". The local stack sends these, and `bun run db:check-sign-in` follows their links.
- 10-minute links in the local stack (`otp_expiry = 600`). Checked locally: a 9-minute-old link signs in, an 11-minute-old one is refused as expired.

**To do in Lovable Cloud:**

1. **Done 2026-10-16 (by the owner):** Auth settings → Email OTP expiration = **600** seconds, so production links last 10 minutes, as the app says.
2. **Custom domain** (Cloud → Emails): enter the domain. Lovable creates a sender subdomain (default `notify`, so for example `noreply@notify.<domain>`) and shows the DNS records to add: a TXT record for verification and NS records that delegate the subdomain to Lovable (add them inside the domain's DNS zone; don't change the domain's nameservers at the registrar), plus `_dmarc` if you turn on "Show as sent from @<domain>". Lovable handles SPF and DKIM. Verification takes a few hours, up to 72.
3. **Templates** (Cloud → Emails → Auth emails → Customize auth emails): this generates the six templates as React Email files in the repo; ask Lovable "Show me my email template files" for the path. Change Magic link and Confirm signup to the wording and subjects in `dev/supabase/templates/`. If the template data includes the token hash, point the button at `<site URL>/auth/confirm?token_hash=<hash>&type=email`; otherwise keep Lovable's link (the page is ready either way). Publish the app so the templates go live.
4. **Auth settings → Site URL and Redirect URLs:** the Site URL must be the published app address, because `/auth/confirm` links are built from it. List the published domain in Redirect URLs.
5. **Test** with real `@mytudublin.ie` mailboxes, one new and one returning account. Check the inbox, then quarantine.
6. **Ask TU Dublin IT** to allow the new sender domain in their anti-spam policy. Don't ask them to allow `auth.lovable.cloud`: every Lovable app can send from it.
7. New sending domains warm up over weeks. Keep these emails transactional and the sender address the same.

**Until then (demos):** the student can release the message from the quarantine page. Adding `no-reply@auth.lovable.cloud` to Outlook's Safe senders may let later emails through, because Microsoft honours safe senders for ordinary spam verdicts. That's untested here, and it also lets other Lovable apps' mail through for that student.

## Without a domain or a paid plan

Checked 2026-10-16 in Lovable's docs: a custom email sender needs a **paid Lovable plan** as well as a domain; free plans always use Lovable's shared sender. So these are the options while there's no budget, best first:

1. **For a demo: sign people in beforehand.** Sessions last until someone signs out (a year at most), so a link released from quarantine once is enough. Keep https://security.microsoft.com/quarantine open in case someone signs in live ([demo.md](demo.md)).
2. **Safe senders, per student:** in Outlook, add `no-reply@auth.lovable.cloud` to Safe senders. Microsoft honours it for ordinary spam verdicts, not for phishing ones; untested here. Fine for a small demo group, not for a pilot.
3. **Ask TU Dublin IT for a narrow allow rule:** an Exchange rule that lets through mail from `no-reply@auth.lovable.cloud` only when it links to the published app's address (`student-society-spot.lovable.app`). Free, and narrower than allowing the shared sender outright, which IT should refuse because every Lovable app can send from it. Worth asking as part of a pilot conversation.
4. **"Sign in with Microsoft"** would skip email altogether for TU Dublin accounts, but nobody has checked that Lovable's broker refuses other organisations' Microsoft accounts claiming a university address ([go-live.md](go-live.md#microsoft-sign-in)). Don't lean on it until that's checked.
5. **For a pilot: make it the university's cost.** A domain is about €10–20 a year (or free for a year through the GitHub Student Developer Pack, at name.com); the paid Lovable plan is the bigger cost. A university running a pilot can reasonably cover both, or give a subdomain of its own.

Six-digit codes instead of links wouldn't help: the email carrying the code is quarantined just the same.

**Regression check:** `bun run db:check-sign-in` for our code; one real `@mytudublin.ie` mailbox (new and returning account) before every demo, since quarantine can't be simulated locally.
