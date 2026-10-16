import { describe, expect, it } from "vitest";
import { importTemplate, parseCsv, readSocietyCsv } from "@/lib/society-import";

describe("Society import file", () => {
  it("parses quoted fields, doubled quotes and line breaks", () => {
    expect(parseCsv('a,b\r\n"x, y","say ""hi""\nthere"\n\n')).toEqual([
      ["a", "b"],
      ["x, y", 'say "hi"\nthere'],
    ]);
  });

  it("reads columns whatever their case or spacing, and lists interests", () => {
    const { rows, problems } = readSocietyCsv(
      "\uFEFFID,Name,Short name,Interests,Notes\n7,Chess Society,Chess,Gaming; Science,ignored\n",
    );
    expect(problems).toEqual(["Columns that will be ignored: Notes."]);
    expect(rows).toEqual([
      { id: "7", name: "Chess Society", short_name: "Chess", interests: ["Gaming", "Science"] },
    ]);
  });

  it("numbers problems by data row, like the database does", () => {
    const { problems } = readSocietyCsv(
      "id,name,join_url\n1,Chess,https://ok.ie\n1,X,http://not-https.ie\n",
    );
    expect(problems).toEqual([
      "Row 2: the name needs 2 to 100 characters.",
      "Row 2: join url must start with https://.",
      "Row 2: the id 1 is in the file twice.",
    ]);
  });

  it("needs a name column and at least one society", () => {
    expect(readSocietyCsv("id,title\n").problems).toEqual([
      "The first row needs a name column.",
      "Columns that will be ignored: title.",
      "There are no societies under the header row.",
    ]);
  });

  it("offers a template that reads back cleanly", () => {
    const { rows, problems } = readSocietyCsv(importTemplate());
    expect(problems).toEqual([]);
    expect(rows[0]?.name).toBe("Chess Society");
  });
});
