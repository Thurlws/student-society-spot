/**
 * Cloudflare Turnstile, the bot check on the sign-in form (audit finding 7). The site key is
 * public and set in .env as VITE_TURNSTILE_SITE_KEY; without one there's no check and nothing
 * loads from Cloudflare. The secret key belongs in Lovable Cloud's auth settings, where
 * Supabase Auth checks each sign-in email request's token (context/go-live.md).
 */
export const TURNSTILE_SITE_KEY: string =
  (import.meta.env["VITE_TURNSTILE_SITE_KEY"] as string | undefined)?.trim() ?? "";
