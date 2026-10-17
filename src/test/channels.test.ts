import { describe, expect, it } from "vitest";
import { channelInput, channelName } from "@/lib/validation";

describe("Channel names", () => {
  // The same rule as private.channel_name in migration 0034, so the form shows what's saved.
  it("cleans a name into lower case letters, numbers and dashes", () => {
    expect(channelName("  Kit & Lifts! ")).toBe("kit-lifts");
    expect(channelName("AGM 2026")).toBe("agm-2026");
    expect(channelName("--notices--")).toBe("notices");
  });

  it("refuses names with nothing usable, or too long", () => {
    const check = (name: string) =>
      channelInput.safeParse({ name, description: "", committeeOnly: false });
    expect(check("!!!").success).toBe(false);
    expect(check("a".repeat(31)).success).toBe(false);
    expect(check("Kit & Lifts").data?.name).toBe("kit-lifts");
  });
});
