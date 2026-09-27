import { deepStrictEqual as equal } from "node:assert/strict";
import { sourceDeclarationRanges } from "./source_ranges.ts";

Deno.test("source partitions keep attributes, delimiters, escaped strings and comments together", () => {
  const first = '// fn ignored\nconst text = "\\"[ // not a comment"\n';
  const second =
    "#[component]\n// attached attribute\n#[other]\ndata Pair = Pair {\n  first: U32,\n  second: U32,\n}\n";
  const third =
    "const answer = fn () => do:\n  let values = [\n    1, // )\n    2,\n  ]\n  return 42\n";
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
      'const text = "open\nconst next = fn () => 1',
      "const bad = fn () => (1]\nconst next = fn () => 2",
      "const bad = [1\nconst next = fn () => 2",
    ]
  ) {
    equal(sourceDeclarationRanges(source), undefined);
  }
});

Deno.test("empty and indivisible sources stay local", () => {
  for (const source of ["", "// comment", "const answer = fn () => 42\n"]) {
    equal(sourceDeclarationRanges(source), [{ start: 0, end: source.length }]);
  }
});

Deno.test("entry declarations start work ranges, while entry elsewhere does not", () => {
  const chunks = [
    "const entry = fn entry => entry\n",
    "#[tagged]\nentry const create = fn () => 1\n",
    "entry let count: U32 = 2\n",
    "const read = fn value => do:\n  let entry = value\n  return entry\n",
  ];
  const source = chunks.join("");
  equal(
    sourceDeclarationRanges(source)?.map((range) =>
      source.slice(range.start, range.end)
    ),
    chunks,
  );
});

Deno.test("expression tags and same-line entry declarations stay in one work range", () => {
  const chunks = [
    "const decorate = fn amount => fn value => value + amount\n",
    "#[decorate 1]\n#[fn value => value * 2] entry const answer = 20\n",
    "#[decorate 2] entry let runtime = 40\n",
    "entry const other = 42\n",
  ];
  const source = chunks.join("");
  equal(
    sourceDeclarationRanges(source)?.map((range) =>
      source.slice(range.start, range.end)
    ),
    chunks,
  );
});

Deno.test("adjacent same-line tagged declarations split after nested tag brackets", () => {
  const chunks = [
    "#[fn value => [value][0]] entry const first = 41\n",
    "#[fn value => value + 1] entry const second = 41\n",
    "entry const third = 42\n",
  ];
  const source = chunks.join("");
  equal(
    sourceDeclarationRanges(source)?.map((range) =>
      source.slice(range.start, range.end)
    ),
    chunks,
  );
});

Deno.test("multiline qualified clauses and open rows stay with adjacent declarations", () => {
  const chunks = [
    'const first: a -> a ! {Reader.ask | e} where {\n  associated "add" a a a ! {| e},\n  effect_rep ! {Reader.ask | e},\n} = fn value => value + value\n',
    "#[fn value => value] entry const answer: U32 where { type_rep U32 } = 42\n",
    "entry const next = 43\n",
  ];
  const source = chunks.join("");
  equal(
    sourceDeclarationRanges(source)?.map((range) =>
      source.slice(range.start, range.end)
    ),
    chunks,
  );
});
