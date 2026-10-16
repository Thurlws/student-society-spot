# Staging

Written 2026-10-16 (roadmap T4.5). Not set up yet: it needs the owner in Lovable. The repo side is ready: [`dev/supabase/check-migrations.sql`](../dev/supabase/check-migrations.sql) says which migrations a database has, and monitoring takes `SENTRY_ENVIRONMENT=staging`.

## Why

Code reaches production as soon as `main` changes, and migrations reach Lovable Cloud in a way we still haven't watched happen. The database tests and journeys run against a local stack, not against Lovable. A migration that fails or half-applies in Lovable Cloud would first show up on real students' data.

## Recommendation: a second Lovable project

Staging should be a second Lovable project with its own Lovable Cloud backend and its own GitHub repository. What most needs testing is how Lovable applies migrations and publishes the app, and only another Lovable project does that. (A plain Supabase project with Vercel would rehearse leaving Lovable instead; worth doing when a pilot provides infrastructure, see [hosting.md](hosting.md).)

## Setting it up (owner, in Lovable)

1. Create the staging project: remix SocConnect, or create a new project and connect it to a new repository. **Check that it gets its own Lovable Cloud backend** (its own database and sign-in), not production's. If a remix copies data, delete every real person's data from staging before going on.
2. Connect it to a new GitHub repository, for example `Thurlws/student-society-spot-staging`.
3. Secrets in the staging project: `SENTRY_DSN` (the same tracker is fine), `SENTRY_ENVIRONMENT=staging`, its own `MONITORING_TOKEN`. Leave `LIVEKIT_*` out unless calls need testing, and then use a separate LiveKit project.
4. Data: fictional only. The team signs in with their own university addresses. For a staging-only university, add a university in `/admin` with a domain the team controls.
5. Locally, once: `git remote add staging git@github.com:Thurlws/student-society-spot-staging.git`.
6. Note the staging URL here.

## For every change with a migration

From the repository folder, on the pull request's branch, after CI is green:

```bash
git fetch staging
git checkout -B staging-main staging/main
git merge --no-edit <pull-request-branch>
git push staging staging-main:main
git checkout <pull-request-branch>
```

This merges instead of force-pushing, so Lovable's history in the staging repository is kept.

Then, in the staging project:

1. Wait for Lovable to sync, then paste the new migration file into the staging project's SQL editor (More → Cloud → SQL editor) and run it. Lovable doesn't apply migration files that arrive from GitHub (found on production, 2026-10-16).
2. Run [`dev/supabase/check-migrations.sql`](../dev/supabase/check-migrations.sql) in the SQL editor. Every row should say `yes`.
3. Open `https://<staging>/api/health`: `{"status":"ok"}`.
4. By hand: sign in as a new and a returning user (real mailboxes), join a society, register for an event, open `/admin`.
5. Write down here what happened, especially how Lovable applied the migration. That answers the open question in [roadmap.md](roadmap.md).

Then merge the pull request, and repeat steps 2 and 3 on production.

## Changes without a migration

Staging is optional; CI covers them. Use it for anything that depends on Lovable's hosting (build settings, server routes, secrets).
