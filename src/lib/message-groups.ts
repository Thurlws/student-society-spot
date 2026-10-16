import { toDublin } from "@/lib/format";
import type { DiscussionMessage } from "@/lib/types";

/** A pause longer than this starts a new group, as in Discord. */
export const GROUP_GAP_MS = 7 * 60_000;

/** Messages one person sent in a row: shown under one name and avatar. */
export type MessageGroup = {
  key: string;
  authorId: string;
  author: string;
  /** Dublin date of the group, YYYY-MM-DD. */
  day: string;
  /** The first group of its day, which gets a date line above it. */
  startsDay: boolean;
  messages: DiscussionMessage[];
};

/**
 * Groups a channel's messages (oldest first). A new group starts when someone else writes,
 * after a pause of more than seven minutes, or on a new day in Dublin.
 */
export function groupMessages(messages: DiscussionMessage[]): MessageGroup[] {
  const groups: MessageGroup[] = [];
  let previous: DiscussionMessage | undefined;
  for (const m of messages) {
    const day = toDublin(m.createdAt).date;
    const last = groups.at(-1);
    const continues =
      !!last &&
      !!previous &&
      last.authorId === m.authorId &&
      last.day === day &&
      new Date(m.createdAt).getTime() - new Date(previous.createdAt).getTime() <= GROUP_GAP_MS;
    if (continues) last.messages.push(m);
    else
      groups.push({
        key: m.id,
        authorId: m.authorId,
        author: m.author,
        day,
        startsDay: last?.day !== day,
        messages: [m],
      });
    previous = m;
  }
  return groups;
}
