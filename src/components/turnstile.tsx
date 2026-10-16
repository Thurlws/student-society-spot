import { useEffect, useImperativeHandle, useRef, type Ref } from "react";
import { TURNSTILE_SITE_KEY } from "@/lib/turnstile";

type TurnstileApi = {
  render: (el: HTMLElement, options: Record<string, unknown>) => string;
  reset: (id: string) => void;
  remove: (id: string) => void;
};

declare global {
  interface Window {
    turnstile?: TurnstileApi;
  }
}

let script: Promise<TurnstileApi> | null = null;

/** Loads Cloudflare's script once per page, on the pages that show the check. */
function loadTurnstile() {
  script ??= new Promise<TurnstileApi>((resolve, reject) => {
    if (window.turnstile) return resolve(window.turnstile);
    const el = document.createElement("script");
    el.src = "https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit";
    el.async = true;
    el.onload = () => (window.turnstile ? resolve(window.turnstile) : reject(new Error("no api")));
    el.onerror = () => {
      script = null;
      reject(new Error("Cloudflare's bot check didn't load."));
    };
    document.head.appendChild(el);
  });
  return script;
}

export type TurnstileHandle = { reset: () => void };

/**
 * Cloudflare Turnstile: shows nothing unless Cloudflare wants the person to tick a box, and
 * hands over a one-time token that Supabase Auth checks with each sign-in email request.
 * Renders nothing when no site key is set.
 */
export function Turnstile({
  onToken,
  onError,
  ref,
}: {
  onToken: (token: string | null) => void;
  onError: () => void;
  ref?: Ref<TurnstileHandle>;
}) {
  const box = useRef<HTMLDivElement>(null);
  const id = useRef<string | null>(null);
  const api = useRef<TurnstileApi | null>(null);
  // The latest callbacks, without re-rendering the widget when they change.
  const handlers = useRef({ onToken, onError });
  handlers.current = { onToken, onError };

  useImperativeHandle(ref, () => ({
    reset: () => {
      handlers.current.onToken(null);
      if (api.current && id.current) api.current.reset(id.current);
    },
  }));

  useEffect(() => {
    if (!TURNSTILE_SITE_KEY) return;
    let gone = false;
    loadTurnstile()
      .then((t) => {
        if (gone || !box.current) return;
        api.current = t;
        id.current = t.render(box.current, {
          sitekey: TURNSTILE_SITE_KEY,
          action: "sign-in",
          appearance: "interaction-only",
          size: "flexible",
          theme: "light",
          callback: (token: string) => handlers.current.onToken(token),
          "expired-callback": () => handlers.current.onToken(null),
          "error-callback": () => {
            handlers.current.onToken(null);
            handlers.current.onError();
          },
        });
      })
      .catch(() => !gone && handlers.current.onError());
    return () => {
      gone = true;
      if (api.current && id.current) api.current.remove(id.current);
      id.current = null;
    };
  }, []);

  if (!TURNSTILE_SITE_KEY) return null;
  return <div ref={box} className="empty:hidden" />;
}
