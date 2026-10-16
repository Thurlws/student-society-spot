import { expect, test } from "@playwright/test";
import { pageAs, people } from "./support";

test("a university admin creates a society and invites its committee", async ({ browser }) => {
  const admin = await pageAs(browser, people.uniadmin);
  await admin.goto("/admin", { waitUntil: "networkidle" });
  await expect(admin.getByText("Add TU Dublin societies and choose who runs them.")).toBeVisible();

  await admin.getByRole("button", { name: "New society" }).click();
  const dialog = admin.getByRole("dialog");
  await dialog.getByLabel("Name", { exact: true }).fill("E2E Admin Made Society");
  await dialog.getByLabel("Short name").fill("E2E Admin Made");
  await dialog.getByLabel("Address").fill("e2e-admin-made");
  await dialog.getByRole("button", { name: "Create society" }).click();
  await expect(admin.getByText("Society created")).toBeVisible();

  const society = admin.locator("section", {
    has: admin.getByRole("heading", { name: /E2E Admin Made Society/ }),
  });
  await society.getByLabel("Committee member email").fill("e2e-newchair@mytudublin.ie");
  await society.getByLabel("Position").fill("President");
  await society.getByRole("button", { name: "Add", exact: true }).click();
  await expect(
    society.getByText("e2e-newchair@mytudublin.ie, President, waiting for first sign-in"),
  ).toBeVisible();

  // The database only takes committee invites at the society's university.
  await society.getByLabel("Committee member email").fill("someone@gmail.com");
  await society.getByRole("button", { name: "Add", exact: true }).click();
  await expect(admin.getByText("Invite an address at TU Dublin.")).toBeVisible();
});
