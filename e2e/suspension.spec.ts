import { expect, test } from "@playwright/test";
import { pageAs, people, societies } from "./support";

test("a university admin suspends a student, who sees why, then lifts it", async ({ browser }) => {
  const admin = await pageAs(browser, people.uniadmin);
  await admin.goto("/admin", { waitUntil: "networkidle" });
  await admin.getByRole("tab", { name: "People" }).click();
  const section = admin.locator("section", {
    has: admin.getByRole("heading", { name: "People", exact: true }),
  });
  await section.getByLabel("Name or email address").fill(people.student.email);
  await section.getByRole("button", { name: "Find" }).click();
  await expect(section.getByText(people.student.name)).toBeVisible();
  await section.getByRole("button", { name: "Suspend" }).click();
  const dialog = admin.getByRole("dialog");
  await dialog.getByLabel("Reason (they see this)").fill("Spamming the events channel");
  await dialog.getByRole("button", { name: "Suspend" }).click();
  await expect(admin.getByText(`${people.student.name} is suspended`)).toBeVisible();
  await expect(
    section.getByText(/Suspended .*: Spamming the events channel/).first(),
  ).toBeVisible();

  // The student sees the notice instead of the app, and nothing from their societies.
  const student = await pageAs(browser, people.student);
  await student.goto(`/societies/${societies.open.slug}`, { waitUntil: "networkidle" });
  await expect(student.getByRole("heading", { name: "Your account is suspended" })).toBeVisible();
  await expect(student.getByText("Spamming the events channel")).toBeVisible();
  await expect(student.getByRole("link", { name: "Discover societies" })).toHaveCount(0);

  await section.getByRole("button", { name: "Lift suspension" }).first().click();
  await admin.getByRole("alertdialog").getByRole("button", { name: "Lift suspension" }).click();
  await expect(admin.getByText(`${people.student.name}'s suspension is lifted`)).toBeVisible();

  await student.goto(`/societies/${societies.open.slug}`, { waitUntil: "networkidle" });
  await expect(student.getByRole("heading", { name: societies.open.name })).toBeVisible();

  await admin.getByRole("tab", { name: "Activity" }).click();
  const activity = admin.locator("section", {
    has: admin.getByRole("heading", { name: "Activity" }),
  });
  await expect(
    activity.getByText(`${people.student.name} was suspended: Spamming the events channel`),
  ).toBeVisible();
  await expect(activity.getByText(`${people.student.name}'s suspension was lifted`)).toBeVisible();
});
