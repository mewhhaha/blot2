import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;

Deno.test("complete journals bound discarded Arrays inside nested collecting loops", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const compiler = await createZigProjectCompiler({
    executable,
    entry,
    prelude: new URL("../../std/prelude.blot", import.meta.url),
    cacheDirectory: false,
  });
  try {
    const result = await compiler.build({
      sources: {
        [entry]: `
entry const run = fn (count: U32) => do:
  let rows = @array.generate 90 (fn index => #[index, index + 1])
  let checksum = 0
  for row in rows:
    let round = 0
    for ever:
      if round == count:
        break
      let discarded = @array.fill 8192 round
      checksum := self + discarded[8191]
      round := self + 1
    checksum := self + row[0] + row[1]
  return #[checksum, rows[89][0], rows[89][1]]
`,
      },
    });
    assert(result.success, JSON.stringify(result));
    const module = new WebAssembly.Module(result.bytes);
    assert.deepEqual([
      ...new Uint8Array(
        WebAssembly.Module.customSections(module, "blot:ownership")[0],
      ),
    ], [2, 2, 0]);
    const raw = new WebAssembly.Instance(module).exports;
    const memory = raw["blot:memory"] as WebAssembly.Memory;
    const enter = raw["blot:ownership_enter"] as CallableFunction;
    const leave = raw["blot:ownership_leave"] as CallableFunction;
    const reset = raw["blot:reset"] as CallableFunction;
    let warmed = 0;
    let destroyed = Number(
      (raw["blot:rc_destroyed"] as WebAssembly.Global).value,
    );
    for (const count of [8, 8, 40, 200, 8, 200]) {
      enter();
      const pointer = (raw.run as CallableFunction)(count);
      const words = new DataView(memory.buffer);
      assert.equal(words.getUint32(pointer, true), 3);
      assert.equal(
        words.getUint32(pointer + 4, true),
        90 * count * (count - 1) / 2 + 8100,
      );
      assert.equal(words.getUint32(pointer + 8, true), 89);
      assert.equal(words.getUint32(pointer + 12, true), 90);
      const retired = Number(
        (raw["blot:rc_destroyed"] as WebAssembly.Global).value,
      );
      assert(
        retired - destroyed >= 90 * count,
        "discarded Arrays retire before invocation exit",
      );
      destroyed = retired;
      if (warmed !== 0) assert(memory.buffer.byteLength <= warmed + 65536);
      if (count === 8 && warmed === 0) warmed = memory.buffer.byteLength;
      leave(0);
      reset(0);
      assert.equal((raw["blot:rc_roots"] as WebAssembly.Global).value, 0);
      assert.equal((raw["blot:rc_leases"] as WebAssembly.Global).value, 0);
    }
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("unchanged variants preserve erased payload descriptors and aliases", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const compiler = await createZigProjectCompiler({
    executable,
    entry,
    prelude: new URL("../../std/prelude.blot", import.meta.url),
    cacheDirectory: false,
  });
  try {
    const result = await compiler.build({
      sources: {
        [entry]: `
const change = fn candidate => Result.map (fn value => value + 1) candidate
entry const scalar = fn (value: U32) => Result.unwrap_or 42 (change (#Ok value))
entry const alias = fn (value: U32) => do:
  let child = #[value, value + 1]
  let candidate = #Err child
  let mapped = change candidate
  for index in 0..200:
    let pressure = @array.fill 8192 index
    if pressure[0] != index:
      @panic "lost pressure"
  return case mapped of
    #Ok _ => @panic "changed the variant"
    #Err same => #[same[0], child[1]]
const adapter = monad Maybe
const resolve = fn () => do adapter:
  use value <- #Some 42
  return value
entry const resolver = fn () => Maybe.unwrap_or 0 (resolve ())
`,
      },
    });
    assert(result.success, JSON.stringify(result));
    const module = new WebAssembly.Module(result.bytes);
    assert.deepEqual([
      ...new Uint8Array(
        WebAssembly.Module.customSections(module, "blot:ownership")[0],
      ),
    ], [2, 2, 0]);
    const raw = new WebAssembly.Instance(module).exports;
    const memory = raw["blot:memory"] as WebAssembly.Memory;
    for (const value of [0, 8192, 0xffff_fffe]) {
      (raw["blot:ownership_enter"] as CallableFunction)();
      assert.equal(
        Number((raw.scalar as CallableFunction)(value)) >>> 0,
        (value + 1) >>> 0,
      );
      assert.equal((raw.resolver as CallableFunction)(0), 42);
      const pointer = (raw.alias as CallableFunction)(value);
      const words = new DataView(memory.buffer);
      assert.equal(words.getUint32(pointer, true), 2);
      assert.equal(words.getUint32(pointer + 4, true), value);
      assert.equal(words.getUint32(pointer + 8, true), (value + 1) >>> 0);
      (raw["blot:ownership_leave"] as CallableFunction)(0);
      (raw["blot:reset"] as CallableFunction)(0);
      assert.equal((raw["blot:rc_roots"] as WebAssembly.Global).value, 0);
      assert.equal((raw["blot:rc_leases"] as WebAssembly.Global).value, 0);
    }
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("borrowed reference returns preserve field aliases when their parent replaces the owning edge", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const compiler = await createZigProjectCompiler({
    executable,
    entry,
    prelude: new URL("../../std/prelude.blot", import.meta.url),
    cacheDirectory: false,
  });
  try {
    const result = await compiler.build({
      sources: {
        [entry]: `
const identity = fn value => value
entry const run = fn (count: U32) => do:
  let fresh = #[7, 42]
  let direct = identity fresh
  let rows = @array.generate 2 (fn index => #[index, index + 1])
  let field = identity rows[0]
  rows := @array.set rows 0 #[90, 91]
  for index in 0..count:
    let pressure = @array.fill 8192 index
    if pressure[8191] != index:
      @panic "lost pressure"
  return #[direct[1], field[0], field[1], rows[0][0], fresh[0]]
`,
      },
    });
    assert(result.success, JSON.stringify(result));
    const module = new WebAssembly.Module(result.bytes);
    assert.deepEqual([
      ...new Uint8Array(
        WebAssembly.Module.customSections(module, "blot:ownership")[0],
      ),
    ], [2, 2, 0]);
    const raw = new WebAssembly.Instance(module).exports;
    const memory = raw["blot:memory"] as WebAssembly.Memory;
    const enter = raw["blot:ownership_enter"] as CallableFunction;
    const leave = raw["blot:ownership_leave"] as CallableFunction;
    const reset = raw["blot:reset"] as CallableFunction;
    let warmed = 0;
    for (const count of [8, 200, 8, 200]) {
      enter();
      const pointer = (raw.run as CallableFunction)(count);
      const words = new DataView(memory.buffer);
      assert.equal(words.getUint32(pointer, true), 5);
      const values = Array.from(
        { length: 5 },
        (_, index) => words.getUint32(pointer + 4 + index * 4, true),
      );
      assert.deepEqual(values, [42, 0, 1, 90, 7]);
      if (warmed !== 0) assert(memory.buffer.byteLength <= warmed + 65536);
      if (warmed === 0) warmed = memory.buffer.byteLength;
      leave(0);
      reset(0);
      assert.equal((raw["blot:rc_roots"] as WebAssembly.Global).value, 0);
      assert.equal((raw["blot:rc_leases"] as WebAssembly.Global).value, 0);
    }
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
