import { useEffect, useMemo, useRef } from "react";
import { useData } from "@/lib/api/store";
import { initialsOf } from "@/lib/auth";
import { dayLabel, formatDate, toDublin } from "@/lib/format";
import { groupMessages } from "@/lib/message-groups";
import type { DiscussionMessage } from "@/lib/types";
import { MessageActions } from "@/components/moderation";
import { cn } from "@/lib/utils";

/**
 * A channel's messages, oldest first, grouped by sender as in Discord: one name and avatar
 * for messages someone sends in a row, and a date line when the day changes. Keeps the
 * newest message in view.
 */
export function MessageList({
  channelId,
  messages,
  societyId,
  societyName,
}: {
  channelId: string | undefined;
  messages: DiscussionMessage[];
  societyId: string;
  societyName: string;
}) {
  const { user } = useData();
  const groups = useMemo(() => groupMessages(messages), [messages]);
  const scroller = useRef<HTMLDivElement>(null);
  const newest = messages.at(-1)?.id;

  useEffect(() => {
    const el = scroller.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, [channelId, newest]);

  return (
    <div ref={scroller} className="flex-1 overflow-y-auto px-3 py-4">
      {messages.length === 0 && (
        <p className="text-center text-sm text-muted-foreground">No messages yet. Say hello.</p>
      )}
      <ol aria-label="Messages">
        {groups.map((g) => (
          <li key={g.key} className="pt-3 first:pt-0">
            {g.startsDay && (
              <div
                role="separator"
                aria-label={dayLabel(g.day)}
                className="mb-3 flex items-center gap-3 px-2 text-xs font-medium text-muted-foreground"
              >
                <span className="h-px flex-1 bg-border" />
                {dayLabel(g.day)}
                <span className="h-px flex-1 bg-border" />
              </div>
            )}
            {g.messages.map((m, i) => {
              const at = toDublin(m.createdAt);
              const when = (
                <time dateTime={m.createdAt} title={`${formatDate(at.date)}, ${at.time}`}>
                  {at.time}
                </time>
              );
              return (
                <div
                  key={m.id}
                  className="group/msg flex gap-3 rounded-md px-2 py-0.5 focus-within:bg-muted/50 hover:bg-muted/50"
                >
                  <div className="w-8 shrink-0">
                    {i === 0 ? (
                      <span
                        aria-hidden
                        className={cn(
                          "mt-0.5 flex size-8 items-center justify-center rounded-full text-xs font-semibold",
                          m.authorId === user.id ? "bg-ink text-ink-foreground" : "bg-muted",
                        )}
                      >
                        {initialsOf(g.author)}
                      </span>
                    ) : (
                      <span className="invisible block pt-1 text-right text-[10px] tabular-nums text-muted-foreground group-focus-within/msg:visible group-hover/msg:visible">
                        {when}
                      </span>
                    )}
                  </div>
                  <div className="min-w-0 flex-1">
                    {i === 0 && (
                      <p className="text-sm">
                        <span className="font-semibold">{g.author}</span>{" "}
                        <span className="text-xs text-muted-foreground">{when}</span>
                      </p>
                    )}
                    <p className="whitespace-pre-line break-words text-sm text-foreground/90">
                      {m.body}
                    </p>
                  </div>
                  {/* Shown on hover or focus where there's a mouse; always on touch screens. */}
                  <div className="shrink-0 opacity-0 transition-opacity group-focus-within/msg:opacity-100 group-hover/msg:opacity-100 has-[[data-state=open]]:opacity-100 [@media(hover:none)]:opacity-100">
                    <MessageActions message={m} societyId={societyId} societyName={societyName} />
                  </div>
                </div>
              );
            })}
          </li>
        ))}
      </ol>
    </div>
  );
}
