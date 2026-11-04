import { type ParseRange, type PreparedSource, SourceError } from "./syntax.ts";

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
  const replace = (from: number, to: number, value: string) => {
    const left = Math.max(start, from), right = Math.min(end, to);
    if (left >= right) return;
    markersBefore(left);
    parts.push(
      prepared.source.slice(position, left),
      value.slice(left - from, right - from),
    );
    position = right;
  };
  let moduleDeclaration = false;
  let declarationStart = true;
  let delimiters = 0;
  let indentation = 0;
  for (
    let index = range.tokenStart ?? 0;
    index < (range.tokenEnd ?? prepared.tokens.length);
    index++
  ) {
    const token = prepared.tokens[index];
    // Normalize the constructor sigil for the shared CST grammar without
    // changing spans or the original text used by formatting and diagnostics.
    if (
      token.text === "$" &&
      prepared.tokens[index + 1]?.span.start === token.span.end &&
      /^[A-Za-z_]/.test(prepared.tokens[index + 1]?.text ?? "")
    ) replace(token.span.start, token.span.end, "#");
    if (token.type === "named" && token.kind === "INTEGER") {
      replace(
        token.span.start,
        token.span.end,
        "0".repeat(token.span.end - token.span.start),
      );
    }
    // Declaration words remain ordinary names outside a top-level header.
    // Same-width markers preserve original CST text and source offsets.
    const topLevel = delimiters === 0 && indentation === 0;
    if (topLevel && declarationStart) {
      if (["privatE", "opaquE", "exporT", "impL"].includes(token.text)) {
        throw new SourceError(
          "reserved_declaration_marker",
          "Use ordinary declaration spellings",
          prepared.originalOffsets[token.span.start],
          prepared.originalOffsets[token.span.end],
        );
      }
      if (token.text === "private") {
        replace(token.span.end - 1, token.span.end, "E");
      } else {
        declarationStart = false;
        if (
          token.text === "opaque" && prepared.tokens[index + 1]?.text === "type"
        ) {
          replace(token.span.end - 1, token.span.end, "E");
        } else if (
          token.text === "export" && prepared.tokens[index + 1]?.text === "{"
        ) {
          replace(token.span.end - 1, token.span.end, "T");
          moduleDeclaration = true;
        } else if (token.text === "impl") {
          replace(token.span.end - 1, token.span.end, "L");
        } else if (token.text === "import") moduleDeclaration = true;
      }
    }
    if (token.text === "\uE000" && topLevel) {
      declarationStart = true;
      moduleDeclaration = false;
    }
    if (["(", "[", "{"].includes(token.text)) delimiters++;
    else if ([")", "]", "}"].includes(token.text)) delimiters--;
    if (token.text === "\uE001") indentation++;
    else if (token.text === "\uE002") {
      indentation--;
      if (indentation === 0 && delimiters === 0) declarationStart = true;
    }
    if (
      moduleDeclaration && token.text === "froM" &&
      prepared.tokens[index + 1]?.text.startsWith('"')
    ) {
      throw new SourceError(
        "reserved_import_marker",
        "Use 'from' in an import or export declaration",
        prepared.originalOffsets[token.span.start],
        prepared.originalOffsets[token.span.end],
      );
    }
    if (
      moduleDeclaration && token.text === "from" &&
      prepared.tokens[index + 1]?.text.startsWith('"')
    ) {
      replace(token.span.start + 3, token.span.start + 4, "M");
    }
    if (token.text === ".") {
      const previous = prepared.tokens[index - 1];
      if (
        previous?.span.end !== token.span.start ||
        !/[a-zA-Z0-9_\])}]/.test(prepared.source[token.span.start - 1] ?? "")
      ) replace(token.span.start, token.span.end, "·");
    }
  }
  markersBefore(end);
  if (parts.length === 0) return prepared.source.slice(start, end);
  parts.push(prepared.source.slice(position, end));
  return parts.join("");
}
