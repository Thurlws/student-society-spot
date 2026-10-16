import { describe, expect, it } from "vitest";

import { signInError, signInFailureIsOurs } from "@/lib/auth";

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

  it("keeps the domain rules' own messages", () => {
    expect(signInError({ message: "Please use your university email address." })).toBe(
      "Please use your university email address.",
    );
    expect(signInError({ message: "Your new address has to be at the same university." })).toBe(
      "Your new address has to be at the same university.",
    );
  });

  it("explains a failed bot check", () => {
    expect(
      signInError({ code: "captcha_failed", message: "captcha protection: request disallowed" }),
    ).toMatch(/not a bot/);
  });

  it("never blames the email address for a server error", () => {
    expect(
      signInError({ code: "unexpected_failure", message: "Database error saving new user" }),
    ).toBe("We couldn't send the sign-in link. Try again in a minute.");
  });
});

describe("signInFailureIsOurs", () => {
  it("alerts on the project-wide email cap and on sending failures", () => {
    expect(
      signInFailureIsOurs({
        code: "over_email_send_rate_limit",
        message: "email rate limit exceeded",
      }),
    ).toBe(true);
    expect(signInFailureIsOurs({ message: "Error sending magic link email" })).toBe(true);
  });

  it("not on one person's cooldown, a busy network or a wrong address", () => {
    expect(
      signInFailureIsOurs({
        code: "over_email_send_rate_limit",
        message: "For security purposes, you can only request this after 42 seconds.",
      }),
    ).toBe(false);
    expect(signInFailureIsOurs({ code: "over_request_rate_limit", message: "Too many" })).toBe(
      false,
    );
    expect(signInFailureIsOurs({ message: "Please use your university email address." })).toBe(
      false,
    );
  });
});
