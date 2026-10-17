/**
 * New messages per channel since you last looked, counted on this device. The newest message
 * time you've seen in each channel lives in localStorage (DEVICE_STORAGE in privacy.ts) and
 * goes when you sign out.
 */
import type { DiscussionMessage } from "./types";

export const READ_KEY = "socconnect-read";

/** Channel id → the time of the newest message you've seen there. */
export type ReadMarks = Record<string, string>;

export function loadMarks(): ReadMarks {
  try {
    const m: unknown = JSON.parse(localStorage.getItem(READ_KEY) ?? "{}");
    return m && typeof m === "object" ? (m as ReadMarks) : {};
  } catch {
    return {};
  }
}

export function saveMarks(marks: ReadMarks) {
  try {
    localStorage.setItem(READ_KEY, JSON.stringify(marks));
  } catch {
    // Private windows and full storage: counts just start over next time.
  }
}

export function clearMarks() {
  try {
    localStorage.removeItem(READ_KEY);
  } catch {
    // Nothing kept, nothing to clear.
  }
}

/**
 * The marks after showing these channels (id → newest message time, "" for none): a channel
 * seen for the first time starts with nothing new, and the open one is read to its newest
 * message. The same object when nothing changed.
 */
export function nextMarks(marks: ReadMarks, newest: Record<string, string>, open?: string) {
  let next = marks;
  for (const [id, at] of Object.entries(newest))
    if (marks[id] === undefined || (id === open && at > marks[id]!)) next = { ...next, [id]: at };
  return next;
}

/** Messages from other people in a channel since its mark; none before it has one. */
export function unreadIn(
  messages: Pick<DiscussionMessage, "channelId" | "authorId" | "createdAt">[],
  channelId: string,
  mark: string | undefined,
  me: string,
) {
  if (mark === undefined) return 0;
  return messages.filter(
    (m) => m.channelId === channelId && m.authorId !== me && m.createdAt > mark,
  ).length;
}
