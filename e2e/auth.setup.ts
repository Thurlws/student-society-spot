import { test as setup } from "@playwright/test";
import { people, signIn } from "./support";

// Each account signs in once per run through the real email flow; the journeys reuse the session.
for (const who of [people.chair, people.member, people.student, people.uniadmin]) {
  setup(`sign in as ${who.name}`, async ({ page }) => {
    await signIn(page, who.email);
    await page.context().storageState({ path: who.state });
  });
}
