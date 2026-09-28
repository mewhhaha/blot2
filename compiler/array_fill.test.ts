import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import { createNativeCompiler } from "./native.ts";
import { createNativeIncrementalCompiler } from "./native_incremental.ts";
import { createSourceCompiler } from "./source.ts";
import { SourceError } from "./syntax.ts";

// Const evaluation only runs for declarations an entry reaches.
const probe = (name: string) =>
  `entry const probe = fn () => do:\n  let kept = ${name}\n  return 0\n`;

const source = `
entry const seed = 20
const filled = @array.fill 3 seed
const callbacks = @array.fill 2 (fn value => value + 2)
entry const count = @array.length filled
entry const constant = (@array.get callbacks 1) 40
entry const empty = fn () => @array.length (@array.fill 0 True)
entry const high = fn (count: U32) => @array.get (@array.fill count 4294967295) 0
entry const size = fn (count: U32) => @array.length (@array.fill count 7)
entry const closures = fn () => do:
  let offset = 2
  let functions = @array.fill 2 (fn value => value + offset)
  return (@array.get functions 1) 40
entry const unchanged = fn () => do:
  let original = @array.fill 2 (@array.fill 2 seed)
  let changed = @array.set (@array.get original 0) 1 22
  return @array.get (@array.get original 1) 1 + @array.get changed 1
entry const float = fn () => @array.get (@array.fill 2 1.25) 1
entry const packet = fn (count: U32) => @array.fill count 0x12345678
entry const float_packet = fn (count: U32) => @array.fill count 1.25
entry const many_closures = fn (count: U32) => do:
  let offset = 2
  let functions = @array.fill count (fn value => value + offset)
  return (@array.get functions (@u32.sub count 1)) 40
entry const many_shared = fn (count: U32) => do:
  let arrays = @array.fill count (@array.fill 2 20)
  let changed = @array.set (@array.get arrays 0) 1 22
  return @array.get (@array.get arrays (@u32.sub count 1)) 1 + @array.get changed 1
`;

async function exercise(bytes: Uint8Array<ArrayBuffer>) {
  const { instance } = await WebAssembly.instantiate(bytes);
  const call = (name: string, count = 0) =>
    (instance.exports[name] as CallableFunction)(count);
  equal((instance.exports.count as WebAssembly.Global).value, 3);
  equal((instance.exports.constant as WebAssembly.Global).value, 42);
  equal(call("empty"), 0);
  equal(call("high", 3) >>> 0, 0xffffffff);
  equal(call("float"), 1.25);
  for (
    const name of ["closures", "unchanged"]
  ) {
    equal(call(name), 42);
  }
  const memory = instance.exports["blot:memory"] as WebAssembly.Memory;
  for (
    const count of [
      0,
      1,
      2,
      31,
      32,
      33,
      63,
      64,
      65,
      127,
      128,
      129,
      8191,
      8192,
      8193,
    ]
  ) {
    const pointer = call("packet", count) >>> 0;
    const words = new Uint32Array(memory.buffer, pointer, count + 1);
    equal(words[0], count);
    equal(words.subarray(1), new Uint32Array(count).fill(0x12345678));
    const floats = call("float_packet", count) >>> 0;
    equal(
      new Float32Array(memory.buffer, floats + 4, count),
      new Float32Array(count).fill(1.25),
    );
    if (count > 0) {
      equal(call("many_closures", count), 42);
      equal(call("many_shared", count), 42);
    }
  }
  equal(call("size", 8192), 8192);
  equal(call("size", 4_194_304), 4_194_304);
  for (const count of [1_073_741_822, 1_073_741_823, 0x80000000, 0xffffffff]) {
    throws(() => call("size", count), WebAssembly.RuntimeError);
    equal(call("size", 2), 2);
  }
}

Deno.test("array fill executes generic immutable values and closures through JS", async () => {
  const compiler = await createSourceCompiler();
  try {
    await exercise(compiler.compile(source).bytes);
  } finally {
    compiler.dispose();
  }
});

Deno.test("array fill native compilation and cached revisions agree with JS", async () => {
  const compiler = await createSourceCompiler();
  const native = await createNativeCompiler();
  const incremental = await createNativeIncrementalCompiler();
  try {
    for (
      const revision of [
        source,
        source.replace("@array.fill 3 seed", "@array.fill 3 21"),
        source.replace("@array.fill count 7", "@array.fill count 8"),
        source,
      ]
    ) {
      const artifact = await native.compile(revision);
      equal(artifact, compiler.compile(revision));
      await exercise(artifact.bytes);
      const cached = await incremental.compile(revision);
      equal(cached.artifact.bytes, artifact.bytes);
      await exercise(cached.artifact.bytes);
    }
  } finally {
    compiler.dispose();
    await native.dispose();
    await incremental.dispose();
  }
});

Deno.test("array fill validates counts, arity, limits and const budgets", async () => {
  const compiler = await createSourceCompiler();
  try {
    for (
      const [text, code] of [
        ["const invalid = @array.fill True 0", "type_mismatch"],
        ["const invalid = @array.fill 2", "call_arity"],
        ["const invalid = @array.fill 2 0 0", "call_arity"],
        ["const invalid = @array.fill 4294967295 0", "backend_limit"],
        ["const invalid = @array.fill 4194304 0", "backend_limit"],
        ["const invalid = @array.get (@array.fill 0 1) 0", "array_bounds"],
        [
          'const invalid = @array.fill (@panic "count first") (@panic "value second")',
          "const_panic",
        ],
        ['const invalid = @array.fill 0 (@panic "eager value")', "const_panic"],
      ]
    ) {
      throws(
        () => compiler.compile(`${text}\n${probe("invalid")}`),
        (error) => {
          ok(error instanceof SourceError, String(error));
          equal(error.code, code, error.message);
          if (text.includes("count first")) {
            ok(error.message.includes("count first"));
          }
          return true;
        },
      );
    }
    const fill = "const filled = @array.fill 3 42\n" + probe("filled");
    const result = compiler.analyze(fill, { const_steps: 9n });
    equal(result.remaining_steps, 0n);
    throws(() => compiler.analyze(fill, { const_steps: 8n }), (error) => {
      ok(error instanceof SourceError);
      equal(error.code, "const_budget");
      return true;
    });
  } finally {
    compiler.dispose();
  }
});
