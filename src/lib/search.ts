/** Lower case without accents, so "eire" finds "Éire" and "cumann" finds "Cumann". */
const fold = (s: string) => s.normalize("NFD").replace(/\p{M}/gu, "").toLowerCase();
const escape = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

/**
 * How well a query matches a name, 0 for not at all. Every word of the query has to appear in
 * the name or the other text (short name, tags); then the name starting with the query ranks
 * first, a word of the name starting with it next, the query anywhere in the name after that.
 * Plain words, not letters in order: "dental" doesn't match "Students' Association, Law".
 */
export function matchScore(name: string, other: string, query: string) {
  const q = fold(query).trim().replace(/\s+/g, " ");
  if (!q) return 1;
  const n = fold(name);
  const all = `${n} ${fold(other)}`;
  if (!q.split(" ").every((w) => all.includes(w))) return 0;
  if (n.startsWith(q)) return 4;
  if (new RegExp(`(^|[^\\p{L}\\p{N}])${escape(q)}`, "u").test(n)) return 3;
  return n.includes(q) ? 2 : 1;
}

/** Items matching the query, best first and then by name; all of them, in order, without one. */
export function search<T>(
  items: T[],
  query: string,
  name: (t: T) => string,
  other: (t: T) => string,
) {
  if (!query.trim()) return items;
  return items
    .map((t) => ({ t, score: matchScore(name(t), other(t), query) }))
    .filter((x) => x.score > 0)
    .sort((a, b) => b.score - a.score || name(a.t).localeCompare(name(b.t)))
    .map((x) => x.t);
}
