import { describe, expect, it } from "vitest";
import { withTaps } from "@/lib/interests";

describe("withTaps", () => {
  it("shows taps before they're saved", () => {
    expect(withTaps(["Music", "Sport"], {})).toEqual(["Music", "Sport"]);
    expect(withTaps(["Music", "Sport"], { Sport: false, Games: true })).toEqual(["Music", "Games"]);
  });
  it("leaves a tap that matches what's saved alone", () => {
    expect(withTaps(["Music"], { Music: true, Games: false })).toEqual(["Music"]);
  });
});
