import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../compiler/guest.ts";
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
  break #[checksum, rows[89][0], rows[89][1]]
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
  break case mapped of
    #Ok _ => @panic "changed the variant"
    #Err same => #[same[0], child[1]]
const adapter = monad Maybe
const resolve = fn () => do adapter:
  use value <- #Some 42
  break value
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
  break #[direct[1], field[0], field[1], rows[0][0], fresh[0]]
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

Deno.test("checked field updates preserve variant layouts aliases captures and retained edits in both tiers", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  try {
    for (const codegenTier of ["optimized", "development"] as const) {
      const options = {
        executable,
        entry,
        codegenTier,
        prelude: new URL("../../std/prelude.blot", import.meta.url),
        cacheDirectory: false as const,
      };
      const retained = await createZigProjectCompiler(options);
      try {
        for (const offset of [0, 10, 0]) {
          const sources = {
            [entry]: `
type Shape is data = #Small {child: Array U32, value: U32} | #Large {alpha: F32, child: Array U32, value: U32, tail: U32}
const replace = fn (shape: Shape) => do:
  shape.child := #[self[0] + 1 + ${offset}]
  shape.value := self + 2
  break shape
entry const run = fn (mode: U32) => do:
  let original = if mode == 0 then #Small {child: #[40], value: 7} else #Large {alpha: -0.0, child: #[40], value: 7, tail: 3}
  let captured = fn () => original.child[0]
  let changed = replace original
  for index in 0..32:
    let pressure = @array.fill 8192 index
    if pressure[8191] != index:
      break #[0]
  break #[original.child[0], changed.child[0], captured (), original.value, changed.value]
entry const packed = fn (value: U32) => do:
  let rows = [{x: value, y: value + 1}]
  let original = rows
  rows := [{x: value + 40, y: value + 1}, ...self]
  let items = @array.from_list rows
  let before = items
  items[0] := {x: self.x + 1, y: self.y + 2}
  break #[(@array.from_list original)[0].x, (@array.from_list rows)[0].x, before[0].x, items[0].x, items[0].y]
entry const floating = fn (value: F32) => do:
  let original = #Large {alpha: value, child: #[40], value: 7, tail: 3}
  let changed = replace original
  let #Large {alpha, child: _, value: _, tail: _} = changed else:
    break 0.0
  break alpha
`,
          };
          const result = await retained.build({ sources });
          const fresh = await createZigProjectCompiler(options);
          try {
            const expected = await fresh.build({ sources });
            assert(result.success && expected.success, JSON.stringify(result));
            assert.deepEqual(result.bytes, expected.bytes);
            const module = new WebAssembly.Module(result.bytes);
            assert.deepEqual([
              ...new Uint8Array(
                WebAssembly.Module.customSections(module, "blot:ownership")[0],
              ),
            ], [2, 2, 0]);
            const guest = await instantiateGuest(result.bytes);
            try {
              for (const mode of [0, 1, 0, 1]) {
                assert.deepEqual(
                  Array.from(guest.call("run", mode) as Uint32Array),
                  [40, 41 + offset, 40, 7, 9],
                );
              }
              assert.deepEqual(
                Array.from(guest.call("packed", 1) as Uint32Array),
                [1, 41, 41, 42, 4],
              );
              for (const value of [-0, 0, 1.25, -1.5]) {
                assert(Object.is(guest.call("floating", value), value));
              }
            } finally {
              guest.dispose();
            }
          } finally {
            await fresh.dispose();
          }
        }
      } finally {
        await retained.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("complete allocation leaves legacy trace metadata untouched with ordinary and shared machine bodies", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  try {
    for (const shareMachineCode of [false, true]) {
      const compiler = await createZigProjectCompiler({
        executable,
        entry,
        shareMachineCode,
        prelude: new URL("../../std/prelude.blot", import.meta.url),
        cacheDirectory: false,
      });
      try {
        const result = await compiler.build({
          sources: {
            [entry]: `
entry const run = fn (count: U32) => do:
  let kept = #[7, 11]
  let total = 0
  for index in 0..count:
    let pressure = @array.fill 8192 index
    total := self + pressure[8191]
  break total + kept[0] + kept[1]
entry const memory = fn (value: U32) => #[value]
`,
          },
        });
        assert(result.success, JSON.stringify(result));
        const module = new WebAssembly.Module(result.bytes);
        const mode = new Uint8Array(
          WebAssembly.Module.customSections(module, "blot:ownership")[0],
        );
        if (!shareMachineCode) {
          assert.deepEqual([...mode], [2, 2, 0]);
          const raw = new WebAssembly.Instance(module).exports;
          const memory = raw["blot:memory"] as WebAssembly.Memory;
          new DataView(memory.buffer).setUint32(4, 0xdeadbeef, true);
          new DataView(memory.buffer).setUint32(12, 0xcafebabe, true);
          for (let round = 0; round < 10; round++) {
            (raw["blot:ownership_enter"] as CallableFunction)();
            assert.equal((raw.run as CallableFunction)(32), 514);
            (raw["blot:ownership_leave"] as CallableFunction)(0);
            (raw["blot:reset"] as CallableFunction)(0);
            assert.equal(
              new DataView(memory.buffer).getUint32(4, true),
              0xdeadbeef,
            );
            assert.equal(
              new DataView(memory.buffer).getUint32(12, true),
              0xcafebabe,
            );
          }
        } else {
          assert.deepEqual([...mode], [2, 2, 0]);
          const guest = await instantiateGuest(result.bytes);
          try {
            for (let round = 0; round < 10; round++) {
              assert.equal(guest.call("run", 32), 514);
            }
          } finally {
            guest.dispose();
          }
        }
      } finally {
        await compiler.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("List literal publication counts actual leaves and preserves shared children across leaf boundaries", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const elements = Array.from({ length: 260 }, () => "child").join(", ");
  try {
    for (const codegenTier of ["optimized", "development"] as const) {
      const compiler = await createZigProjectCompiler({
        executable,
        entry,
        codegenTier,
        prelude: new URL("../../std/prelude.blot", import.meta.url),
        cacheDirectory: false,
      });
      try {
        const result = await compiler.build({
          sources: {
            [entry]: `
entry const run = fn (value: U32) => do:
  let child = #[value, value + 1]
  let rows = [${elements}]
  let before = @array.from_list rows
  let changed = @array.from_list rows
  let read = fn () => before[259][1]
  changed[243] := #[self[0] + 40, self[1] + 40]
  changed[244] := #[self[0] + 41, self[1] + 41]
  for index in 0..32:
    let pressure = @array.fill 8192 index
    if pressure[8191] != index:
      break #[0]
  break #[before[243][0], changed[243][0], before[244][0], changed[244][0], read (), child[0]]
entry const floating = fn (value: F32) => @array.from_list [value, -0.0]
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
        const guest = await instantiateGuest(result.bytes);
        try {
          const floats = guest.call("floating", -0) as Float32Array;
          assert(Object.is(floats[0], -0) && Object.is(floats[1], -0));
          const wanted = [7, 47, 7, 48, 8, 7];
          assert.deepEqual(
            Array.from(guest.call("run", 7) as Uint32Array),
            wanted,
          );
          const warmed = guest.memoryBytes();
          for (let round = 0; round < 20; round++) {
            assert.deepEqual(
              Array.from(guest.call("run", 7) as Uint32Array),
              wanted,
            );
          }
          assert(guest.memoryBytes() <= warmed + 65536);
        } finally {
          guest.dispose();
        }
      } finally {
        await compiler.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
