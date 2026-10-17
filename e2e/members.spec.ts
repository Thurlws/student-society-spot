import { expect, test } from "@playwright/test";
import { openNotifications, pageAs, people, societies } from "./support";

test("the committee sees every member and removes one", async ({ browser }) => {
  const student = await pageAs(browser, people.student);
  await student.goto(`/societies/${societies.open.slug}`, { waitUntil: "networkidle" });
  await student.getByRole("button", { name: "Join society" }).click();
  await expect(
    student.getByRole("button", { name: `Joined ${societies.open.shortName}. Leave society` }),
  ).toBeVisible();
  // Members see the committee and themselves, not the list.
  await student.getByRole("tab", { name: "members" }).click();
  await expect(student.getByRole("button", { name: `Remove ${people.member.name}` })).toHaveCount(
    0,
  );

  const chair = await pageAs(browser, people.chair);
  await chair.goto(`/societies/${societies.open.slug}`, { waitUntil: "networkidle" });
  await chair.getByRole("tab", { name: "members" }).click();
  await expect(
    chair.getByText("Only the committee sees this list.", { exact: false }),
  ).toBeVisible();
  await chair.getByLabel("Search members").fill("sam");
  await expect(chair.getByText(people.member.name)).toHaveCount(0);
  await chair.getByRole("button", { name: `Remove ${people.student.name}` }).click();
  await chair.getByLabel("Reason (optional, they see it)").fill("Testing the members tab");
  await chair.getByRole("alertdialog").getByRole("button", { name: "Remove" }).click();
  await expect(chair.getByText(`${people.student.name} was removed`)).toBeVisible();
  await expect(chair.getByText("Nobody matches that search.")).toBeVisible();

  await openNotifications(student);
  await expect(
    student.getByText(`You were removed from ${societies.open.shortName}`),
  ).toBeVisible();
  await student.goto(`/societies/${societies.open.slug}`, { waitUntil: "networkidle" });
  await expect(student.getByRole("button", { name: "Join society" })).toBeVisible();
});
