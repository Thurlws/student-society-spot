import { expect, test } from "@playwright/test";
import { openNotifications, pageAs, people, societies } from "./support";

test("a student asks to join an approval-only society and the committee approves", async ({
  browser,
}) => {
  const student = await pageAs(browser, people.student);
  await student.goto(`/societies/${societies.approval.slug}`);
  await student.getByRole("button", { name: "Request to join" }).click();
  await expect(student.getByRole("button", { name: "Pending, cancel request" })).toBeVisible();

  const chair = await pageAs(browser, people.chair);
  await chair.goto("/committee");
  await chair.getByRole("combobox").click();
  await chair.getByRole("option", { name: societies.approval.shortName }).click();
  await chair.getByRole("button", { name: `Approve ${people.student.name}` }).click();
  await expect(
    chair.getByText(`${people.student.name} is now a member of ${societies.approval.shortName}`),
  ).toBeVisible();

  await openNotifications(student);
  await expect(
    student.getByText(`You're in! Welcome to ${societies.approval.shortName}`),
  ).toBeVisible();
  await student.goto(`/societies/${societies.approval.slug}`);
  await expect(
    student.getByRole("button", { name: `Joined ${societies.approval.shortName}. Leave society` }),
  ).toBeVisible();
});
