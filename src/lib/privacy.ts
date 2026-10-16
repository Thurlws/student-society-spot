// What the privacy notice at /privacy says about contacts, retention and service providers.
// Keep it in step with docs/privacy/ and migration 0026 (the nightly purge).

/**
 * Where people write about their personal data. Empty until the SocConnect team sets up an
 * address; it must be filled in before a university pilot (docs/privacy/README.md).
 */
export const PRIVACY_CONTACT_EMAIL = "";

export const NOTICE_UPDATED = "16 October 2026";

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
];
