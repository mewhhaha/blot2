import {
  deepStrictEqual as equal,
  ok,
  rejects,
  throws,
} from "node:assert/strict";
import { createSourceCompiler } from "./source.ts";
import { createNativeCompiler } from "./native.ts";
import { createNativeIncrementalCompiler } from "./native_incremental.ts";
import { loadSourceProject } from "./source_project.ts";
import { SourceError } from "./syntax.ts";

async function exportsOf(bytes: Uint8Array<ArrayBuffer>) {
  ok(WebAssembly.validate(bytes));
  return (await WebAssembly.instantiate(bytes)).instance.exports;
}

Deno.test("value patterns match constants, parameters and lexical bindings in JS and native", async () => {
  const js = await createSourceCompiler();
  const native = await createNativeCompiler({ threads: 4 });
  const source = `
entry const tab = @u32.add 0x110100 4
data Event = #Event { key: U32 }
const record = fn actual => do:
  let expected = 7
  return case actual of
    #Event { key: ^expected } => 42
    _ => 0
entry const key_action = fn code => case code of
  ^tab => 42
  _ => 0
entry const inferred = fn expected => case 7 of
  ^expected => 42
  _ => 0
const compare = fn (expected: U32) => fn actual => case actual of
  ^expected => 42
  _ => 0
const nested = fn actual => do:
  let expected = 7
  return case actual of
    #Some (expected, ^expected) => expected
    _ => 0
const guarded = fn actual => do:
  let expected = 7
  let #Some ^expected = actual else:
    return 0
  return 42
const conditional = fn actual => do:
  let expected = 7
  if let #Some ^expected = actual:
    return 42
  return 0
const make_matcher = fn (expected: U32) => fn actual => case actual of
  ^expected => 42
  _ => 0
entry const captured = make_matcher 7
entry const boolean = fn (actual: Bool) => do:
  let expected = #True
  return case actual of
    ^expected => 42
    _ => 0
entry const correlated = fn actual => do:
  let expected = 7
  return case actual, actual of
    ^expected, 8 => 0
    _, ^expected => 42
    _, _ => 0
entry const evaluated_record = record (#Event { key: 7 })
entry const evaluated = key_action tab
entry const evaluated_capture = captured 7
entry const evaluated_nested = nested (#Some (42, 7))
entry const evaluated_miss = nested (#Some (7, 42))
entry const evaluated_guard = guarded (#Some 7)
entry const evaluated_bool = boolean #False
entry const record_key = fn code => record (#Event { key: code })
entry const inferred_key = fn code => inferred code
entry const key = fn code => key_action code
entry const parameter = fn actual => compare 7 actual
entry const shadow = fn actual => nested (#Some (42, actual))
entry const guard = fn actual => guarded (#Some actual)
entry const condition = fn actual => conditional (#Some actual)
entry const closure = fn actual => (make_matcher 7) actual
entry const const_closure = fn actual => captured actual
entry const flag = fn actual => boolean (actual == 7)
entry const row = fn actual => correlated actual
`;
  try {
    const artifact = js.compile(source);
    equal(await native.compile(source), artifact);
    const exports = await exportsOf(artifact.bytes);
    for (
      const name of [
        "inferred_key",
        "record_key",
        "parameter",
        "guard",
        "condition",
        "closure",
        "const_closure",
        "flag",
        "row",
      ]
    ) {
      equal((exports[name] as CallableFunction)(7), 42, name);
      equal((exports[name] as CallableFunction)(8), 0, name);
    }
    equal((exports.key as CallableFunction)(0x110104), 42);
    equal((exports.key as CallableFunction)(7), 0);
    equal((exports.shadow as CallableFunction)(7), 42);
    equal((exports.shadow as CallableFunction)(42), 0);
    for (
      const name of [
        "evaluated_record",
        "evaluated",
        "evaluated_capture",
        "evaluated_nested",
        "evaluated_guard",
      ]
    ) {
      equal((exports[name] as WebAssembly.Global).value, 42, name);
    }
    equal((exports.evaluated_miss as WebAssembly.Global).value, 0);
    equal((exports.evaluated_bool as WebAssembly.Global).value, 0);
  } finally {
    js.dispose();
    await native.dispose();
  }
});

Deno.test("value patterns diagnose invalid references, types and incomplete coverage", async () => {
  const js = await createSourceCompiler({ prelude: "none" });
  const native = await createNativeCompiler({ prelude: "none", threads: 1 });
  const cases = [
    [
      "const test = fn x => case x of\n  ^missing => 1\n  _ => 0\n",
      "unknown_value",
    ],
    [
      "const target = fn x => x\nconst test = fn x => case x of\n  ^target => 1\n  _ => 0\n",
      "value_pattern_reference",
    ],
    [
      "const expected = 7\nconst test = fn (x: Bool) => case x of\n  ^expected => 1\n  _ => 0\n",
      "type_mismatch",
    ],
    [
      "const expected = 1.0\nconst test = fn x => case x of\n  ^expected => 1\n  _ => 0\n",
      "value_pattern_type",
    ],
    [
      "const expected = (1, 2)\nconst test = fn x => case x of\n  ^expected => 1\n  _ => 0\n",
      "value_pattern_type",
    ],
    [
      "const expected = #True\nconst test = fn x => case x of\n  ^expected => 1\n",
      "non_exhaustive_match",
    ],
    [
      "const test = fn x => case x of\n  (fresh, ^fresh) => 1\n  _ => 0\n",
      "unknown_value",
    ],
  ];
  try {
    for (const [source, code] of cases) {
      const diagnostic = (error: unknown) => {
        ok(error instanceof SourceError, String(error));
        equal(error.code, code, error.message);
        return true;
      };
      throws(() => js.compile(source), diagnostic);
      await rejects(() => native.compile(source), diagnostic);
    }
  } finally {
    js.dispose();
    await native.dispose();
  }
});

Deno.test("imported and incremental value patterns track changed constants", async () => {
  const js = await createSourceCompiler({ prelude: "none" });
  const native = await createNativeCompiler({ prelude: "none" });
  const session = await createNativeIncrementalCompiler({
    prelude: "none",
    threads: 4,
  });
  try {
    for (const expected of [7, 8, 7]) {
      const project = await loadSourceProject(
        new URL("file:///value-pattern/main.blot"),
        {
          readSource(url) {
            return Promise.resolve(
              url.pathname.endsWith("keys.blot")
                ? `const tab = @u32.add 0 ${expected}\n`
                : `import * as keys from "./keys"
entry const matches = fn code => case code of
  ^keys.tab => 42
  _ => 0
entry const folded = matches 7
entry const answer = fn code => matches code
`,
            );
          },
        },
      );
      const artifact = js.compile(project);
      equal(await native.compile(project), artifact);
      const local = `const tab = ${expected}
entry const matches = fn code => case code of
  ^tab => 42
  _ => 0
entry const folded = matches 7
entry const answer = fn code => matches code
`;
      equal((await session.compile(local)).artifact, js.compile(local));
      const exports = await exportsOf(artifact.bytes);
      equal((exports.answer as CallableFunction)(expected), 42);
      equal((exports.answer as CallableFunction)(expected === 7 ? 8 : 7), 0);
      equal(
        (exports.folded as WebAssembly.Global).value,
        expected === 7 ? 42 : 0,
      );
    }
    for (const reference of ["first", "second", "first"]) {
      const source = `entry const first = 7
entry const second = 8
entry const answer = fn code => case code of
  ^${reference} => 42
  _ => 0
`;
      const artifact = (await session.compile(source)).artifact;
      equal(artifact, js.compile(source));
      const exports = await exportsOf(artifact.bytes);
      equal(
        (exports.answer as CallableFunction)(7),
        reference === "first" ? 42 : 0,
      );
    }
  } finally {
    js.dispose();
    await session.dispose();
    await native.dispose();
  }
});

Deno.test("caret remains available as an infix operator beside value patterns", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    const artifact = compiler.compile(`infixl 60 (^) = add
const add = fn left => fn right => @u32.add left right
entry const expected = 40 ^ 2
entry const answer = fn x => case x of
  ^expected => 42
  _ => 0
`);
    equal(
      ((await exportsOf(artifact.bytes)).answer as CallableFunction)(42),
      42,
    );
  } finally {
    compiler.dispose();
  }
});

Deno.test("tuple value patterns preserve lexical captures across many fields", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  const native = await createNativeCompiler({ prelude: "none", threads: 1 });
  try {
    const width = 128;
    const source =
      `const matcher = fn (expected: U32) => fn candidate => case candidate of
  (${["^expected", ...Array(width - 1).fill("_")].join(", ")}) => 42
  _ => 0
entry const answer = fn () => (matcher 7) (${
        ["7", ...Array(width - 1).fill("0")].join(", ")
      })
`;
    const artifact = compiler.compile(source);
    equal(await native.compile(source), artifact);
    equal(((await exportsOf(artifact.bytes)).answer as CallableFunction)(), 42);
  } finally {
    compiler.dispose();
    await native.dispose();
  }
});
