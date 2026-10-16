import { expect, test } from "@playwright/test";
import { pageAs, people } from "./support";

test("a university admin creates a society and invites its committee", async ({ browser }) => {
  const admin = await pageAs(browser, people.uniadmin);
  await admin.goto("/admin", { waitUntil: "networkidle" });
  await expect(
    admin.getByText("Run TU Dublin's societies and committees, and look after its members."),
  ).toBeVisible();

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
  await society.getByRole("button", { name: "Committee" }).click();
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

  // Both changes are in the activity log, under the admin's name.
  await admin.getByRole("tab", { name: "Activity" }).click();
  const activity = admin.locator("section", {
    has: admin.getByRole("heading", { name: "Activity" }),
  });
  await expect(activity.getByText("E2E Admin Made Society was created")).toBeVisible();
  await expect(
    activity.getByText(
      "e2e-newchair@mytudublin.ie was invited to E2E Admin Made's committee as President",
    ),
  ).toBeVisible();
  await expect(activity.getByText(`${people.uniadmin.name}, `).first()).toBeVisible();
});

test("a university admin imports societies from a file", async ({ browser }) => {
  const admin = await pageAs(browser, people.uniadmin);
  await admin.goto("/admin", { waitUntil: "networkidle" });
  await admin.getByRole("button", { name: "Import societies" }).click();
  const dialog = admin.getByRole("dialog");
  await dialog.getByLabel("File").setInputFiles({
    name: "societies.csv",
    mimeType: "text/csv",
    buffer: Buffer.from(
      [
        "id,name,short_name,slug,category,interests",
        "e2e-1,E2E Imported Chess Society,E2E Chess,e2e-imported-chess,Gaming,Gaming",
        'e2e-2,"E2E Imported Drama, Theatre and Film",E2E Drama,e2e-imported-drama,Arts,Arts',
      ].join("\n"),
    ),
  });
  await expect(dialog.getByText(/2 societies in societies\.csv/)).toBeVisible();
  await dialog.getByRole("button", { name: "Import" }).click();
  await expect(admin.getByText("2 new societies, 0 updated")).toBeVisible();
  await expect(
    admin.getByRole("heading", { name: /E2E Imported Drama, Theatre and Film/ }),
  ).toBeVisible();
  await admin.getByRole("tab", { name: "Activity" }).click();
  const activity = admin.locator("section", {
    has: admin.getByRole("heading", { name: "Activity" }),
  });
  await expect(
    activity.getByText("2 societies were imported from a file: 2 new, 0 updated"),
  ).toBeVisible();
});
