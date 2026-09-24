export interface SourceRange {
  readonly start: number;
  readonly end: number;
}

// This only finds conservative work boundaries, not tokens or valid syntax.
// Every slice still passes through Baba and the ordinary layout rules; any
// rejection falls back to a whole-file parse for canonical diagnostics.
export function sourceDeclarationRanges(
  source: string,
): SourceRange[] | undefined {
  const starts = [0];
  const pending: string[] = [];
  const closers: Readonly<Record<string, string>> = {
    "(": ")",
    "[": "]",
    "{": "}",
  };
  let quoted = false;
  let comment = false;
  let lineStart = true;
  let declaration = false;
  let attribute = false;
  for (let at = 0; at < source.length; at++) {
    const char = source[at];
    if (char === "\r" || char === "\n") {
      if (quoted) return undefined;
      comment = false;
      lineStart = true;
      continue;
    }
    if (comment) continue;
    if (quoted) {
      if (char === "\\") at++;
      else if (char === '"') quoted = false;
      continue;
    }
    if (lineStart && pending.length === 0) {
      const prefix = source.slice(at, at + 40);
      const tagged = /^#[ \t]*\[/.test(prefix);
      const header =
        /^(?:const|let|data|effect|type|infixl|infixr|infix|import)[ \t]/
          .test(prefix);
      if (tagged || header) {
        if (declaration && !attribute) starts.push(at);
        declaration = true;
        attribute = tagged;
      }
    }
    lineStart = false;
    if (char === "/" && source[at + 1] === "/") comment = true;
    else if (char === '"') quoted = true;
    else if (closers[char]) pending.push(closers[char]);
    else if (")]}".includes(char) && pending.pop() !== char) return undefined;
  }
  if (quoted || pending.length) return undefined;
  return starts.map((start, index) => ({
    start,
    end: starts[index + 1] ?? source.length,
  }));
}
