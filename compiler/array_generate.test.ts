import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import { createNativeCompiler } from "./native.ts";
import { createNativeIncrementalCompiler } from "./native_incremental.ts";
import { createSourceCompiler } from "./source.ts";
import { SourceError } from "./syntax.ts";

const source = `
const indexed = fn index => do:
  return index + 40
const named = fn () => @array.get (@array.generate 3 indexed) 2
const offset = 40
const generated = @array.generate 3 (fn index => index + offset)
const functions = @array.generate 3 (fn index => fn value => index + value)
const constant = @array.get generated 2
const callback = (@array.get functions 2) 40
const skipped = @array.length (@array.generate 0 (fn index => @panic "unused"))
const empty = fn () => @array.length (@array.generate 0 (fn index => @panic "unused"))
const at = fn (index: U32) => @array.get (@array.generate 32768 (fn lane => lane + 7)) index
const count = fn (size: U32) => @array.length (@array.generate size (fn lane => lane))
const high = fn () => @array.get (@array.generate 2 (fn index => 4294967295 - index)) 0
const float = fn () => @array.get (@array.generate 2 (fn index => 1.25)) 1
const closure = fn () => do:
  let delta = 40
  let callbacks = @array.generate 3 (fn index => fn value => delta + index + value)
  return (@array.get callbacks 2) 0
const unchanged = fn () => do:
  let original = @array.fill 2 20
  let copies = @array.generate 2 (fn index => original)
  let changed = @array.set (@array.get copies 0) 1 22
  return @array.get (@array.get copies 1) 1 + @array.get changed 1
`;

async function exercise(bytes: Uint8Array<ArrayBuffer>) {
  const { instance } = await WebAssembly.instantiate(bytes);
  const call = (name: string, index = 0) =>
    (instance.exports[name] as CallableFunction)(index);
  equal((instance.exports.constant as WebAssembly.Global).value, 42);
  equal((instance.exports.callback as WebAssembly.Global).value, 42);
  equal((instance.exports.skipped as WebAssembly.Global).value, 0);
  equal(call("empty"), 0);
  equal(call("at", 32767), 32774);
  equal(call("at", 0), 7);
  equal(call("high") >>> 0, 0xffffffff);
  equal(call("float"), 1.25);
  equal(call("closure"), 42);
  equal(call("named"), 42);
  equal(call("unchanged"), 42);
  for (const count of [4194304, 0x80000000, 0xffffffff]) {
    throws(() => call("count", count), WebAssembly.RuntimeError);
    equal(call("count", 3), 3);
  }
}

Deno.test("array generate JS builds large arrays once and preserves generic immutable values", async () => {
  const compiler = await createSourceCompiler();
  try {
    await exercise(compiler.compile(source).bytes);
  } finally {
    compiler.dispose();
  }
});

Deno.test("array generate native compilation and incremental callback edits match JS", async () => {
  const compiler = await createSourceCompiler();
  const native = await createNativeCompiler();
  const incremental = await createNativeIncrementalCompiler();
  try {
    for (
      const revision of [
        source,
        source.replace("fn lane => lane)", "fn lane => lane + 1)"),
        source.replace(
          "@array.generate 3 (fn index => index + offset)",
          "@array.generate 4 (fn index => index + offset)",
        ),
        source,
      ]
    ) {
      const artifact = await native.compile(revision);
      equal(artifact, compiler.compile(revision));
      const cached = await incremental.compile(revision);
      equal(cached.artifact.bytes, artifact.bytes);
      await exercise(artifact.bytes);
      await exercise(cached.artifact.bytes);
    }
  } finally {
    compiler.dispose();
    await native.dispose();
    await incremental.dispose();
  }
});

Deno.test("array generate rejects invalid counts, callbacks, effects, limits and exhausted budgets", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    for (
      const [source, code] of [
        [
          "const invalid = @array.generate True (fn index => index)",
          "type_mismatch",
        ],
        ["const invalid = @array.generate 2 3", "type_mismatch"],
        [
          "const invalid = @array.generate 2 (fn (index: Bool) => index)",
          "type_mismatch",
        ],
        ["const invalid = @array.generate 2", "call_arity"],
        [
          "const invalid = @array.generate 2 (fn index => index) 0",
          "call_arity",
        ],
        [
          'const invalid = @array.generate 4294967295 (fn index => @panic "unvisited")',
          "backend_limit",
        ],
        [
          "const invalid = @array.generate 4194304 (fn index => index)",
          "backend_limit",
        ],
        [
          'const invalid = @array.generate 0 (@panic "eager callback")',
          "const_panic",
        ],
        [
          'const invalid = @array.generate (@panic "count first") (@panic "callback second")',
          "const_panic",
        ],
      ]
    ) {
      throws(() => compiler.compile(`${source}\n`), (error) => {
        ok(error instanceof SourceError, String(error));
        equal(error.code, code, error.message);
        if (source.includes("count first")) {
          ok(error.message.includes("count first"));
        }
        return true;
      });
    }
    throws(() =>
      compiler.compile(`effect Read : U32 -> U32
const invalid = fn () => @array.generate 2 (fn index => Read index)
`), (error) => {
      ok(error instanceof SourceError, String(error));
      equal(error.code, "effect_mismatch", error.message);
      return true;
    });
    const source = "const generated = @array.generate 3 (fn index => index)\n";
    const ample = compiler.analyze(source, { const_steps: 100n });
    const required = 100n - ample.remaining_steps;
    equal(
      compiler.analyze(source, { const_steps: required }).remaining_steps,
      0n,
    );
    throws(
      () => compiler.analyze(source, { const_steps: required - 1n }),
      (error) => {
        ok(error instanceof SourceError);
        equal(error.code, "const_budget");
        return true;
      },
    );
  } finally {
    compiler.dispose();
  }
});
