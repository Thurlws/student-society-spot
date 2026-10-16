import { describe, expect, it } from "vitest";

import { signInError } from "@/lib/auth";

describe("signInError", () => {
  it("turns the per-user cooldown into a wait time", () => {
    expect(
      signInError({
        code: "over_email_send_rate_limit",
        message: "For security purposes, you can only request this after 42 seconds.",
      }),
    ).toBe("You just asked for a link. Wait 42 seconds, then try again.");
  });

  it("explains the project-wide email cap", () => {
    expect(
      signInError({ code: "over_email_send_rate_limit", message: "email rate limit exceeded" }),
    ).toMatch(/last hour/);
  });

  it("keeps the domain rule's own message", () => {
    expect(signInError({ message: "Please use your TU Dublin email (@mytudublin.ie)" })).toBe(
      "Please use your TU Dublin email (@mytudublin.ie)",
    );
  });

  it("never blames the email address for a server error", () => {
    expect(
      signInError({ code: "unexpected_failure", message: "Database error saving new user" }),
    ).toBe("We couldn't send the sign-in link. Try again in a minute.");
  });
});
