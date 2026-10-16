/**
 * The published address, for link previews (og:image needs a full URL). Change it with the
 * custom domain.
 */
export const SITE_URL = "https://student-society-spot.lovable.app";

export function pageHead(title: string, description: string) {
  const full = `${title} · SocConnect`;
  return {
    meta: [
      { title: full },
      { name: "description", content: description },
      { property: "og:title", content: full },
      { property: "og:description", content: description },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary_large_image" },
    ],
  };
}
