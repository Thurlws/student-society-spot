import { expect, test } from "@playwright/test";
import { latestEmail, people, signIn } from "./support";

test("a new student confirms their address, sets up a profile and lands on the home page", async ({
  page,
}) => {
  const mail = await signIn(page, people.newcomer.email);
  expect(mail.subject).toBe("Confirm your SocConnect account");
  await expect(page).toHaveURL(/\/onboarding$/);
  await page.getByRole("button", { name: "Technology" }).click();
  await page.getByLabel("What should people call you?").fill("Nia Newcomer");
  await page.getByLabel("Year").selectOption("Year 1");
  await page.getByRole("button", { name: "Finish and continue" }).click();
  await expect(page.getByRole("heading", { level: 1 })).toContainText("Nia.");
});

test("a returning student gets a sign-in link and goes straight in", async ({ page }) => {
  const mail = await signIn(page, people.returning.email);
  expect(mail.subject).toBe("Your SocConnect sign-in link");
  await expect(page.getByRole("heading", { level: 1 })).toContainText("Rita.");
});

test("an address typed before the page has loaded is kept, and the link goes once it has", async ({
  page,
}) => {
  // Hold the page's scripts back, as a slow connection would.
  let load!: () => void;
  const loaded = new Promise<void>((resolve) => (load = resolve));
  await page.route("**/*", async (route) => {
    if (route.request().resourceType() === "script") await loaded;
    await route.continue();
  });
  await page.goto("/welcome", { waitUntil: "commit" });
  const email = page.getByLabel("University email");
  const send = page.getByRole("button", { name: "Email me a sign-in link" });
  await expect(send).toBeDisabled();
  await email.fill(people.early.email);
  await email.press("Enter");
  load();
  await expect(send).toBeEnabled();
  await expect(email).toHaveValue(people.early.email);
  await send.click();
  await expect(page.getByRole("heading", { name: "Check your inbox" })).toBeVisible();
  expect((await latestEmail(people.early.email)).subject).toBe("Confirm your SocConnect account");
});
