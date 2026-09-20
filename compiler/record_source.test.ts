import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import { instantiateGuest } from "./guest.ts";
import { createNativeCompiler } from "./native.ts";
import { createNativeIncrementalCompiler } from "./native_incremental.ts";
import { createIncrementalCompiler } from "./incremental.ts";
import { createSourceCompiler } from "./source.ts";
import { loadSourceProject } from "./source_project.ts";
import { SourceError } from "./syntax.ts";

Deno.test("source records compose with generic data, arrays, const evaluation, and native Wasm", async () => {
  const source = await Deno.readTextFile(
    new URL("../examples/records.blot", import.meta.url),
  );
  const js = await createSourceCompiler();
  const native = await createNativeCompiler();
  try {
    const expected = js.compile(source);
    const actual = await native.compile(source);
    equal(actual, expected);
    const { instance } = await WebAssembly.instantiate(actual.bytes);
    equal((instance.exports.expected as WebAssembly.Global).value, 42);
    equal((instance.exports.answer as CallableFunction)(), 42);
  } finally {
    js.dispose();
    await native.dispose();
  }
});

Deno.test("record fields evaluate once in source order, independent of declaration order", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    const artifact = compiler.compile(
      `data Pair = Pair { first: U32, second: U32 }
export fn answer (io: U32 -> U32 ! {Foreign}) => do:
  use pair <- Pair { second: io 1, first: io 2 }
  let Pair { first, second } = pair
  return @u32.add (@u32.mul first 10) second
`,
    );
    const guest = await instantiateGuest(artifact.bytes);
    try {
      const calls: number[] = [];
      const capability = guest.capability({
        parameter: "U32",
        result: "U32",
        call(value) {
          calls.push(value as number);
          return value;
        },
      });
      equal(guest.call("answer", capability), 21);
      equal(calls, [1, 2]);
    } finally {
      guest.dispose();
    }
  } finally {
    compiler.dispose();
  }
});

Deno.test("record shorthand retains lexical scope and function-valued fields", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(
      `data Action a = Action { run: U32 -> a, enabled: Bool }
fn apply action => case action of
  Action { run, enabled: True } => run 40
  Action { enabled: False } => 0
export fn answer () => do:
  let increment = 2
  let run = fn value => value + increment
  let enabled = True
  return apply (Action { enabled, run })
`,
    );
    const { instance } = await WebAssembly.instantiate(artifact.bytes);
    equal((instance.exports.answer as CallableFunction)(), 42);
  } finally {
    compiler.dispose();
  }
});

Deno.test("record construction diagnoses missing, unknown, duplicate, and invalid fields", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    for (
      const [source, code] of [
        ["data Pair = Pair { x: U32, x: U32 }\n", "duplicate_record_field"],
        [
          "data Pair = Pair { x: U32, y: U32 }\nfn make () => Pair { x: 1 }\n",
          "missing_record_field",
        ],
        [
          "data Pair = Pair { x: U32, y: U32 }\nfn make () => Pair { x: 1, y: 2, z: 3 }\n",
          "unknown_record_field",
        ],
        [
          "data Pair = Pair { x: U32, y: U32 }\nfn make () => Pair { x: 1, y: 2, x: 3 }\n",
          "duplicate_record_field",
        ],
        [
          "data Box = Box U32\nfn make () => Box { x: 1 }\n",
          "record_constructor",
        ],
        ["fn make value => value { x: 1 }\n", "record_constructor"],
        ["fn make () => Missing {}\n", "unknown_constructor"],
        [
          "data Box = Box { value: Bool }\nfn make () => Box { value: 42 }\n",
          "type_mismatch",
        ],
      ]
    ) {
      throws(() => compiler.compile(source), (error) => {
        ok(error instanceof SourceError, String(error));
        equal(error.code, code, error.message);
        return true;
      });
    }
  } finally {
    compiler.dispose();
  }
});

Deno.test("record field metadata follows namespace and named constructor imports", async () => {
  const sources: Record<string, string> = {
    "/records/geometry.blot": "export data Point a = Point { x: a, y: U32 }\n",
    "/records/main.blot": `import * as geometry from "./geometry"
import { Point as Position } from "./geometry"
fn sum point => case point of
  Position { y, x } => @u32.add x y
export fn answer () => sum (geometry.Point { y: 2, x: 40 })
`,
  };
  const project = await loadSourceProject(
    new URL("file:///records/main.blot"),
    {
      readSource: (url) => Promise.resolve(sources[url.pathname]),
    },
  );
  const compiler = await createSourceCompiler({ prelude: "none" });
  const native = await createNativeCompiler({ prelude: "none" });
  try {
    const artifact = compiler.compile(project);
    equal(await native.compile(project), artifact);
    const { instance } = await WebAssembly.instantiate(artifact.bytes);
    equal((instance.exports.answer as CallableFunction)(), 42);
  } finally {
    compiler.dispose();
    await native.dispose();
  }
});

Deno.test("record field reordering invalidates source lowering in native and JS sessions", async () => {
  const js = await createIncrementalCompiler({ prelude: "none" });
  const native = await createNativeIncrementalCompiler({ prelude: "none" });
  const clean = await createSourceCompiler({ prelude: "none" });
  const source = `data Pair = Pair { x: U32, y: U32 }
fn make () => Pair { x: 40, y: 2 }
export fn answer () => case make () of
  Pair payload => @product.get payload 0
`;
  try {
    for (const session of [js, native]) {
      for (
        const [text, expected] of [
          [source, 40],
          [source.replace("{ x: U32, y: U32 }", "{ y: U32, x: U32 }"), 2],
          [source, 40],
        ] as const
      ) {
        const actual = await session.compile(text);
        equal(actual.artifact.bytes, clean.compile(text).bytes);
        const { instance } = await WebAssembly.instantiate(
          actual.artifact.bytes,
        );
        equal((instance.exports.answer as CallableFunction)(), expected);
      }
    }
  } finally {
    await js.dispose();
    await native.dispose();
    clean.dispose();
  }
});
