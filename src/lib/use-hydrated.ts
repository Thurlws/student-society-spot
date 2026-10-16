import { useSyncExternalStore } from "react";

const subscribe = () => () => {};

/**
 * False on the server and while the page hydrates, true after. Buttons that only work once
 * the page's code has loaded use it to stay disabled until then, instead of doing nothing
 * (or submitting the form natively and reloading the page) on a slow connection.
 */
export function useHydrated() {
  return useSyncExternalStore(
    subscribe,
    () => true,
    () => false,
  );
}
