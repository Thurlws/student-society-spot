# Sub-processors

Draft, 2026-10-16. Every company that receives personal data from SocConnect, checked against the code at the date above. "To confirm" means we haven't seen the provider's own documentation or settings for it yet.

When a university pilots SocConnect, the university is the controller, the SocConnect team is its processor, and the companies below are sub-processors (GDPR Article 28(2) and (4)). The processing agreement asks the university for general authorisation to use them, with notice before any change.

## In use

| Provider | What it does for SocConnect | Personal data it gets | Where | Status |
|---|---|---|---|---|
| **Lovable** (Lovable Labs Incorporated) | Hosts the web app and builds it from GitHub. Runs the backend, Lovable Cloud, which is a managed Supabase project: the Postgres database, sign-in, scheduled jobs | Everything SocConnect stores (see the notice's "What we collect"), plus request logs (IP address, browser, pages) | To confirm: the Lovable Cloud project's region, where the app is served from, and how long request logs are kept | To confirm: Lovable's data processing agreement and its own sub-processors (Supabase, the hosting network) |
| **Lovable's email service** | Sends the sign-in and confirmation emails | Email address, the sign-in link | To confirm | Moving to a custom sending domain ([context/sign-in-email-bug.md](../../context/sign-in-email-bug.md)). Record the provider behind it when that's done |
| **OpenAI**, through the Lovable AI gateway (`src/lib/ai.server.ts`) | Transcribes caption clips (`openai/gpt-transcribe`), writes call recaps and answers questions about them, explains society suggestions, drafts collaboration proposals and answers "Ask SocConnect" (`openai/gpt-6-astra`) | Seven-second audio clips of speech from people who turned captions on, call transcripts, questions people ask, and society, event and announcement text the person can already see | United States | To confirm: the transfer mechanism (EU-US Data Privacy Framework or standard contractual clauses), and how long Lovable's gateway and OpenAI keep requests. The app asks for responses not to be stored (`store: false`) |
| **LiveKit** (LiveKit Cloud) | Carries video calls between browsers | Display name, an internal identity, camera, microphone and the captions people send in a call. Not recorded by SocConnect | To confirm: the project's region | To confirm: LiveKit's data processing agreement. Only used when `LIVEKIT_*` variables are set |

| **Sentry** (Functional Software, Inc.), EU region | Error alerts (roadmap T4.4): server errors, warnings (a failing feature, AI out of credits, a slow or failing server function), browser crashes | Error reports: the error and its stack, the page's path, the server function's name. Scrubbed of email addresses, tokens and keys; never names, message text, request bodies or ids of people | EU (Frankfurt), chosen when the account is created | Added 2026-10-16 as the owner sets it up. To confirm: Sentry's data processing agreement and its transfer terms for support access from the US. Nothing is sent until `SENTRY_DSN` is set |

## Not sub-processors, but worth knowing

| Who | What happens | Notes |
|---|---|---|
| The university's societies website (`societies.tudublin.ie` for TU Dublin) | Society logos and banners load from it, so it sees each visitor's IP address | It's the university's own site. Copying the images into SocConnect would stop this, once the right to republish them is confirmed |
| The university's Microsoft tenant | People who use "Sign in with Microsoft" sign in at their university's Microsoft account, through Lovable's sign-in broker | The university's own identity service. The broker's setup is unverified ([context/architecture.md](../../context/architecture.md)) |
| Google Fonts | Not used since 2026-10-16. The fonts are bundled with the app | Before then, every visit sent the visitor's IP address to Google |

## Planned

| Provider | For | Status |
|---|---|---|
| An uptime checker | Polls the public `/api/health` endpoint | Sees no personal data |
| **Cloudflare** (Turnstile) | Checks the sign-in form is used by a person (audit finding 7). Code done 2026-10-16; on once `VITE_TURNSTILE_SITE_KEY` is set, and the notice then lists it | The visitor's IP address and browser characteristics, on the sign-in page only. Cloudflare says Turnstile sets no cookies and keeps IP addresses for a few weeks at most | To confirm: Cloudflare's data processing agreement and the transfer mechanism (it's certified under the EU-US Data Privacy Framework) |
