# SocConnect

A web app for university societies. Students find societies, join them, register for events and get announcements in one feed. Committees review membership requests, post updates, run events, answer member requests and hold video calls with AI recaps.

It started as a hackathon project at TU Dublin, which is still the only university on it. Universities are data: each has its email domains, members and admins, and people only see their own university's societies.

> **Status:** prototype with a real backend, not yet piloted. Known open problems and the plan are in [`context/`](context/README.md). Start there if you're picking up the work.

## How it fits together

- **Frontend:** React 19, TypeScript, TanStack Router and Start (server rendering), Tailwind CSS 4, shadcn/ui.
- **Backend:** Supabase (Postgres and Auth), managed by Lovable Cloud. The browser reads and writes the database directly with the signed-in user's token. Row-level security policies and SQL functions in [`drizzle/migrations/`](drizzle/migrations) enforce every permission and business rule, so the browser is never trusted.
- **Server functions** in `src/lib/*.functions.ts` handle the parts that need secrets: LiveKit call tokens and guest links, AI recaps, captions and society recommendations.
- **Sign-in:** an emailed sign-in link (`supabase.auth.signInWithOtp`). Only addresses at a listed university domain can sign up (`university_domains`; for TU Dublin `@mytudublin.ie` and `@tudublin.ie`); a database trigger enforces this.

[`AGENTS.md`](AGENTS.md) has the design decisions in more detail.

## Requirements

- Node.js 22 or newer (we use 24 in CI and 26 locally)
- [Bun](https://bun.sh) as the package manager (`bun.lock`, also used by Lovable). npm works with the same `package.json`, but don't commit a `package-lock.json`.
- Docker, only for the local database

## Run it

```bash
bun install
bun run dev
```

The app runs on http://localhost:8080.

Out of the box it talks to the **production** Lovable Cloud backend, because the committed `.env` holds its public URL and key. That database has real students in it. Use the local database below for anything beyond looking around.

## Local database

The Supabase CLI runs through `npx`, pinned to one version, so there's nothing to install apart from Docker.

```bash
bun run db:start          # first run pulls the Docker images, takes a few minutes
bun run db:reset          # rebuild the database from drizzle/migrations
bun run db:test           # pgTAP tests in dev/supabase/tests
bun run db:check-sign-in  # check that new and returning users get a working sign-in email
bun run db:stop
```

`db:start` replays all migrations in `drizzle/migrations/` (in filename order) and prints the local URLs and keys. Run `bun run supabase status` to see them again. To point the app at the local stack, create `.env.local` (git ignores it, and it overrides `.env`):

```bash
VITE_SUPABASE_URL=http://127.0.0.1:54321
VITE_SUPABASE_PUBLISHABLE_KEY=<publishable key from db:start>
SUPABASE_URL=http://127.0.0.1:54321
SUPABASE_PUBLISHABLE_KEY=<publishable key from db:start>
SUPABASE_SERVICE_ROLE_KEY=<secret key from db:start>
```

Local sign-in emails never leave your machine. Read them in Mailpit at http://127.0.0.1:54324.

The local stack's settings are in `dev/supabase/config.toml`. The `supabase/config.toml` at the repo root belongs to Lovable Cloud, so leave it alone.

## Checks

```bash
bun run typecheck
bun run test
bun run build
bun run lint     # includes Prettier formatting; `bun run format` fixes it
bun run db:test  # needs the local database (bun run db:start)
bun run e2e      # browser journeys; needs the local database too
```

CI runs all of these on every pull request and every push to `main` (`.github/workflows/ci.yml`), in three jobs: `check`, `database` and `journeys`.

To see which migrations a database has (production, staging), run [`dev/supabase/check-migrations.sql`](dev/supabase/check-migrations.sql) in its SQL editor.

`dev/supabase/tests/permission_matrix.test.sql` tries every table and every database function as a signed-out visitor, a student, an applicant, a member, the society's committee, another society's committee, a platform admin, a student at another university and a university admin. When you add a table or a function that signed-in users can call, add rows for it there. The test fails until you do.

### Browser journeys

`e2e/` holds Playwright tests that sign in through the real email flow (read from Mailpit) and walk the main journeys: signing up and back in, joining and approval, events, announcements and moderation.

```bash
bun run db:start
npx playwright install chromium   # once
bun run e2e
```

They always start their own dev server pointed at the local database, and refuse to run if anything is already listening on port 8080, so they can't touch production. Each run deletes and recreates its own `e2e-` accounts and societies. A failed run leaves screenshots and traces in `test-results/`; open a trace with `npx playwright show-trace <file>`.

## Environment variables

| Variable | Where it lives | Used for |
|---|---|---|
| `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY` | `.env` (committed, public) | Browser database client |
| `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` | `.env` (committed, public) | Server functions acting as the signed-in user |
| `SUPABASE_SERVICE_ROLE_KEY` | Lovable Cloud secrets | Server functions that bypass row-level security: call tokens, recaps, AI quotas |
| `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET` | Hosting environment | Live video calls. Without them, calls show "not available". |
| `LOVABLE_API_KEY` | Provided by Lovable hosting | AI recaps, captions and recommendations. Without it, recaps fall back to a keyword summary. |
| `SENTRY_DSN`, `SENTRY_ENVIRONMENT` | Lovable Cloud secrets | Server and browser errors to an EU error tracker ([`context/monitoring.md`](context/monitoring.md)). Without them, errors only reach the server log. |
| `MONITORING_TOKEN` | Lovable Cloud secrets | Lets an uptime monitor read `/api/health/sign-in` and send a test alert. `/api/health` itself is public. |

`.env` is committed on purpose: published builds read it and break without it. It must only ever hold public values. Put secrets and local overrides in `.env.local`. [`.env.example`](.env.example) lists the server-only variables.

## Database changes

Migrations are plain SQL files in `drizzle/migrations/`. Drizzle is only the migration runner (`drizzle/schema.ts` is intentionally blank), and Lovable applies the migrations to Lovable Cloud.

To add one by hand, create the next numbered file, add a matching entry to `drizzle/migrations/meta/_journal.json` (plus a copy of the last snapshot), and run `bun run db:reset && bun run db:test` to check it applies on a clean database. Then confirm in Lovable that it reached production. We haven't verified how Lovable picks up hand-written migrations pushed from GitHub.

Supabase grants every new table and function to signed-out and signed-in users by default. Turn on row-level security for new tables, and revoke `execute` from `public, anon` on every new `security definer` function (from `authenticated` too if the app shouldn't call it). Add new columns and functions to `src/integrations/supabase/types.ts` by hand; Lovable regenerates that file once the migration reaches production.

## Deploying

The app is hosted by Lovable, which publishes from the GitHub branch it is connected to (`main`). We plan to stay there until a university pilot provides infrastructure. [`context/hosting.md`](context/hosting.md) lists everything that changes when we leave.

The build picks its target from the environment: Cloudflare Workers by default, Vercel when built on Vercel, and a plain Node server with `NITRO_PRESET=node-server` (then `node .output/server/index.mjs`). On any host other than Lovable, set every server variable from the table above in the host's environment, because the built server doesn't read `.env`.

## Official TU Dublin society data

The society directory comes from the public [TU Dublin Societies site](https://societies.tudublin.ie/societies/). A Scrapy crawler kept outside this repo (`student-society-spot-extractor/tud_scrapy`) collects each society's profile, and `build_socconnect_seed.py` turns the result into `drizzle/migrations/0006_official_tud_societies.sql`. That migration:

- adds official-data columns to `societies` (campus, logo and banner URLs, MyStudentLife join URL, official URL, contact email, links, extra sections, and source tracking fields);
- upserts the 67 societies, matched on `(source, source_id)`, and adds interest tags for recommendations;
- can be regenerated and re-applied. Committee edits to the tagline, description and meeting time survive a refresh, and societies that disappear from the source are never deleted automatically.

Student-number email addresses, phone numbers and committee names from the source site are not imported. Logos and banners are linked from the official site rather than copied, because we haven't confirmed the right to republish them.

## Video calls

Society calls are real multi-person calls when the LiveKit variables are set. Create a project at [LiveKit Cloud](https://cloud.livekit.io) and copy its URL, API key and secret. For local runs, put them in `.env.local`.

- Camera and microphone need HTTPS. Test on the deployed URL; `http://<your-ip>:8080` won't get camera access (only `localhost` is exempt).
- Captions record 7-second audio clips while someone speaks and send them to the server for AI transcription. Spoken and typed lines are shared with everyone in the call and feed the recap. Anyone in the call can switch captions off.
- Committees can create guest links (`/join/<code>`) that expire and have a use limit.

## Privacy and operations

- The privacy notice is at `/privacy`; its contacts, retention periods and providers are in `src/lib/privacy.ts`. The drafts a university's data protection officer needs (providers, retention schedule, impact assessment, processing agreement) are in [`docs/privacy/`](docs/privacy/README.md).
- Admins run their university from `/admin`: societies and committees, an import from a spreadsheet, reported messages, suspensions and an activity log. [`context/onboarding.md`](context/onboarding.md) walks through adding a university.
- Health checks and error alerts: [`context/monitoring.md`](context/monitoring.md). Staging: [`context/staging.md`](context/staging.md).

## Known issues

- Sign-in emails from Lovable's default sender land in Microsoft 365 quarantine at TU Dublin. The fix needs a custom sending domain; see [`context/sign-in-email-bug.md`](context/sign-in-email-bug.md).
- A second university needs its own society data and a decision on the sign-in email wording, which names TU Dublin. See Phase 3 in [`context/roadmap.md`](context/roadmap.md).
- The privacy notice has no contact address yet, and the providers' regions and terms still need confirming ([`docs/privacy/README.md`](docs/privacy/README.md)).
- The October 2026 audit's open items, and what's left before a pilot, are in [`context/roadmap.md`](context/roadmap.md).

## Project layout

```text
src/
  routes/             pages (file-based routing); signed-in pages live in _authenticated/
  components/         app components; ui/ holds generated shadcn components
  lib/api/            the single data layer: loads data, runs database functions
  lib/*.functions.ts  server functions (calls, guest links, AI)
  lib/*.server.ts     server-only helpers (LiveKit, AI gateway)
  integrations/       Supabase and Lovable clients, generated by Lovable (don't edit)
  test/               Vitest tests
drizzle/migrations/   database schema, policies and functions as SQL
dev/                  local Supabase stack, pgTAP tests (dev/supabase/tests) and dev scripts
e2e/                  Playwright journeys
context/              notes for whoever picks up the work next
docs/privacy/         drafts for a university's data protection officer
```

## License

No license has been chosen yet. Add one before anyone outside the team reuses the code.

<!-- LOVABLE:BEGIN -->
> [!IMPORTANT]
> This project is connected to [Lovable](https://lovable.dev). Avoid rewriting
> published git history — force pushing, or rebasing/amending/squashing commits
> that are already pushed — as it rewrites history on Lovable's side and the
> user will likely lose their project history.
>
> Commits you push to the connected branch sync back to Lovable and show up in
> the editor, so keep the branch in a working state.
<!-- LOVABLE:END -->
