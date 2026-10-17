import { expect, test } from "@playwright/test";
import { pageAs, people, societies } from "./support";

test("a member puts their registered events in their own calendar", async ({ browser }) => {
  const member = await pageAs(browser, people.member);
  await member.goto(`/societies/${societies.open.slug}`, { waitUntil: "networkidle" });
  await member.getByRole("tab", { name: "events" }).click();
  await member
    .getByRole("link", { name: /E2E quiz night/ })
    .first()
    .click();
  await expect(member.getByRole("heading", { name: "E2E quiz night" })).toBeVisible();
  // The booking panel renders after the heading. Wait for it, then register unless a retry
  // already did.
  const register = member.getByRole("button", { name: "Register" });
  const registered = member.getByText("You're registered", { exact: true });
  await expect(register.or(registered)).toBeVisible();
  if (await register.isVisible()) await register.click();
  await expect(registered).toBeVisible();
  await expect(member.getByRole("link", { name: "Add to Google Calendar" })).toHaveAttribute(
    "href",
    /^https:\/\/calendar\.google\.com\/calendar\/render\?action=TEMPLATE&text=E2E\+quiz\+night/,
  );

  await member.goto("/settings#calendar", { waitUntil: "networkidle" });
  await member.getByRole("button", { name: "Make my calendar link" }).click();
  const link = await member.getByLabel("Your calendar link").inputValue();
  expect(link).toMatch(/\/api\/calendar\/[0-9a-f]{64}\.ics$/);
  await expect(member.getByRole("link", { name: "Add to Google Calendar" })).toHaveAttribute(
    "href",
    /^https:\/\/calendar\.google\.com\/calendar\/r\?cid=webcal/,
  );
  // What a calendar app gets, without signing in.
  const feed = await member.request.get(link, { headers: { cookie: "" } });
  expect(feed.status()).toBe(200);
  expect(feed.headers()["content-type"]).toContain("text/calendar");
  expect(await feed.text()).toContain("SUMMARY:E2E quiz night");

  // Shown once; afterwards it can be replaced or turned off.
  await member.reload({ waitUntil: "networkidle" });
  await expect(member.getByText(/Your calendar link is on/)).toBeVisible();
  await member.getByRole("button", { name: "Turn it off" }).click();
  await expect(member.getByText("Calendar link turned off")).toBeVisible();
  const after = await member.request.get(link);
  expect(await after.text()).not.toContain("BEGIN:VEVENT");
});
