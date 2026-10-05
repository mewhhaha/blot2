import type { CompactFrontendProgram } from "@mewhhaha/baba/runtime/webgpu";
import schema from "../generated/wasm/cst-schema.json" with { type: "json" };

// Preserve adjacent call and index boundaries for the formatter.
export function postfixStarts(program: CompactFrontendProgram, source: string) {
  const starts = new Set<number>();
  let previousEnd = -1;
  for (let token = 0; token < program.tokens.length; token += 4) {
    const kind = schema.tokens[program.tokens[token + 3]];
    if (kind === "WHITESPACE" || kind === "COMMENT") continue;
    const start = program.tokens[token + 1];
    if (
      previousEnd === start &&
      (source[start] === "[" || source[start] === "(")
    ) starts.add(start);
    previousEnd = program.tokens[token + 2];
  }
  return starts;
}
