import { expect, test } from "@playwright/test";
import { people, signIn } from "./support";

test("a new student confirms their address, sets up a profile and lands on the home page", async ({ page }) => {
  const mail = await signIn(page, people.newcomer.email);
  expect(mail.subject).toBe("Confirm your SocConnect account");
  await expect(page).toHaveURL(/\/onboarding$/);
  await page.getByRole("button", { name: "Technology" }).click();
  await page.getByLabel("Display name").fill("Nia Newcomer");
  await page.getByLabel("Year").selectOption("Year 1");
  await page.getByRole("button", { name: "Finish and continue" }).click();
  await expect(page.getByRole("heading", { level: 1 })).toContainText("Nia.");
});

test("a returning student gets a sign-in link and goes straight in", async ({ page }) => {
  const mail = await signIn(page, people.returning.email);
  expect(mail.subject).toBe("Your SocConnect sign-in link");
  await expect(page.getByRole("heading", { level: 1 })).toContainText("Rita.");
});
