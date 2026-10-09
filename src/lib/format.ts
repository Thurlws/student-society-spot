import { DEMO_TODAY } from "@/data/mock";

const NOW = new Date(`${DEMO_TODAY}T12:00:00`);

export function formatDate(iso: string, opts: Intl.DateTimeFormatOptions = { weekday: "short", day: "numeric", month: "short" }) {
  return new Date(`${iso.slice(0, 10)}T12:00:00`).toLocaleDateString("en-GB", opts);
}

export function dayParts(iso: string) {
  const d = new Date(`${iso}T12:00:00`);
  return {
    day: d.toLocaleDateString("en-GB", { day: "2-digit" }),
    month: d.toLocaleDateString("en-GB", { month: "short" }).toUpperCase(),
  };
}

export function timeAgo(iso: string) {
  const diff = (NOW.getTime() - new Date(iso).getTime()) / 1000;
  if (diff < 60) return "just now";
  if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
  const days = Math.floor(diff / 86400);
  return days === 1 ? "yesterday" : `${days}d ago`;
}

export function daysUntil(iso: string) {
  const d = new Date(`${iso}T12:00:00`).getTime();
  return Math.round((d - NOW.getTime()) / 86400000);
}

export function demoNowIso() {
  return `${DEMO_TODAY}T12:00:00`;
}

export function greeting() {
  return "Good afternoon";
}
