// Checks that the local stack sends a sign-in email to a returning user, the case that
// fails in production (see context/sign-in-email-bug.md). Run with `npm run db:check-sign-in`
// after `npm run db:start`. Sends the same request as signInWithOtp in src/routes/welcome.tsx.
import { execSync } from "node:child_process";

const API = "http://127.0.0.1:54321";
const MAIL = "http://127.0.0.1:54324";
const env = execSync("npm run -s supabase -- status -o env", { encoding: "utf8" });
const key = env.match(/^PUBLISHABLE_KEY="?([^"\n]+)/m)?.[1];
if (!key) throw new Error("No local publishable key. Is the stack running? Try `npm run db:start`.");

const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const signIn = (email) =>
  fetch(`${API}/auth/v1/otp?redirect_to=${encodeURIComponent("http://localhost:8080")}`, {
    method: "POST",
    headers: { apikey: key, "content-type": "application/json" },
    body: JSON.stringify({ email, data: {}, create_user: true }),
  });
const subjects = async (email) => {
  await wait(1500);
  const r = await fetch(`${MAIL}/api/v1/search?query=${encodeURIComponent(`to:"${email}"`)}`);
  return ((await r.json()).messages ?? []).map((m) => ({ id: m.ID, subject: m.Subject }));
};
const fail = (msg) => {
  console.error(`FAIL: ${msg}`);
  process.exit(1);
};

const email = `check.${Date.now()}@mytudublin.ie`;
let res = await signIn(email);
if (!res.ok) fail(`new address: HTTP ${res.status} ${await res.text()}`);
let mails = await subjects(email);
if (mails.length !== 1) fail(`new address: expected 1 email, got ${mails.length}`);
console.log(`ok  new address gets "${mails[0].subject}"`);

// The emails link to our /auth/confirm page, which calls verifyOtp({ token_hash, type }) on a button press.
const verify = async (id) => {
  const text = (await (await fetch(`${MAIL}/api/v1/message/${id}`)).json()).Text;
  const tokenHash = text.match(/\/auth\/confirm\?token_hash=([^&\s]+)&type=email/)?.[1];
  if (!tokenHash) fail("no /auth/confirm link in the email");
  return fetch(`${API}/auth/v1/verify`, {
    method: "POST",
    headers: { apikey: key, "content-type": "application/json" },
    body: JSON.stringify({ type: "email", token_hash: tokenHash }),
  });
};
let verified = await verify(mails[0].id);
if (!(await verified.json()).access_token) fail("confirmation link gave no session");
console.log("ok  confirmation link signs the user in");

res = await signIn(email);
if (!res.ok) fail(`returning user: HTTP ${res.status} ${await res.text()}`);
mails = await subjects(email);
if (mails.length !== 2) fail(`returning user: expected a second email, got ${mails.length} in total`);
console.log(`ok  returning user gets "${mails[0].subject}"`);
verified = await verify(mails[0].id);
if (!(await verified.json()).access_token) fail("sign-in link gave no session");
console.log("ok  sign-in link signs the user in");
verified = await verify(mails[0].id);
if (verified.ok) fail("a used sign-in link worked a second time");
console.log("ok  a used link is refused");

res = await signIn(email);
if (res.status !== 429) fail(`immediate retry: expected HTTP 429, got ${res.status}`);
console.log("ok  immediate retry is refused with 429 (60 s cooldown)");
