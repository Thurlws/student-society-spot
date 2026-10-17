import { expect, test, type Page } from "@playwright/test";
import { pageAs, people, societies } from "./support";

async function setFee(chair: Page, euros: string, saved: string) {
  await chair.goto("/committee", { waitUntil: "networkidle" });
  await chair.getByRole("combobox").click();
  await chair.getByRole("option", { name: societies.open.shortName }).click();
  await chair.getByLabel("Fee in euros").fill(euros);
  await chair.getByRole("button", { name: "Save fee" }).click();
  await expect(chair.getByText(saved)).toBeVisible();
}

test("a member pays the membership fee through the demo checkout", async ({ browser }) => {
  const chair = await pageAs(browser, people.chair);
  await setFee(chair, "5", "Membership fee saved");

  const member = await pageAs(browser, people.member);
  await member.goto(`/societies/${societies.open.slug}`, { waitUntil: "networkidle" });
  await expect(member.getByText("Membership fee:")).toBeVisible();
  await expect(member.getByText("Not paid yet.")).toBeVisible();
  await member.getByRole("button", { name: "Pay €5 (demo)" }).click();
  // Nobody can mistake it for a real payment.
  await expect(member.getByRole("dialog").getByText("No money is taken")).toBeVisible();
  await member.getByRole("button", { name: "Complete demo payment" }).click();
  await expect(member.getByText("Demo payment of €5 recorded, no money taken.")).toBeVisible();
  await expect(member.getByText(/Paid \(demo, no money taken\)/)).toBeVisible();

  await chair.reload({ waitUntil: "networkidle" });
  await chair.getByRole("combobox").click();
  await chair.getByRole("option", { name: societies.open.shortName }).click();
  await expect(chair.getByText(/1 of \d+ paid, 1 through the demo checkout/)).toBeVisible();
  await expect(
    chair.getByRole("button", { name: `Mark ${people.member.name} unpaid` }),
  ).toBeVisible();

  // Back to free, so other journeys join without the checkout.
  await setFee(chair, "", `${societies.open.shortName} is free to join`);
});
