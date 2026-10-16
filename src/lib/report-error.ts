import { reportClientError } from "./monitoring.functions";

/** Sends a browser error to the error tracker, if one is set up. Fire and forget. */
export function reportFromBrowser(error: unknown, area: "page" | "sign-in") {
  const e =
    error instanceof Error
      ? error
      : new Error(
          typeof error === "object" && error && "message" in error
            ? String((error as { message: unknown }).message)
            : String(error),
        );
  void reportClientError({
    data: {
      name: e.name.slice(0, 100),
      message: e.message.slice(0, 2000),
      stack: e.stack?.slice(0, 8000),
      route: window.location.pathname.slice(0, 300),
      area,
    },
  }).catch(() => {});
}
