// What the privacy notice at /privacy says about contacts, retention and service providers.
import { TURNSTILE_SITE_KEY } from "@/lib/turnstile";
// Keep it in step with docs/privacy/ and migration 0026 (the nightly purge).

/**
 * Where people write about their personal data. Empty until the SocConnect team sets up an
 * address; it must be filled in before a university pilot (docs/privacy/README.md).
 */
export const PRIVACY_CONTACT_EMAIL = "";

/**
 * Who runs SocConnect, as a legal person or business with its address (the EU e-Commerce
 * Directive and the GDPR ask for it). Empty until the team confirms it (docs/privacy/dpia.md).
 */
export const OPERATOR = "";

export const NOTICE_UPDATED = "16 October 2026";
export const TERMS_UPDATED = "16 October 2026";

/**
 * Everything SocConnect keeps on a visitor's device. All of it is strictly necessary for what the
 * person asked for, so the ePrivacy rules need no consent banner; the notice lists it anyway.
 * Adding anything that isn't (analytics, tracking, a third-party script) needs consent first.
 */
export const DEVICE_STORAGE: { name: string; kind: string; why: string; kept: string }[] = [
  {
    name: "sb-…-auth-token",
    kind: "Local storage",
    why: "Keeps you signed in",
    kept: "Until you sign out, or a year after your last sign-in",
  },
  {
    name: "socconnect-guest-name",
    kind: "Session storage",
    why: "Remembers the name you typed to join a call as a guest",
    kept: "Until you close the tab",
  },
];

/** How long each kind of data is kept. The purge runs every night (purge_expired_data). */
export const RETENTION: { what: string; kept: string }[] = [
  {
    what: "Your account: email address, name, course, year, interests, settings",
    kept: "Until you delete it. A year without signing in ends your sessions, and you need your university mailbox to get back in.",
  },
  {
    what: "Memberships, committee positions, messages, announcements and events",
    kept: "While the account or society exists, unless you or the committee delete them first",
  },
  { what: "Who registered for an event", kept: "A year after the event" },
  { what: "Call transcripts", kept: "7 days" },
  { what: "Call recaps (AI summary, answers, who took part)", kept: "A year" },
  { what: "Who joined a call", kept: "90 days" },
  { what: "Notifications", kept: "90 days once read, a year at most" },
  { what: "Reports about messages", kept: "Until handled, then a year" },
  { what: "Member requests to committees", kept: "Two years after they're resolved" },
  { what: "Record of AI feature use (for usage limits)", kept: "30 days" },
  {
    what: "Admin activity log (rights, invites, society changes, moderation, suspensions)",
    kept: "Two years",
  },
];

/** Companies that process personal data for SocConnect. Regions marked "to confirm" are being checked. */
export const PROVIDERS: { name: string; does: string; data: string; where: string }[] = [
  {
    name: "Lovable",
    does: "Hosts the app and runs its database and sign-in (Lovable Cloud, built on Supabase)",
    data: "Everything SocConnect stores",
    where: "to confirm",
  },
  {
    name: "Lovable's email service",
    does: "Sends sign-in emails",
    data: "Your email address",
    where: "to confirm",
  },
  {
    name: "OpenAI, through Lovable's AI gateway",
    does: "Writes captions, call recaps and answers, and explains society suggestions",
    data: "Speech from your captions, call transcripts, your questions, society details",
    where: "United States, to confirm the transfer terms",
  },
  {
    name: "LiveKit",
    does: "Carries video calls",
    data: "Your name, camera, microphone and captions while you're in a call",
    where: "to confirm",
  },
  {
    name: "Sentry",
    does: "Tells the SocConnect team when something breaks",
    data: "Error reports and the server's activity log: what failed or ran, on which page, how long it took, and technical details. Email addresses and sign-in tokens are removed first; no names, messages or who did what",
    where: "EU (Frankfurt), to confirm the transfer terms for its US parent company",
  },
  // Only while the bot check is switched on (VITE_TURNSTILE_SITE_KEY).
  ...(TURNSTILE_SITE_KEY
    ? [
        {
          name: "Cloudflare (Turnstile)",
          does: "Checks that the sign-in form is used by a person, not a bot",
          data: "Your IP address and technical details of your browser, on the sign-in page only. It sets no cookies",
          where: "Cloudflare's network, worldwide, to confirm the transfer terms",
        },
      ]
    : []),
];
