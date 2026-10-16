import { execSync } from "node:child_process";
import { createClient } from "@supabase/supabase-js";
import { expect, type Browser, type Page } from "@playwright/test";

/**
 * Journeys run against the local Supabase stack (`npm run db:start`), never the production
 * backend in the committed .env. Emails are read from the local Mailpit.
 */
export const MAILPIT = "http://127.0.0.1:54324";

type Stack = { url: string; publishableKey: string; serviceKey: string };
export function localStack(): Stack {
  if (!process.env["E2E_STACK"]) {
    const s = JSON.parse(execSync("npm run -s supabase -- status -o json", { encoding: "utf8" }));
    process.env["E2E_STACK"] = JSON.stringify({
      url: s.API_URL,
      publishableKey: s.PUBLISHABLE_KEY,
      serviceKey: s.SERVICE_ROLE_KEY,
    });
  }
  const stack = JSON.parse(process.env["E2E_STACK"]) as Stack;
  if (!/^http:\/\/(127\.0\.0\.1|localhost):\d+$/.test(stack.url))
    throw new Error(`Refusing to run journeys against ${stack.url}: only the local stack.`);
  return stack;
}

export const adminClient = () => {
  const { url, serviceKey } = localStack();
  return createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
};

/** Test accounts. Everything starting with "e2e-" is deleted and recreated before each run. */
export const people = {
  chair: { email: "e2e-chair@mytudublin.ie", name: "Cara Chair", state: "e2e/.auth/chair.json" },
  member: { email: "e2e-member@mytudublin.ie", name: "Mo Member", state: "e2e/.auth/member.json" },
  student: {
    email: "e2e-student@mytudublin.ie",
    name: "Sam Student",
    state: "e2e/.auth/student.json",
  },
  returning: { email: "e2e-returning@mytudublin.ie", name: "Rita Returning" },
  newcomer: { email: "e2e-newcomer@mytudublin.ie" },
};
export const societies = {
  open: { slug: "e2e-open", name: "E2E Open Society", shortName: "E2E Open" },
  approval: { slug: "e2e-approval", name: "E2E Approval Society", shortName: "E2E Approval" },
};

/** The newest email to an address, waiting for it to arrive. */
export async function latestEmail(email: string) {
  for (let i = 0; i < 40; i++) {
    const r = await fetch(`${MAILPIT}/api/v1/search?query=${encodeURIComponent(`to:"${email}"`)}`);
    const [m] = ((await r.json()).messages ?? []) as { ID: string; Subject: string }[];
    if (m) {
      const full = (await (await fetch(`${MAILPIT}/api/v1/message/${m.ID}`)).json()) as {
        Text: string;
      };
      return { subject: m.Subject, text: full.Text };
    }
    await new Promise((res) => setTimeout(res, 250));
  }
  throw new Error(`No email arrived for ${email}`);
}

/** Signs in the way a student does: the form on /welcome, the emailed link, then Continue. */
export async function signIn(page: Page, email: string) {
  // Wait for hydration: text typed into the server-rendered form before then is lost.
  await page.goto("/welcome", { waitUntil: "networkidle" });
  await page.getByLabel("University email").fill(email);
  await page.getByRole("button", { name: "Email me a sign-in link" }).click();
  await expect(page.getByRole("heading", { name: "Check your inbox" })).toBeVisible();
  const mail = await latestEmail(email);
  const link = mail.text.match(
    /https?:\/\/\S+?\/auth\/confirm\?token_hash=[^&\s]+&type=email/,
  )?.[0];
  if (!link) throw new Error(`No sign-in link in "${mail.subject}"`);
  await page.goto(link, { waitUntil: "networkidle" });
  await page.getByRole("button", { name: "Continue" }).click();
  await page.waitForURL((u) => !u.pathname.startsWith("/auth/"));
  return mail;
}

/** A page signed in as one of the saved test accounts. */
export async function pageAs(browser: Browser, who: { state: string }) {
  const context = await browser.newContext({ storageState: who.state });
  return context.newPage();
}

/** Opens the notifications bell in the top bar, fresh from the database. */
export async function openNotifications(page: Page) {
  await page.goto("/", { waitUntil: "networkidle" });
  await page.getByRole("button", { name: /^Notifications/ }).click();
}

/** YYYY-MM-DD, `days` from today. */
export const isoDate = (days: number) =>
  new Date(Date.now() + days * 86_400_000).toISOString().slice(0, 10);
