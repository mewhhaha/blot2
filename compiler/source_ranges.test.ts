import { deepStrictEqual as equal } from "node:assert/strict";
import { sourceDeclarationRanges } from "./source_ranges.ts";

Deno.test("source partitions keep attributes, delimiters, escaped strings and comments together", () => {
  const first = '// fn ignored\nconst text = "\\"[ // not a comment"\n';
  const second =
    "#[component]\n// attached attribute\n#[other]\ndata Pair = Pair {\n  first: U32,\n  second: U32,\n}\n";
  const third =
    "export fn answer () => do:\n  let values = [\n    1, // )\n    2,\n  ]\n  return 42\n";
  for (const ending of ["\n", "\r\n", "\r"]) {
    const chunks = [first, second, third].map((chunk) =>
      chunk.replaceAll("\n", ending)
    );
    const source = chunks.join("");
    equal(
      sourceDeclarationRanges(source)?.map((range) =>
        source.slice(range.start, range.end)
      ),
      chunks,
    );
  }
});

Deno.test("source partitions defer malformed delimiters and unterminated strings to the full parser", () => {
  for (
    const source of [
      'const text = "open\nfn next () => 1',
      "fn bad () => (1]\nfn next () => 2",
      "const bad = [1\nfn next () => 2",
    ]
  ) {
    equal(sourceDeclarationRanges(source), undefined);
  }
});

Deno.test("empty and indivisible sources stay local", () => {
  for (const source of ["", "// comment", "fn answer () => 42\n"]) {
    equal(sourceDeclarationRanges(source), [{ start: 0, end: source.length }]);
  }
});
