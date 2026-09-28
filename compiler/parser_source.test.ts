import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { parserSource } from "./parser_source.ts";
import {
  createFrontend,
  declarationRanges,
  type ParseRange,
  type PreparedSource,
} from "./syntax.ts";

// Frozen pre-optimization implementation: compare the exact parser input, not
// just successful parsing. This also catches any change in UTF-16 positions.
function previous(prepared: PreparedSource, range: ParseRange = {}) {
  const start = range.start ?? 0;
  const end = range.end ?? prepared.source.length;
  const neutral = prepared.source.slice(start, end).split("");
  for (const position of prepared.clauseMarkers) {
    if (position >= start && position + 5 <= end) {
      neutral[position - start + 4] = "E";
    }
  }
  for (
    let i = range.tokenStart ?? 0;
    i < (range.tokenEnd ?? prepared.tokens.length);
    i++
  ) {
    const token = prepared.tokens[i];
    if (token.type === "named" && token.kind === "INTEGER") {
      neutral.fill("0", token.span.start - start, token.span.end - start);
    }
  }
  return neutral.join("");
}

Deno.test("parser span builder preserves integers, Unicode, clauses and declaration slices", async () => {
  const frontend = await createFrontend();
  try {
    const declarations = [
      "// Unicode 🙂 café; numbers in comments: 4294967295",
      'const text = "🙂 where { 123 }"',
      "const high = 4_294_967_295",
      "const hex = 0xFFFF_FFFF",
      "const decimal = 2147483648",
      "const fraction = 1.25",
      "const bounded: U32 where { self < 100 } = 42",
      "const same = fn (value: U32 where { self < 1000 }) => value",
      "entry const result = fn () => do:",
      "  let value = 19",
      "  return @u32.add value 23",
      "",
    ];
    for (const separator of ["\n", "\r\n", "\r"]) {
      const prepared = frontend.prepare(declarations.join(separator));
      ok(prepared.clauseMarkers.length >= 2);
      equal(parserSource(prepared), previous(prepared));
      equal(parserSource(prepared).length, prepared.source.length);
      const ranges = declarationRanges(prepared);
      ok(ranges && ranges.length > 3);
      for (const { start, end } of ranges) {
        const range = {
          start: prepared.tokens[start].span.start,
          end: prepared.tokens[end - 1].span.end,
          tokenStart: start,
          tokenEnd: end,
        };
        equal(parserSource(prepared, range), previous(prepared, range));
      }
    }
    for (
      const source of [
        "",
        "\n",
        "// 🙂 only a comment\n",
        "const id = fn x => x\n",
      ]
    ) {
      const prepared = frontend.prepare(source);
      equal(parserSource(prepared), previous(prepared));
    }
  } finally {
    frontend.dispose();
  }
});

Deno.test("parser span builder matches the old representation on a large mixed module", async () => {
  const frontend = await createFrontend();
  try {
    const source = Array.from(
      { length: 2048 },
      (_, index) =>
        `// 🙂 ${index}\nconst n_${index}: U32 where { self < 4294967295 } = ${index}\n`,
    ).join("");
    const prepared = frontend.prepare(source);
    equal(parserSource(prepared), previous(prepared));
    for (const { start, end } of declarationRanges(prepared) ?? []) {
      const range = {
        start: prepared.tokens[start].span.start,
        end: prepared.tokens[end - 1].span.end,
        tokenStart: start,
        tokenEnd: end,
      };
      equal(parserSource(prepared, range), previous(prepared, range));
    }
  } finally {
    frontend.dispose();
  }
});
