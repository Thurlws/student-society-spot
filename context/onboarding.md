# Onboarding a university

Written 2026-10-16 (roadmap T4.6). Everything here happens in the app, at `/admin`, without a developer. The steps marked *agreement* come first and aren't in the app.

## 1. Before anything goes in (agreement)

- The university and the SocConnect team sign the processing agreement, and the university's DPO signs off the impact assessment ([docs/privacy](../docs/privacy/README.md)).
- The privacy notice has a contact address (`PRIVACY_CONTACT_EMAIL` in `src/lib/privacy.ts`) and the providers' details are confirmed.
- The university's IT team confirms its email domains, and which are students' and which staff's. Anyone with an address at a listed domain can sign up.
- IT allows SocConnect's sign-in email sender, or students' sign-in emails may land in quarantine ([sign-in-email-bug.md](sign-in-email-bug.md)).
- Decide the sign-in email wording: the templates in `dev/supabase/templates/` say "the app for TU Dublin societies" (roadmap, Phase 3 rollout step 5).
- Get the list of societies from the Students' Union as a spreadsheet. Don't copy it from the university's website without permission. Logos and banners are only linked, and only where the university agrees.

## 2. Create the university (a platform admin)

1. `/admin` → pick any university → **New university**: name, short name, address (lower case, used internally) and the email domains, comma separated.
2. In the **Universities** section, with the new university picked: **University admins** → the email address of each person who will run it, for example Students' Union staff. They become admins the first time they sign in. Their addresses must be at one of the university's domains.

## 3. Bring in the societies (a university admin)

1. `/admin` → **Import societies** → **Download a template**.
2. Fill in one row per society. Only `name` is required; the rest helps:

   | Column | What to put |
   |---|---|
   | `id` | The Students' Union's own id or code for the society. Keep it the same every year: importing again matches on it |
   | `name`, `short_name` | Full name, and up to 30 characters for cards |
   | `slug` | The society's address in SocConnect; made from the short name if empty |
   | `category`, `campus` | As the university uses them |
   | `tagline`, `description`, `meets` | Up to 140, 2,000 and 140 characters. Committees can edit these later, and a later import won't overwrite their changes |
   | `requires_approval` | `yes` if the committee approves new members |
   | `join_url`, `official_url` | The university's join page and official page, `https://` only |
   | `contact_email`, `logo_url`, `banner_url` | Optional; images `https://` only |
   | `interests` | From SocConnect's list (Technology, Gaming, Music, Arts, Sport, Outdoors, Culture, Volunteering, Business, Science, Wellbeing, Food), separated by semicolons. Drives recommendations |

3. Save as CSV, choose it in the import dialog, fix any problems it lists by row number, and **Import**.
4. Check the societies on `/admin`. Set colours there if wanted.
5. For each society, add its committee: **Committee** → email and position → **Add**. People get their seat when they first sign in.

## 4. Check it works

- Sign up with a real student mailbox at the new domain: the email arrives, onboarding works (students outside TU Dublin type their course), the societies show, joining works.
- `/admin` → **Activity** lists the university, the import and the committee invites.

## 5. Every year

- Import the updated society list in September; new societies are added, changed ones updated, and none deleted. Archive societies that have closed (**Archive** on `/admin`).
- Committee handover: remove last year's seats and invite the new committee.
- Accounts that haven't signed in for a year are signed out automatically, and need the university mailbox to come back.

## Running a university

- **Reported messages** and **People** (suspend or lift a suspension) are on `/admin`. A suspended person sees the reason you give.
- **Activity** shows who changed admin rights, committees, societies and moderation, for two years.
- Requests a university admin can't handle in the app go to the SocConnect team: deleting a suspended account, correcting someone's university, or answering a data protection request beyond what Settings → Your data offers. A platform admin does those in Lovable Cloud's SQL editor, and the deletions are logged.

## Ending a pilot

As in the processing agreement: export the university's data if asked (Lovable Cloud → database export, or SQL by university), then delete the university's societies and people, and confirm in writing. A university with societies can't be deleted until its societies are.
