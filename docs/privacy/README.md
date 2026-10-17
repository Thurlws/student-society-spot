# Privacy pack

Written 2026-10-16 for roadmap task T4.1. These are working drafts for a university's Data Protection Officer (DPO) to review before a pilot. They describe what the code does today. They are not legal advice, and nothing here is final until the DPO and the SocConnect team have agreed it.

| File | What it is | Who it's for |
|---|---|---|
| [`/privacy` in the app](../../src/routes/privacy.tsx) | The privacy notice students read, including what's stored on their device (cookies section). Contacts, retention periods, providers and device storage come from [`src/lib/privacy.ts`](../../src/lib/privacy.ts) | Students, the DPO |
| [`/terms` in the app](../../src/routes/terms.tsx) | The terms of use (added 2026-10-16): who can use SocConnect, the rules, reporting illegal content and how moderation works, as the EU Digital Services Act asks, and the AI labelling the AI Act asks for | Students, the university's legal office |
| [sub-processors.md](sub-processors.md) | Every company that touches personal data, what it gets, where, and what still needs confirming | The DPO, procurement |
| [retention.md](retention.md) | How long each kind of data is kept, and how it is deleted | The DPO |
| [dpia.md](dpia.md) | Draft data protection impact assessment: what is processed, the risks and what reduces them, and open decisions | The DPO |
| [processing-agreement.md](processing-agreement.md) | Template for the agreement between a university (controller) and the SocConnect team (processor), GDPR Article 28 | The DPO, the university's legal office |

## Before a pilot

Things only the owner or the university can do. The code is ready for them.

1. **A privacy contact address.** Set `PRIVACY_CONTACT_EMAIL` in `src/lib/privacy.ts`. Until then the notice says no address exists yet.
2. **Who the SocConnect team is legally.** The processing agreement needs a named party (a person, a company or a club) and an address.
3. **Confirm the providers' regions and terms** in [sub-processors.md](sub-processors.md): Lovable Cloud's database region, Lovable's data processing agreement, which service sends sign-in emails, LiveKit's region, and the transfer terms for AI requests that go to OpenAI in the United States.
4. **Decide the open questions** at the end of [dpia.md](dpia.md), above all the legal basis for memberships of societies that reveal religion, ethnicity, sexuality, health or disability (GDPR Article 9).
5. **Agree the retention periods** in [retention.md](retention.md). Changing one means changing `purge_expired_data` (migration 0026) and `RETENTION` in `src/lib/privacy.ts` together.
6. **Fill in the university's details** in the processing agreement and attach the current sub-processor list.
7. **A lawyer reads the terms of use** (`/terms`) and the notice together, and `OPERATOR` in `src/lib/privacy.ts` gets the team's legal name and address (the e-Commerce Directive asks for them).
8. **Decide who answers reports of illegal content** sent to the contact address, and how fast (Digital Services Act, article 16). The terms promise a confirmation and a decision.

## Cookies and device storage (2026-10-16)

SocConnect sets no cookies and has no analytics, advertising or tracking. It keeps three things on the device, all strictly necessary for what the person asked for, so the ePrivacy rules need no consent banner: the sign-in session (local storage), which channel messages they've already seen, for the new-message counts (local storage, channel ids and times only, cleared on sign-out; added 2026-10-17), and the name a guest typed to join a call (session storage, gone when the tab closes). The list is `DEVICE_STORAGE` in `src/lib/privacy.ts`, shown at `/privacy#cookies`. Adding anything that isn't strictly necessary (analytics, a third-party script, a chat widget) needs a consent step first, and an update here.

Cloudflare Turnstile, the bot check on the sign-in form, loads a script from Cloudflare on the sign-in page once `VITE_TURNSTILE_SITE_KEY` is set. It's a security measure for the service the person asked for, and Cloudflare says it sets no cookies, so it needs no consent either; the notice and [sub-processors.md](sub-processors.md) name it automatically while it's on.

## Keeping it current

- A change that collects new personal data, sends it somewhere new or keeps it longer updates the notice, these files and the DPIA risk table in the same pull request.
- A new provider goes in `PROVIDERS` in `src/lib/privacy.ts` and in [sub-processors.md](sub-processors.md) before it is used. Under the processing agreement, the university is told first.
- Date every change at the top of the file you change.
