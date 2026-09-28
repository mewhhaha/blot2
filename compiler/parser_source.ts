import type { ParseRange, PreparedSource } from "./syntax.ts";

// Baba parses INTEGER tokens as signed I32. Neutralize just those spans while
// leaving the original source available for CST text and Blot's U32 policy.
// Slices also preserve UTF-16 offsets, including astral Unicode and CRLF.
export function parserSource(
  prepared: PreparedSource,
  range: ParseRange = {},
): string {
  const start = range.start ?? 0;
  const end = range.end ?? prepared.source.length;
  const parts: string[] = [];
  let position = start;
  // Both marker positions and token spans are already sorted by the lexer.
  // Binary search keeps declaration-sized reparses from scanning old markers.
  let low = 0, high = prepared.clauseMarkers.length;
  while (low < high) {
    const middle = (low + high) >>> 1;
    if (prepared.clauseMarkers[middle] < start) low = middle + 1;
    else high = middle;
  }
  let marker = low;
  const markersBefore = (limit: number) => {
    while (marker < prepared.clauseMarkers.length) {
      const at = prepared.clauseMarkers[marker];
      if (at >= limit || at + 5 > end) break;
      parts.push(prepared.source.slice(position, at + 4), "E");
      position = at + 5;
      marker++;
    }
  };
  for (
    let index = range.tokenStart ?? 0;
    index < (range.tokenEnd ?? prepared.tokens.length);
    index++
  ) {
    const token = prepared.tokens[index];
    if (token.type !== "named" || token.kind !== "INTEGER") continue;
    const from = Math.max(start, token.span.start);
    const to = Math.min(end, token.span.end);
    if (from >= to) continue;
    markersBefore(from);
    parts.push(prepared.source.slice(position, from), "0".repeat(to - from));
    position = to;
  }
  markersBefore(end);
  if (parts.length === 0) return prepared.source.slice(start, end);
  parts.push(prepared.source.slice(position, end));
  return parts.join("");
}
