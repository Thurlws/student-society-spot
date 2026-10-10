import { useSyncExternalStore } from "react";

export type Theme = "light" | "dark";
const KEY = "socconnect-theme";

function current(): Theme {
  if (typeof document === "undefined") return "light";
  return document.documentElement.classList.contains("dark") ? "dark" : "light";
}

export function applyTheme(theme: Theme) {
  document.documentElement.classList.toggle("dark", theme === "dark");
  document.documentElement.style.colorScheme = theme;
  try {
    localStorage.setItem(KEY, theme);
  } catch {
    /* private mode: keep the in-memory choice */
  }
  window.dispatchEvent(new Event("themechange"));
}

export function toggleTheme() {
  applyTheme(current() === "dark" ? "light" : "dark");
}

function subscribe(cb: () => void) {
  window.addEventListener("themechange", cb);
  return () => window.removeEventListener("themechange", cb);
}

/** Current theme; updates when toggled. SSR-safe (always "light" on the server). */
export function useTheme(): Theme {
  return useSyncExternalStore(subscribe, current, () => "light");
}

/** Inline script for the document head: applies the saved (or system) theme before first paint. */
export const themeInitScript = `(function(){try{var t=localStorage.getItem("${KEY}");if(t!=="dark"&&t!=="light"){t=window.matchMedia("(prefers-color-scheme: dark)").matches?"dark":"light";}var d=document.documentElement;d.classList.toggle("dark",t==="dark");d.style.colorScheme=t;}catch(e){}})();`;
