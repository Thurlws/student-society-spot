# Privacy pack

Written 2026-10-16 for roadmap task T4.1. These are working drafts for a university's Data Protection Officer (DPO) to review before a pilot. They describe what the code does today. They are not legal advice, and nothing here is final until the DPO and the SocConnect team have agreed it.

| File | What it is | Who it's for |
|---|---|---|
| [`/privacy` in the app](../../src/routes/privacy.tsx) | The privacy notice students read. Contacts, retention periods and providers come from [`src/lib/privacy.ts`](../../src/lib/privacy.ts) | Students, the DPO |
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

## Keeping it current

- A change that collects new personal data, sends it somewhere new or keeps it longer updates the notice, these files and the DPIA risk table in the same pull request.
- A new provider goes in `PROVIDERS` in `src/lib/privacy.ts` and in [sub-processors.md](sub-processors.md) before it is used. Under the processing agreement, the university is told first.
- Date every change at the top of the file you change.
