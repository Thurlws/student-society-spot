import { defineConfig, devices } from "@playwright/test";
import { localStack } from "./e2e/support";

/**
 * User journeys in a real browser against the local Supabase stack. Start it first with
 * `npm run db:start`, then `bun run e2e`. The dev server is always started here with the
 * local URL and keys, so the tests can't reach the production backend in .env.
 */
const stack = localStack();

export default defineConfig({
  testDir: "e2e",
  // The journeys share one database, so they run one at a time.
  workers: 1,
  // The dev server compiles each page on its first visit, which is slow on CI machines.
  timeout: 60_000,
  expect: { timeout: 10_000 },
  reporter: process.env["CI"] ? [["github"], ["html", { open: "never" }]] : "list",
  globalSetup: "./e2e/global-setup.ts",
  use: {
    baseURL: "http://localhost:8080",
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
    // Set to use an already installed Chromium instead of `npx playwright install chromium`.
    launchOptions: process.env["PLAYWRIGHT_CHROMIUM_PATH"] ? { executablePath: process.env["PLAYWRIGHT_CHROMIUM_PATH"] } : {},
  },
  projects: [
    { name: "sign-in", testMatch: /auth\.setup\.ts/ },
    { name: "journeys", testMatch: /\.spec\.ts/, dependencies: ["sign-in"], use: { ...devices["Desktop Chrome"] } },
  ],
  webServer: {
    command: "npx vite dev --host 127.0.0.1 --port 8080 --strictPort",
    url: "http://localhost:8080/welcome",
    reuseExistingServer: false,
    timeout: 120_000,
    env: {
      VITE_SUPABASE_URL: stack.url,
      VITE_SUPABASE_PUBLISHABLE_KEY: stack.publishableKey,
      SUPABASE_URL: stack.url,
      SUPABASE_PUBLISHABLE_KEY: stack.publishableKey,
      SUPABASE_SERVICE_ROLE_KEY: stack.serviceKey,
    },
  },
});
