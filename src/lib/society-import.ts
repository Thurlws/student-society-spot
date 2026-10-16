// Reads a university's society list (CSV, as a spreadsheet saves it) for import_societies
// (migration 0028). The database checks every row again; this only gives early, row-numbered
// feedback in the admin page.

/** RFC 4180 CSV: quoted fields, doubled quotes, commas and line breaks inside quotes. */
export function parseCsv(text: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [];
  let field = "";
  let quoted = false;
  const s = text.replace(/^\uFEFF/, "");
  for (let i = 0; i < s.length; i++) {
    const c = s[i]!;
    if (quoted) {
      if (c === '"' && s[i + 1] === '"') {
        field += '"';
        i++;
      } else if (c === '"') quoted = false;
      else field += c;
    } else if (c === '"') quoted = true;
    else if (c === ",") {
      row.push(field);
      field = "";
    } else if (c === "\n" || c === "\r") {
      if (c === "\r" && s[i + 1] === "\n") i++;
      row.push(field);
      rows.push(row);
      row = [];
      field = "";
    } else field += c;
  }
  if (field !== "" || row.length) {
    row.push(field);
    rows.push(row);
  }
  return rows.filter((r) => r.some((f) => f.trim() !== ""));
}

export const IMPORT_COLUMNS = [
  "id",
  "name",
  "short_name",
  "slug",
  "category",
  "tagline",
  "description",
  "meets",
  "campus",
  "requires_approval",
  "join_url",
  "official_url",
  "contact_email",
  "logo_url",
  "banner_url",
  "interests",
] as const;
type Column = (typeof IMPORT_COLUMNS)[number];
export type ImportRow = Partial<Record<Exclude<Column, "interests">, string>> & {
  interests?: string[];
};

/** A header cell to a column name: "Short name", "short-name" and "SHORT_NAME" all work. */
const columnOf = (h: string) => {
  const k = h
    .trim()
    .toLowerCase()
    .replace(/[\s-]+/g, "_");
  return (IMPORT_COLUMNS as readonly string[]).includes(k) ? (k as Column) : null;
};

const https = /^https:\/\/\S+$/;

/** Rows for import_societies, plus the problems found, numbered like the database does (first data row = 1). */
export function readSocietyCsv(text: string) {
  const [header, ...body] = parseCsv(text);
  const problems: string[] = [];
  if (!header) return { rows: [], problems: ["The file is empty."] };
  const cols = header.map(columnOf);
  if (!cols.includes("name")) problems.push("The first row needs a name column.");
  const unknown = header.filter((_, i) => !cols[i]).map((h) => h.trim());
  if (unknown.filter(Boolean).length)
    problems.push(`Columns that will be ignored: ${unknown.filter(Boolean).join(", ")}.`);
  const seen = new Set<string>();
  const rows: ImportRow[] = body.map((cells, n) => {
    const row: ImportRow = {};
    cols.forEach((c, i) => {
      const v = (cells[i] ?? "").trim();
      if (!c || !v) return;
      if (c === "interests")
        row.interests = v
          .split(/[;,]/)
          .map((x) => x.trim())
          .filter(Boolean);
      else row[c] = v;
    });
    const at = `Row ${n + 1}`;
    const name = row.name ?? "";
    if (name.length < 2 || name.length > 100)
      problems.push(`${at}: the name needs 2 to 100 characters.`);
    if ((row.short_name ?? "").length > 30)
      problems.push(`${at}: the short name can be up to 30 characters.`);
    if ((row.tagline ?? "").length > 140)
      problems.push(`${at}: the tagline can be up to 140 characters.`);
    if ((row.description ?? "").length > 2000)
      problems.push(`${at}: the description can be up to 2,000 characters.`);
    for (const k of ["join_url", "official_url", "logo_url", "banner_url"] as const)
      if (row[k] && !https.test(row[k]!))
        problems.push(`${at}: ${k.replace("_", " ")} must start with https://.`);
    if (row.id) {
      if (seen.has(row.id)) problems.push(`${at}: the id ${row.id} is in the file twice.`);
      seen.add(row.id);
    }
    return row;
  });
  if (!rows.length) problems.push("There are no societies under the header row.");
  if (rows.length > 500) problems.push("Import at most 500 societies at a time.");
  return { rows, problems };
}

/** A file with the header and one example row, for admins to fill in. */
export function importTemplate() {
  const example = [
    "chess-01",
    "Chess Society",
    "Chess",
    "",
    "Gaming",
    "Casual and competitive chess",
    "We meet every week for casual games and run a ladder for anyone who wants it.",
    "Wednesdays 6pm, Room A12",
    "City",
    "no",
    "https://example.ie/join/chess",
    "https://example.ie/societies/chess",
    "chess@example.ie",
    "",
    "",
    "Gaming; Science",
  ];
  const quote = (v: string) => (/[",\n]/.test(v) ? `"${v.replace(/"/g, '""')}"` : v);
  return [IMPORT_COLUMNS.join(","), example.map(quote).join(",")].join("\n") + "\n";
}
