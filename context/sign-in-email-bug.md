# Returning users don't get the sign-in email

**Status (2026-10-16):** cause found (Microsoft 365 quarantines the emails as spam). App side fixed on branch `phase-1`; the rest needs the custom sending domain and settings in Lovable Cloud (checklist below).

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

1. **Now, no domain needed:** Auth settings → Email OTP expiration = **600** seconds. Until this is set, production links last Supabase's default of 1 hour, while the app already says 10 minutes.
2. **Custom domain** (Cloud → Emails): enter the domain. Lovable creates a sender subdomain (default `notify`, so for example `noreply@notify.<domain>`) and shows the DNS records to add: a TXT record for verification and NS records that delegate the subdomain to Lovable (add them inside the domain's DNS zone; don't change the domain's nameservers at the registrar), plus `_dmarc` if you turn on "Show as sent from @<domain>". Lovable handles SPF and DKIM. Verification takes a few hours, up to 72.
3. **Templates** (Cloud → Emails → Auth emails → Customize auth emails): this generates the six templates as React Email files in the repo; ask Lovable "Show me my email template files" for the path. Change Magic link and Confirm signup to the wording and subjects in `dev/supabase/templates/`. If the template data includes the token hash, point the button at `<site URL>/auth/confirm?token_hash=<hash>&type=email`; otherwise keep Lovable's link (the page is ready either way). Publish the app so the templates go live.
4. **Auth settings → Site URL and Redirect URLs:** the Site URL must be the published app address, because `/auth/confirm` links are built from it. List the published domain in Redirect URLs.
5. **Test** with real `@mytudublin.ie` mailboxes, one new and one returning account. Check the inbox, then quarantine.
6. **Ask TU Dublin IT** to allow the new sender domain in their anti-spam policy. Don't ask them to allow `auth.lovable.cloud`: every Lovable app can send from it.
7. New sending domains warm up over weeks. Keep these emails transactional and the sender address the same.

**Until then (demos):** the student can release the message from the quarantine page. Adding `no-reply@auth.lovable.cloud` to Outlook's Safe senders may let later emails through, because Microsoft honours safe senders for ordinary spam verdicts. That's untested here, and it also lets other Lovable apps' mail through for that student.

**Regression check:** `bun run db:check-sign-in` for our code; one real `@mytudublin.ie` mailbox (new and returning account) before every demo, since quarantine can't be simulated locally.
