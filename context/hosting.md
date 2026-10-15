# Hosting

## Decision (2026-10-15)

Stay on Lovable (hosting and the Lovable Cloud backend) while we build the prototype and demos. Move off Lovable entirely once a university approves a pilot and provides infrastructure.

Why: moving now would mean setting up hosting, email and AI accounts twice. The university's infrastructure (region, single sign-on, email relay, security review) decides the details of the real deployment, so building for it now would be guessing. The code can already leave: see "Verified" below.

## Rules while we're on Lovable

These keep the eventual move cheap.

1. **No new Lovable-only features.** No Lovable connectors, no extra "managed" sign-in providers, no edge functions that depend on Lovable secrets. Keep every AI call inside `src/lib/ai.server.ts`, so the AI gateway is a one-file swap.
2. **Every schema change is a migration file** in `drizzle/migrations/` (plus its `meta/_journal.json` entry), never a manual edit in Lovable's table editor. Run `bun run db:reset` to check the database still builds from scratch.
3. **Demo data stays fictional or public** (like the official society list). If no real student data goes into Lovable Cloud, the move needs no data export, and there's less GDPR exposure meanwhile.
4. **Still fix the demo blockers** in [roadmap.md](roadmap.md) Phase 1. They don't depend on hosting.
5. **Watch what Lovable's AI editor changes.** It edits the same repo and can regenerate files. `AGENTS.md` points it at `context/`.

## Verified (2026-10-15)

- All 7 migrations apply to a stock Supabase stack (`bun run db:start`).
- A build with `VERCEL=1` produces Vercel output (`.vercel/output`, Node 24 function). Nitro detects Vercel by itself.
- A build with `NITRO_PRESET=node-server` produces `.output/server/index.mjs`; `node .output/server/index.mjs` serves `/welcome` with HTTP 200.
- A plain `bun run build` targets Cloudflare Workers (the Lovable config's default).
- The built server reads its settings from `process.env` only. `.env` is **not** read at runtime, so every server variable must be set in the host's environment.

## Where the code depends on Lovable

| Dependency | Where | What to do when leaving |
|---|---|---|
| Database and auth (Lovable Cloud Supabase) | `.env`, `src/integrations/supabase/*` | New Supabase project: managed in the EU, or self-hosted with Docker on university servers (same stack as `dev/supabase`). Apply `drizzle/migrations` in order. |
| Sign-in emails | Lovable Cloud email settings | Own SMTP or the university's mail relay, own sending domain, own templates. |
| Server secrets (`SUPABASE_SERVICE_ROLE_KEY` etc.) | Lovable Cloud secrets | Lovable says stored secrets aren't exported. Use the new project's keys. |
| AI gateway | `src/lib/ai.server.ts` (`BASE`, `LOVABLE_API_KEY`, models `openai/gpt-6-astra` and `openai/gpt-transcribe`, the "Add credits in Settings → Plans & credits" message at line 194) | Point at our own provider account. `@ai-sdk/openai` is already installed. |
| Microsoft sign-in | `src/integrations/lovable/index.ts`, `src/routes/welcome.tsx:90-94`, package `@lovable.dev/cloud-auth-js` | Use Supabase's own Azure provider with the university's Entra ID tenant, or remove the button. Lovable's managed OAuth only works on Lovable Cloud. |
| Migration runner | `drizzle.config.ts` (`LOVABLE_DB_MIGRATION_URL`) | Point at the new database URL, or apply with `psql`/the Supabase CLI. |
| Build config | `vite.config.ts` (`@lovable.dev/vite-tanstack-config`) | Works as it is (see Verified). Replacing it with a plain Vite config is optional. |
| Lovable-only helpers | `src/integrations/supabase/previewAuthStorage.ts` (only acts on Lovable preview hosts), `src/lib/lovable-error-reporting.ts` (no-op outside the editor), `src/integrations/supabase/cron-auth.ts` (unused) | Harmless elsewhere. Delete during the move. |
| GitHub sync | `.lovable/`, Lovable blocks in `README.md` and `AGENTS.md` | Disconnect the sync in Lovable, then remove them. |
| Transcript purge job | pg_cron in migration 0003 | Comes along with the migrations. Check it exists after a restore. |

Server variables the host must set: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, plus the AI provider key. `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY` are baked in at build time.

## Exit checklist

1. **Agree the setup with the university:** whose servers (VM, their cloud tenancy, or managed Supabase in the EU), region, single sign-on, email relay, backups, who runs it, and the data protection agreement and impact assessment (roadmap T4.1).
2. **Backend:** create the Supabase project or self-hosted stack and apply `drizzle/migrations` in order.
3. **Data:** skip if Lovable Cloud only holds demo data. Otherwise go to Lovable → More → Cloud → Overview → Advanced settings → Export data → Database → Export, download the file from Cloud → Storage, and restore it with `pg_restore` (needs zstd support). Exports are limited to one every 24 hours. Lovable says user accounts are included.
4. **Auth:** site URL, redirect URLs, both email templates, SMTP and sending domain, and SSO if wanted. Replace the Lovable OAuth broker.
5. **AI:** swap `src/lib/ai.server.ts` to our own provider.
6. **App hosting:** set the server variables above, pick the build target (Vercel detects itself; `NITRO_PRESET=node-server` for a VM), and run in an EU region.
7. **Test on a separate deployment:** sign-in for new and returning users, joining, events, calls, recaps. Everyone has to sign in again; sessions don't carry over.
8. **Cut over:** update the public values in `.env`, disconnect Lovable's GitHub sync, and keep Lovable Cloud until the new setup is proven. Removing Lovable Cloud is permanent.
9. **Clean up** the Lovable-only files listed above.

Sources: [Lovable: deploying outside Lovable](https://docs.lovable.dev/tips-tricks/external-deployment-hosting), [Lovable: self-hosting](https://docs.lovable.dev/tips-tricks/self-hosting), [Lovable: Microsoft auth](https://docs.lovable.dev/features/microsoft-auth).
