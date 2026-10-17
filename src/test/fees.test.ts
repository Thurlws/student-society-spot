import { describe, expect, it } from "vitest";
import { formatEuro } from "@/lib/format";
import { membershipFeeInput } from "@/lib/validation";

describe("Membership fees", () => {
  it("reads the amount a committee types, in cents", () => {
    const cents = (v: string) => membershipFeeInput.safeParse(v).data;
    expect(cents("5")).toBe(500);
    expect(cents("7.50")).toBe(750);
    expect(cents("€ 7,5")).toBe(750);
    expect(cents("")).toBeNull();
  });

  it("refuses what the database would (0035: €0.01 to €500)", () => {
    const ok = (v: string) => membershipFeeInput.safeParse(v).success;
    expect(ok("0")).toBe(false);
    expect(ok("500.01")).toBe(false);
    expect(ok("five")).toBe(false);
    expect(ok("500")).toBe(true);
  });

  it("shows euros without empty cents", () => {
    expect(formatEuro(500)).toBe("€5");
    expect(formatEuro(750)).toBe("€7.50");
    expect(formatEuro(5)).toBe("€0.05");
  });
});
