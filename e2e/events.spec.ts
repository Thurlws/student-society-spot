import { expect, test } from "@playwright/test";
import { isoDate, openNotifications, pageAs, people, societies } from "./support";

test("the committee creates an event, a student registers, then the committee moves and cancels it", async ({
  browser,
}) => {
  const chair = await pageAs(browser, people.chair);
  await chair.goto("/committee", { waitUntil: "networkidle" });
  await chair.getByRole("combobox").click();
  await chair.getByRole("option", { name: societies.open.shortName }).click();
  await chair.getByRole("button", { name: /Create event/ }).click();
  const form = chair.getByRole("dialog");
  await form.getByLabel("Title").fill("E2E board games");
  await form.getByLabel("Description").fill("Bring your favourite game.");
  await form.getByLabel("Date").fill(isoDate(14));
  await form.getByLabel("Start").fill("18:00");
  await form.getByLabel("End").fill("20:00");
  await form.getByLabel("Venue").fill("Bolton St, room 1");
  await form.getByLabel("Capacity").fill("2");
  await form.getByRole("button", { name: "Publish event" }).click();
  await expect(chair.getByRole("heading", { name: "E2E board games" })).toBeVisible();
  const eventUrl = chair.url();

  const student = await pageAs(browser, people.student);
  await student.goto(eventUrl, { waitUntil: "networkidle" });
  await student.getByRole("button", { name: "Register" }).click();
  await expect(student.getByText("You're registered", { exact: true })).toBeVisible();

  await chair.reload({ waitUntil: "networkidle" });
  await chair.getByRole("button", { name: "Edit event" }).click();
  await chair.getByRole("dialog").getByLabel("Start").fill("19:00");
  await chair.getByRole("dialog").getByLabel("Venue").fill("Bolton St, room 2");
  await chair.getByRole("button", { name: "Save changes" }).click();
  await expect(chair.getByText("Bolton St, room 2")).toBeVisible();

  await openNotifications(student);
  await expect(student.getByText("Event changed: E2E board games")).toBeVisible();
  await expect(student.getByText(/19:00, Bolton St, room 2/)).toBeVisible();

  await chair.getByRole("button", { name: "Cancel event" }).click();
  await chair.getByLabel("Reason (optional)").fill("The room is double-booked.");
  await chair.getByRole("alertdialog").getByRole("button", { name: "Cancel event" }).click();
  await expect(chair.getByText(`${societies.open.shortName} cancelled this event`)).toBeVisible();

  await student.goto(eventUrl, { waitUntil: "networkidle" });
  await expect(student.getByText("The room is double-booked.")).toBeVisible();
  await expect(student.getByRole("button", { name: "Cancelled" })).toBeDisabled();
  await openNotifications(student);
  await expect(student.getByText("Cancelled: E2E board games")).toBeVisible();
});
