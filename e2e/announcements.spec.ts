import { expect, test } from "@playwright/test";
import { pageAs, people, societies } from "./support";

test("the committee posts, edits and deletes an announcement that members see", async ({
  browser,
}) => {
  const chair = await pageAs(browser, people.chair);
  await chair.goto("/committee", { waitUntil: "networkidle" });
  await chair.getByRole("combobox").click();
  await chair.getByRole("option", { name: societies.open.shortName }).click();
  await chair.getByRole("button", { name: /Post announcement/ }).click();
  await chair.getByLabel("Title").fill("AGM on Thursday");
  await chair.getByLabel("Message").fill("The AGM is on Thursday at six in the student union.");
  await chair.getByRole("button", { name: "Publish" }).click();
  await expect(chair.getByText("Announcement published")).toBeVisible();

  const member = await pageAs(browser, people.member);
  await member.goto(`/societies/${societies.open.slug}`, { waitUntil: "networkidle" });
  await member.getByRole("tab", { name: "announcements" }).click();
  await expect(member.getByRole("heading", { name: "AGM on Thursday" })).toBeVisible();
  await expect(member.getByRole("button", { name: "Edit AGM on Thursday" })).toHaveCount(0);

  await chair.goto(`/societies/${societies.open.slug}`, { waitUntil: "networkidle" });
  await chair.getByRole("tab", { name: "announcements" }).click();
  await chair.getByRole("button", { name: "Edit AGM on Thursday" }).click();
  await chair.getByLabel("Message").fill("The AGM is on Thursday at seven in the student union.");
  await chair.getByRole("button", { name: "Save changes" }).click();
  await expect(chair.getByText("at seven in the student union")).toBeVisible();

  await member.reload({ waitUntil: "networkidle" });
  await member.getByRole("tab", { name: "announcements" }).click();
  await expect(member.getByText("at seven in the student union")).toBeVisible();
  await expect(member.getByText(/, edited/)).toBeVisible();

  await chair.getByRole("button", { name: "Delete AGM on Thursday" }).click();
  await chair.getByRole("alertdialog").getByRole("button", { name: "Delete" }).click();
  await expect(chair.getByRole("heading", { name: "AGM on Thursday" })).toHaveCount(0);
});
