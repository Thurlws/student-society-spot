import { describe, expect, it } from "vitest";
import { search } from "@/lib/search";

const societies = [
  { name: "European Law Students' Association (ELSA)", tags: "ELSA Career" },
  { name: "International Students Society", tags: "ISS Culture Social" },
  { name: "Dental Society", tags: "DentSoc Science" },
  { name: "Cumann Gaelach", tags: "Gaeilge Éire Culture" },
  { name: "Independent Film Society", tags: "Film Creative" },
];
const names = (q: string) =>
  search(
    societies,
    q,
    (s) => s.name,
    (s) => s.tags,
  ).map((s) => s.name);

describe("search", () => {
  it("finds Dental Society from 'Dental', and nothing that only has the letters in order", () => {
    expect(names("Dental")).toEqual(["Dental Society"]);
    expect(names("dental s")).toEqual(["Dental Society"]);
  });

  it("ranks a name that starts with the query, then a word, then anywhere", () => {
    // Ties go alphabetically.
    expect(names("dent")).toEqual([
      "Dental Society",
      "European Law Students' Association (ELSA)",
      "Independent Film Society",
      "International Students Society",
    ]);
    expect(names("soc")).toEqual([
      "Dental Society",
      "Independent Film Society",
      "International Students Society",
      "European Law Students' Association (ELSA)",
    ]);
  });

  it("searches short names and tags, without caring about accents or case", () => {
    expect(names("eire")).toEqual(["Cumann Gaelach"]);
    expect(names("CULTURE")).toEqual(["Cumann Gaelach", "International Students Society"]);
    expect(names("film creative")).toEqual(["Independent Film Society"]);
  });

  it("keeps everything, in its order, for an empty query", () => {
    expect(names("  ")).toEqual(societies.map((s) => s.name));
  });
});
