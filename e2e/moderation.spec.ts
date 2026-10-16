import { expect, test } from "@playwright/test";
import { pageAs, people, societies } from "./support";

test("a member reports a message and the committee removes it", async ({ browser }) => {
  const member = await pageAs(browser, people.member);
  await member.goto(`/societies/${societies.open.slug}`, { waitUntil: "networkidle" });
  await member.getByRole("tab", { name: "discussions" }).click();
  await member.getByLabel("Message", { exact: true }).fill("Nobody should come to this society");
  await member.getByRole("button", { name: "Send" }).click();
  await expect(member.getByText("Nobody should come to this society")).toBeVisible();

  const student = await pageAs(browser, people.student);
  await student.goto(`/societies/${societies.open.slug}`, { waitUntil: "networkidle" });
  await student.getByRole("button", { name: "Join society" }).click();
  await student.getByRole("tab", { name: "discussions" }).click();
  await student
    .getByRole("button", { name: `Actions for ${people.member.name}'s message` })
    .click();
  // Students can report other people's messages but not delete them.
  await expect(student.getByRole("menuitem", { name: "Remove message" })).toHaveCount(0);
  await student.getByRole("menuitem", { name: "Report to the committee" }).click();
  await student.getByLabel("What's wrong with it? (optional)").fill("Putting people off joining");
  await student.getByRole("button", { name: "Send report" }).click();
  await expect(student.getByText("Reported. Thanks for letting the committee know.")).toBeVisible();

  const chair = await pageAs(browser, people.chair);
  await chair.goto("/committee", { waitUntil: "networkidle" });
  await chair.getByRole("combobox").click();
  await chair.getByRole("option", { name: societies.open.shortName }).click();
  const queue = chair.locator("section", {
    has: chair.getByRole("heading", { name: "Reported messages" }),
  });
  await expect(queue.getByText("Nobody should come to this society")).toBeVisible();
  await expect(queue.getByText("Putting people off joining")).toBeVisible();
  await queue.getByRole("button", { name: `Remove message from ${people.member.name}` }).click();
  await chair.getByRole("alertdialog").getByRole("button", { name: "Remove" }).click();
  await expect(chair.getByText("Message removed")).toBeVisible();

  await member.reload({ waitUntil: "networkidle" });
  await member.getByRole("tab", { name: "discussions" }).click();
  await expect(member.getByText("Nobody should come to this society")).toHaveCount(0);
});
