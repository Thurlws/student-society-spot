import { expect, test } from "@playwright/test";
import { pageAs, people, societies } from "./support";

test("the profile form edits the society picked on the committee dashboard", async ({
  browser,
}) => {
  const chair = await pageAs(browser, people.chair);
  await chair.goto("/committee", { waitUntil: "networkidle" });
  await chair.getByRole("combobox").click();
  await chair.getByRole("option", { name: societies.open.shortName }).click();
  await chair.getByRole("button", { name: /Edit society profile/ }).click();
  await expect(chair.getByLabel("Tagline")).toHaveValue("Everyone welcome");
  await chair.keyboard.press("Escape");

  await chair.getByRole("combobox").click();
  await chair.getByRole("option", { name: societies.approval.shortName }).click();
  await chair.getByRole("button", { name: /Edit society profile/ }).click();
  await expect(chair.getByLabel("Tagline")).toHaveValue("Ask to join");
});
