/** Saved interests with taps not yet saved on top: true adds an interest, false removes it. */
export function withTaps(saved: string[], taps: Record<string, boolean>) {
  return [
    ...saved.filter((i) => taps[i] !== false),
    ...Object.keys(taps).filter((i) => taps[i] && !saved.includes(i)),
  ];
}
