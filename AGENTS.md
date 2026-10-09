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

## SocConnect architecture
- App data comes from `src/lib/api/` (`useData()`: one TanStack Query over the database, polled until realtime); pages never touch the database directly — keeps one seam for data.
- Permissions and multi-step writes are Postgres functions/RLS (join_society, decide_membership, register_for_event, support-request functions); mutations return `Outcome` `{ ok, error }` from `src/lib/validation.ts`, which only holds Zod form checks — the browser is never trusted.
- "Today" and times are real Europe/Dublin via `src/lib/format.ts`; societies are addressed by slug in the UI and mapped to ids in the data layer — keeps URLs stable.
- Date formatting is manual in `src/lib/format.ts` (no toLocaleDateString) to avoid SSR hydration mismatches.
- The app shell wraps every route except `/welcome` in `__root.tsx`.
- Calls: with `LIVEKIT_URL`/`LIVEKIT_API_KEY`/`LIVEKIT_API_SECRET` set, calls are real multi-person video via LiveKit (`src/components/live-call.tsx`; tokens minted server-side in `src/lib/livekit.server.ts`), and each person's browser speech-to-text is shared over the data channel so the recap covers everyone. Without them, calls fall back to scripted simulated participants (`src/data/calls.ts`). Recaps fall back to a keyword summary when AI is unavailable (`src/lib/call-recap-fallback.ts`).
- AI calls go through server functions in `src/lib/calls.functions.ts`, with gateway helpers in server-only `src/lib/ai.server.ts` — keeps the API key off the client.
- Identity comes from Lovable Cloud auth via `src/lib/auth.tsx` (session, profile, `my_access()` roles); app pages live under `src/routes/_authenticated/` so signed-out visitors go to `/welcome` — never trust the browser for roles.
- Sign-up domains and admin grants are enforced by database triggers on auth.users (`enforce_email_domain`, `handle_new_user`); committee seats come from `role_invites` claimed on sign-in — keep these rules in the database, not the UI.
- Platform admins manage societies and committees at `/admin`; RLS policies (has_role / is_society_committee) are the security boundary.
