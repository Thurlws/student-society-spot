/**
 * Guest links: a committee-made code (stored hashed, with expiry and a use limit) opens a
 * call without an account. The bare call page lives at /join/$code.
 */

/** Same-site path for a guest invite code. */
export const joinPath = (code: string) => `/join/${encodeURIComponent(code.trim())}`;

/**
 * Absolute invite URL for a room.
 * Returns null when the origin isn't a normal web address (e.g. SSR, where
 * window.location.origin is "null") so callers never encode junk into a QR code.
 */
export function inviteUrl(code: string, origin: string): string | null {
  const id = code.trim();
  const base = origin.trim().replace(/\/+$/, "");
  if (!id || !/^https?:\/\/[^\s/]+$/i.test(base)) return null;
  return `${base}${joinPath(id)}`;
}

/**
 * sessionStorage key holding the name a visitor used for their last guest call. Session only, so
 * it stays strictly necessary under the ePrivacy rules (no consent needed) and leaves with the tab.
 */
export const GUEST_NAME_KEY = "socconnect-guest-name";

/** Guest display names are short and must not contain control characters. */
export function cleanGuestName(raw: string): string {
  const name = raw
    .replace(/\s+/g, " ")
    .replace(/\p{Cc}/gu, "")
    .trim()
    .slice(0, 60);
  return name.length > 0 ? name : "Guest";
}
