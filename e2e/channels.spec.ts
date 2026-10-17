import { expect, test } from "@playwright/test";
import { pageAs, people, societies } from "./support";

test("the committee adds a committee-only channel, and deletes it", async ({ browser }) => {
  const chair = await pageAs(browser, people.chair);
  await chair.goto(`/societies/${societies.open.slug}`, { waitUntil: "networkidle" });
  await chair.getByRole("tab", { name: "discussions" }).click();
  await chair.getByRole("button", { name: "Add a channel" }).click();
  const form = chair.getByRole("dialog");
  await form.getByLabel("Name").fill("AGM Notices!");
  await expect(form.getByText("Shown as #agm-notices")).toBeVisible();
  await form.getByLabel("Description").fill("From the committee");
  await form.getByRole("switch").click();
  await form.getByRole("button", { name: "Add channel" }).click();
  await expect(chair.getByText("#agm-notices added")).toBeVisible();
  await chair.getByRole("button", { name: /agm-notices/ }).click();
  await chair.getByLabel("Message", { exact: true }).fill("The AGM is on Friday");
  await chair.getByRole("button", { name: "Send" }).click();
  await expect(chair.getByText("The AGM is on Friday")).toBeVisible();

  // Members read it but can't post there.
  const member = await pageAs(browser, people.member);
  await member.goto(`/societies/${societies.open.slug}`, { waitUntil: "networkidle" });
  await member.getByRole("tab", { name: "discussions" }).click();
  await expect(member.getByRole("button", { name: "Add a channel" })).toHaveCount(0);
  await member.getByRole("button", { name: /agm-notices/ }).click();
  await expect(member.getByText("The AGM is on Friday")).toBeVisible();
  await expect(member.getByText("Only the committee posts in #agm-notices.")).toBeVisible();
  await expect(member.getByLabel("Message", { exact: true })).toHaveCount(0);

  await chair.getByRole("button", { name: "Edit #agm-notices" }).click();
  await chair.getByRole("dialog").getByRole("button", { name: "Delete" }).click();
  await chair.getByRole("alertdialog").getByRole("button", { name: "Delete channel" }).click();
  await expect(chair.getByText("#agm-notices deleted")).toBeVisible();
  await expect(chair.getByRole("button", { name: /agm-notices/ })).toHaveCount(0);
  // #general can be edited but not deleted.
  await chair.getByRole("button", { name: "Edit #general" }).click();
  await expect(chair.getByRole("dialog").getByRole("button", { name: "Delete" })).toHaveCount(0);
});
