import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;

Deno.test("counted List rotations preserve borrowed pivots after original owners retire", async () => {
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
entry const forward = func (count: U32) => return do:
  let values: List U32 = []
  for index in 0..count:
    values := [...self, index]
  break Array.from_list values
entry const backward = func (count: U32) => return do:
  let values: List U32 = []
  for index in 0..count:
    values := [index, ...self]
  break Array.from_list values
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
    for (const count of [0, 244, 1000, 4097]) {
      for (const name of ["forward", "backward"]) {
        enter();
        const pointer = (raw[name] as CallableFunction)(count);
        const words = new DataView(memory.buffer);
        assert.equal(words.getUint32(pointer, true), count);
        for (let index = 0; index < count; index++) {
          let expected = index;
          if (name === "backward") expected = count - index - 1;
          assert.equal(
            words.getUint32(pointer + 4 + index * 4, true),
            expected,
          );
        }
        leave(0);
        reset(0);
        assert.equal((raw["blot:rc_roots"] as WebAssembly.Global).value, 0);
        assert.equal((raw["blot:rc_leases"] as WebAssembly.Global).value, 0);
      }
    }
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});

const source = `
const make = func (value: U32) => return #[value, value + 1]
const choose = func (values: Array (Array U32)) => return values[0]
entry const run = func (value: U32) => return do:
  let child = make value
  let parent = #[child, child]
  let alias = choose parent
  break alias[0] + parent[1][1]
entry const trapped = func (value: U32) => return do:
  let values = make value
  break values[value]
`;
Deno.test("source returned and borrowed Arrays own typed invocation roots across calls and failure", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  try {
    for (const tier of ["development", "optimized"] as const) {
      const compiler = await createZigProjectCompiler({
        executable,
        entry,
        prelude: new URL("../../std/prelude.blot", import.meta.url),
        cacheDirectory: false,
        codegenTier: tier,
      });
      try {
        const result = await compiler.build({ sources: { [entry]: source } });
        assert(result.success, JSON.stringify(result));
        const module = new WebAssembly.Module(result.bytes);
        assert.deepEqual([
          ...new Uint8Array(
            WebAssembly.Module.customSections(module, "blot:ownership")[0],
          ),
        ], [2, 2, 0]);
        const raw = new WebAssembly.Instance(module).exports;
        const roots = () =>
          Number((raw["blot:rc_roots"] as WebAssembly.Global).value);
        const leases = () =>
          Number((raw["blot:rc_leases"] as WebAssembly.Global).value);
        const run = raw.run as CallableFunction;
        const trapped = raw.trapped as CallableFunction;
        assert.throws(() => trapped(41), WebAssembly.RuntimeError);
        assert(roots() > 0);
        for (const value of [41, 7, 41]) {
          assert.equal(run(value), 2 * value + 1);
          assert.equal(roots(), 0);
          assert.equal(leases(), 0);
        }
        const guest = await instantiateGuest(module);
        try {
          assert.equal(guest.abi.version, 3);
          assert.throws(
            () => guest.call("trapped", 41),
            WebAssembly.RuntimeError,
          );
          for (const value of [41, 7, 41]) {
            assert.equal(guest.call("run", value), 2 * value + 1);
          }
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

Deno.test("source loop carries preserve old aliases and retire discarded iteration graphs", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const source = `
const make = func (value: U32) => return #[value, value + 1]
const first = func (end: U32) => return func (value: U32) => return do:
  for index in 0..end:
    let values = make (value + index)
    if index == 3:
      break values
  break make value
entry const run = func (end: U32) => return do:
  let values = make 41
  let before = values
  let previous = make 99
  for index in 0..end:
    let old = values
    values := make (old[0] + 1)
    previous := old
    if index == 6:
      break
  break before[0] + values[0] + previous[0] + (first end 100)[0]
entry const trapped = func (end: U32) => return do:
  let values = make 41
  for index in 0..end:
    values := make (self[0] + 1)
  break values[10]
`;
  try {
    for (const tier of ["development", "optimized"] as const) {
      const compiler = await createZigProjectCompiler({
        executable,
        entry,
        prelude: new URL("../../std/prelude.blot", import.meta.url),
        cacheDirectory: false,
        codegenTier: tier,
      });
      try {
        const result = await compiler.build({ sources: { [entry]: source } });
        assert(result.success, JSON.stringify(result));
        const module = new WebAssembly.Module(result.bytes);
        assert.deepEqual([
          ...new Uint8Array(
            WebAssembly.Module.customSections(module, "blot:ownership")[0],
          ),
        ], [2, 2, 0]);
        const raw = new WebAssembly.Instance(module).exports;
        const count = (name: string) =>
          Number((raw[`blot:rc_${name}`] as WebAssembly.Global).value);
        for (const end of [0, 1, 3, 4, 7, 5000]) {
          const iterations = Math.min(end, 7);
          const previous = iterations === 0 ? 99 : 40 + iterations;
          const first = end > 3 ? 103 : 100;
          assert.equal(
            (raw.run as CallableFunction)(end),
            41 + 41 + iterations + previous + first,
          );
          assert.equal(count("roots"), 0);
          assert.equal(count("leases"), 0);
        }
        assert.throws(
          () => (raw.trapped as CallableFunction)(5000),
          WebAssembly.RuntimeError,
        );
        assert(count("roots") < 16, `discarded roots ${count("roots")}`);
        assert(count("leases") < 16, `discarded leases ${count("leases")}`);
        assert(count("destroyed") > 4900);
        const guest = await instantiateGuest(module);
        try {
          assert.throws(
            () => guest.call("trapped", 5000),
            WebAssembly.RuntimeError,
          );
          assert.equal(guest.call("run", 4), 233);
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

Deno.test("startup reference globals retain captures and ready demand results until teardown", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const source = `
const delay = func ~value => return value
let values = @array.fill 3 40
let saved = (func (capture: Array U32) => return func (index: U32) => return capture[index]) values
let pending = delay (@array.fill 3 (saved 0))
let alias = pending
entry const run = func (value: U32) => return do:
  let before = @force pending
  let after = @force alias
  let changed = @array.set values 0 value
  break saved 2 + before[1] + after[2] + changed[0]
entry const pressure = func (count: U32) => return do:
  let values = @array.fill count 99
  break values[count - 1]
`;
  try {
    for (const tier of ["development", "optimized"] as const) {
      const compiler = await createZigProjectCompiler({
        executable,
        entry,
        prelude: new URL("../../std/prelude.blot", import.meta.url),
        cacheDirectory: false,
        codegenTier: tier,
      });
      try {
        const result = await compiler.build({ sources: { [entry]: source } });
        assert(result.success, JSON.stringify(result));
        const module = new WebAssembly.Module(result.bytes);
        assert.deepEqual([
          ...new Uint8Array(
            WebAssembly.Module.customSections(module, "blot:ownership")[0],
          ),
        ], [2, 2, 0]);
        const raw = new WebAssembly.Instance(module).exports;
        const count = (name: string) =>
          Number((raw[`blot:rc_${name}`] as WebAssembly.Global).value);
        const persistent = count("roots");
        assert(persistent > 0);
        for (const value of [1, 20, 1]) {
          assert.equal((raw.run as CallableFunction)(value), 120 + value);
          assert.equal((raw.pressure as CallableFunction)(32768), 99);
          assert.equal(count("roots"), persistent);
          (raw["blot:ownership_enter"] as CallableFunction)();
          (raw["blot:ownership_leave"] as CallableFunction)(0);
        }
        const retired = count("destroyed");
        (raw["blot:ownership_leave"] as CallableFunction)(2);
        assert.equal(count("roots"), 0);
        assert.equal(count("leases"), 0);
        assert(count("destroyed") > retired);
        const guest = await instantiateGuest(module);
        try {
          for (const value of [1, 20, 1]) {
            assert.equal(guest.call("run", value), 120 + value);
          }
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

Deno.test("source State preserves the old graph held by a strong ready demand memo", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const source = `
data Cell value = #Cell value
const delay = func ~value => return value
entry const run = func (value: U32) => return do:
  let (_, result) = @state.run (#Cell #[value]) (func () => return do:
    let pending = delay (do:
      use cell <- @state.get (func () => return #Cell #[0])
      let #Cell values = cell
      break values)
    use before <- @force pending
    use @state.set (#Cell #[value + 100])
    use after <- @force pending
    break before[0] + after[0])
  break result
`;
  try {
    for (const tier of ["development", "optimized"] as const) {
      const compiler = await createZigProjectCompiler({
        executable,
        entry,
        prelude: new URL("../../std/prelude.blot", import.meta.url),
        cacheDirectory: false,
        codegenTier: tier,
      });
      try {
        const result = await compiler.build({ sources: { [entry]: source } });
        assert(result.success, JSON.stringify(result));
        const module = new WebAssembly.Module(result.bytes);
        assert.deepEqual([
          ...new Uint8Array(
            WebAssembly.Module.customSections(module, "blot:ownership")[0],
          ),
        ], [2, 2, 0]);
        const raw = new WebAssembly.Instance(module).exports;
        for (const value of [41, 7, 41]) {
          assert.equal((raw.run as CallableFunction)(value), value * 2);
          assert.equal((raw["blot:rc_roots"] as WebAssembly.Global).value, 0);
          assert.equal((raw["blot:rc_leases"] as WebAssembly.Global).value, 0);
        }
        const guest = await instantiateGuest(module);
        try {
          assert.equal(guest.call("run", 41), 82);
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

Deno.test("public scalar Arrays own marshalled inputs and copy results before invocation leave", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const source = `
entry const make = func (count: U32) => return @array.generate count (func index => return index + 41)
entry const copy = func (values: Array U32) => return @array.set values 0 99
entry const first = func (values: Array U32) => return values[0]
entry const floats = func (values: Array F32) => return @array.set values 0 2.5
entry const trapped = func (values: Array U32) => return values[values[0]]
`;
  try {
    for (const tier of ["development", "optimized"] as const) {
      const compiler = await createZigProjectCompiler({
        executable,
        entry,
        prelude: new URL("../../std/prelude.blot", import.meta.url),
        cacheDirectory: false,
        codegenTier: tier,
      });
      try {
        const result = await compiler.build({ sources: { [entry]: source } });
        assert(result.success, JSON.stringify(result));
        const module = new WebAssembly.Module(result.bytes);
        assert.deepEqual([
          ...new Uint8Array(
            WebAssembly.Module.customSections(module, "blot:ownership")[0],
          ),
        ], [2, 2, 0]);
        const raw = new WebAssembly.Instance(module).exports;
        const memory = raw["blot:memory"] as WebAssembly.Memory;
        const made = Number((raw.make as CallableFunction)(3));
        assert.deepEqual([...new Uint32Array(memory.buffer, made + 4, 3)], [
          41,
          42,
          43,
        ]);
        // Low-level callers keep the invocation group until explicit reset.
        const copied = Number((raw.copy as CallableFunction)(made));
        assert.deepEqual([...new Uint32Array(memory.buffer, made + 4, 3)], [
          41,
          42,
          43,
        ]);
        assert.deepEqual([...new Uint32Array(memory.buffer, copied + 4, 3)], [
          99,
          42,
          43,
        ]);
        assert.equal((raw.first as CallableFunction)(made), 41);
        (raw["blot:reset"] as CallableFunction)(0);
        assert.equal((raw["blot:rc_roots"] as WebAssembly.Global).value, 0);
        const input = Number((raw["blot:allocate"] as CallableFunction)(12));
        new Uint32Array(memory.buffer, input, 3).set([2, 7, 8]);
        assert.equal((raw.first as CallableFunction)(input), 7);
        (raw["blot:reset"] as CallableFunction)(0);
        assert.equal((raw["blot:rc_roots"] as WebAssembly.Global).value, 0);
        const guest = await instantiateGuest(module);
        try {
          const snapshot = guest.call("make", 3) as Uint32Array;
          assert.deepEqual([...snapshot], [41, 42, 43]);
          for (let index = 0; index < 100; index++) {
            assert.deepEqual([
              ...(guest.call("copy", Uint32Array.of(1, 2, 3)) as Uint32Array),
            ], [99, 2, 3]);
            assert.deepEqual([
              ...(guest.call(
                "floats",
                Float32Array.of(1.5, 3.5),
              ) as Float32Array),
            ], [2.5, 3.5]);
          }
          assert.throws(
            () => guest.call("trapped", Uint32Array.of(99, 2)),
            WebAssembly.RuntimeError,
          );
          assert.equal(guest.call("first", Uint32Array.of(7)), 7);
          assert.deepEqual([...snapshot], [41, 42, 43]);
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

Deno.test("static demands and List caches publish exact persistent reference roots", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const source = `
const delay = func ~value => return value
const pending = delay (@array.fill 3 40)
const alias = pending
const values = [#[10, 11], #[20, 21], #[30, 31]]
entry const run = func (index: U32) => return do:
  let before = @force pending
  let after = @force alias
  let total = 0
  for selected in values:
    total := self + selected[1]
  break before[1] + after[2] + total + index
entry const pressure = func (count: U32) => return do:
  let values = @array.fill count 99
  break values[count - 1]
`;
  try {
    for (const tier of ["development", "optimized"] as const) {
      const compiler = await createZigProjectCompiler({
        executable,
        entry,
        prelude: new URL("../../std/prelude.blot", import.meta.url),
        cacheDirectory: false,
        codegenTier: tier,
      });
      try {
        const result = await compiler.build({ sources: { [entry]: source } });
        assert(result.success, JSON.stringify(result));
        const module = new WebAssembly.Module(result.bytes);
        assert.deepEqual([
          ...new Uint8Array(
            WebAssembly.Module.customSections(module, "blot:ownership")[0],
          ),
        ], [2, 2, 0]);
        const raw = new WebAssembly.Instance(module).exports;
        const count = (name: string) =>
          Number((raw[`blot:rc_${name}`] as WebAssembly.Global).value);
        assert(count("roots") > 0);
        for (const index of [0, 2, 1, 0]) {
          assert.equal((raw.run as CallableFunction)(index), 143 + index);
          assert.equal((raw.pressure as CallableFunction)(32768), 99);
          assert.equal(count("roots"), 1);
        }
        const retired = count("destroyed");
        (raw["blot:ownership_leave"] as CallableFunction)(2);
        assert.equal(count("roots"), 0);
        assert.equal(count("leases"), 0);
        assert(count("destroyed") > retired);
        const guest = await instantiateGuest(module);
        try {
          for (const index of [0, 2, 1, 0]) {
            assert.equal(guest.call("run", index), 143 + index);
          }
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

Deno.test("persistent records in Lists and Arrays own closure captures and shared demand results", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const source = `
const delay = func ~value => return value
const build = func () => return do:
  let children = #[40, 41]
  let pending = delay children
  let read = func (index: U32) => return children[index]
  break @list.fill 3 {pending, read}
let saved = build ()
entry const run = func (value: U32) => return do:
  let values = @array.from_list saved
  let before = values
  values[0] := {pending: delay #[value, value + 1], read: func (index: U32) => return value + index}
  let old = before[0]
  let changed = values[0]
  let cached = @force old.pending
  let current = @force changed.pending
  break cached[1] + current[1] + old.read 1 + changed.read 1
`;
  try {
    for (const tier of ["development", "optimized"] as const) {
      const compiler = await createZigProjectCompiler({
        executable,
        entry,
        prelude: new URL("../../std/prelude.blot", import.meta.url),
        cacheDirectory: false,
        codegenTier: tier,
      });
      try {
        const result = await compiler.build({ sources: { [entry]: source } });
        assert(result.success, JSON.stringify(result));
        const module = new WebAssembly.Module(result.bytes);
        assert.deepEqual([
          ...new Uint8Array(
            WebAssembly.Module.customSections(module, "blot:ownership")[0],
          ),
        ], [2, 2, 0]);
        const raw = new WebAssembly.Instance(module).exports;
        const roots = () =>
          Number((raw["blot:rc_roots"] as WebAssembly.Global).value);
        const baseline = roots();
        assert(baseline > 0);
        for (const value of [1, 20, 1, 40]) {
          assert.equal((raw.run as CallableFunction)(value), 84 + 2 * value);
          assert.equal(roots(), baseline);
        }
        (raw["blot:ownership_leave"] as CallableFunction)(2);
        assert.equal(roots(), 0);
        assert.equal(
          Number((raw["blot:rc_leases"] as WebAssembly.Global).value),
          0,
        );
        const guest = await instantiateGuest(module);
        try {
          for (const value of [1, 20, 1, 40]) {
            assert.equal(guest.call("run", value), 84 + 2 * value);
          }
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

Deno.test("counted reference loop roots plateau across repeated guest calls and teardown", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const compiler = await createZigProjectCompiler({
    executable,
    entry,
    prelude: new URL("../../std/prelude.blot", import.meta.url),
    cacheDirectory: false,
    codegenTier: "optimized",
  });
  try {
    const result = await compiler.build({
      sources: {
        [entry]: `
entry const run = func (count: U32) => return do:
  let values = #[41, 42]
  let before = values
  for index in 0..count:
    values := #[self[0] + 1, self[1] + 1]
  break before[0] + values[0]
entry const memory = func () : Array U32 => return #[]
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
    const run = raw.run as CallableFunction;
    const memory = raw["blot:memory"] as WebAssembly.Memory;
    assert.equal(run(5000), 5082);
    const warm = memory.buffer.byteLength;
    for (let index = 0; index < 10; index++) {
      assert.equal(run(50000), 50082);
      assert.equal(memory.buffer.byteLength, warm);
      assert.equal((raw["blot:rc_roots"] as WebAssembly.Global).value, 0);
      assert.equal((raw["blot:rc_leases"] as WebAssembly.Global).value, 0);
    }
    (raw["blot:ownership_leave"] as CallableFunction)(2);
    assert.equal((raw["blot:rc_roots"] as WebAssembly.Global).value, 0);
    const guest = await instantiateGuest(module);
    try {
      assert.equal(guest.call("run", 5000), 5082);
      const warm = guest.memoryBytes();
      for (let index = 0; index < 10; index++) {
        assert.equal(guest.call("run", 50000), 50082);
        assert.equal(guest.memoryBytes(), warm);
      }
    } finally {
      guest.dispose();
    }
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});

// Issue 9: in-place Array loops must not pay journal work per iteration, and
// shared or replaced carries must keep their counted owners.
const inPlaceLoopSource = `
const sorted_ids = func (count: U32) : Array U32 => return do:
  let keys = @array.generate count (func (i: U32) => return (i * 7919 + 13) % 1009)
  let ids = @array.generate count (func (i: U32) => return i)
  for i in 1..count:
    let j = i
    for 0..i:
      if j == 0:
        break
      let previous = keys[j - 1]
      let current = keys[j]
      if previous <= current:
        break
      keys[j] := previous
      keys[j - 1] := current
      let previous_id = ids[j - 1]
      let current_id = ids[j]
      ids[j] := previous_id
      ids[j - 1] := current_id
      j := self - 1
  break ids
entry const order = sorted_ids
entry const order_checksum = func (count: U32) => return do:
  let ids = sorted_ids count
  let total = 0
  for i in 0..count:
    total := self + (i + 1) * ids[i]
  break total
entry const paths = func (count: U32) : Array F32 => return do:
  let rows = @array.generate 8 (func (r: U32) => return @array.fill 4 r)
  let costs = @array.fill count 1.0
  let total = 0
  for step in 0..count:
    let slot = step % 8
    let row = rows[slot]
    rows[slot] := #[row[0] + 1, row[1] + step, row[2], row[3] + row[0]]
    costs[step] := costs[step] + U32.to_f32 (row[1] % 1000)
    total := self + rows[slot][1] % 1000
  let sum = 0.0
  for cost in costs:
    sum := self + cost
  break #[U32.to_f32 total, sum, U32.to_f32 rows[7][0], U32.to_f32 rows[3][3]]
entry const snapshots = func (count: U32) => return do:
  let values = @array.fill count 0
  let before = values
  let seen = 0
  for i in 0..count:
    let snapshot = values
    values[i] := i + 1
    seen := self + snapshot[i] + values[i]
  let total = 0
  for value in before:
    total := self + value
  break seen * 1000 + total
entry const escapes = func (count: U32) => return do:
  let values = @array.fill 4 0
  let holder = @array.generate count (func (i: U32) => return @array.fill 1 i)
  for i in 0..count:
    values[i % 4] := i
    holder[i] := values
  let total = 0
  for i in 0..count:
    let row = holder[i]
    total := self + row[0] + row[1] * 3 + row[2] * 5 + row[3] * 7
  break total
entry const swaps = func (count: U32) => return do:
  let a = @array.fill 8 1
  let b = @array.fill 8 2
  let total = 0
  for i in 0..count:
    a[i % 8] := a[i % 8] + 1
    let t = a
    a := b
    b := t
    total := self + a[0] + b[0]
  break total
`;
function expectedEscapes(count: number): number {
  const values = [0, 0, 0, 0];
  let total = 0;
  for (let i = 0; i < count; i++) {
    values[i % 4] = i;
    total += values[0] + values[1] * 3 + values[2] * 5 + values[3] * 7;
  }
  return total >>> 0;
}
function expectedSwaps(count: number): number {
  let a = new Array(8).fill(1);
  let b = new Array(8).fill(2);
  let total = 0;
  for (let i = 0; i < count; i++) {
    a = [...a];
    a[i % 8] += 1;
    [a, b] = [b, a];
    total += a[0] + b[0];
  }
  return total >>> 0;
}
function expectedOrder(count: number): number[] {
  const keys = Array.from({ length: count }, (_, i) => (i * 7919 + 13) % 1009);
  return Array.from({ length: count }, (_, i) => i).sort((left, right) =>
    keys[left] - keys[right] || left - right
  );
}
function expectedPaths(count: number): number[] {
  const rows = Array.from({ length: 8 }, (_, r) => [r, r, r, r]);
  const costs = new Float32Array(count).fill(1);
  let total = 0;
  for (let step = 0; step < count; step++) {
    const row = rows[step % 8];
    rows[step % 8] = [row[0] + 1, row[1] + step, row[2], row[3] + row[0]];
    costs[step] = Math.fround(costs[step] + (row[1] % 1000));
    total += rows[step % 8][1] % 1000;
  }
  let sum = 0;
  for (const cost of costs) sum = Math.fround(sum + cost);
  return [total, sum, rows[7][0], rows[3][3]];
}

Deno.test("in-place Array loops keep exact results, constant journal work and plateaued memory", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  try {
    for (const tier of ["development", "optimized"] as const) {
      const compiler = await createZigProjectCompiler({
        executable,
        entry,
        prelude: new URL("../../std/prelude.blot", import.meta.url),
        cacheDirectory: false,
        codegenTier: tier,
      });
      try {
        const result = await compiler.build({
          sources: { [entry]: inPlaceLoopSource },
        });
        assert(result.success, JSON.stringify(result));
        const module = new WebAssembly.Module(result.bytes);
        assert.deepEqual([
          ...new Uint8Array(
            WebAssembly.Module.customSections(module, "blot:ownership")[0],
          ),
        ], [2, 2, 0]);
        const raw = new WebAssembly.Instance(module).exports;
        const counter = (name: string) =>
          Number((raw[`blot:rc_${name}`] as WebAssembly.Global).value);
        const checksum = raw.order_checksum as CallableFunction;
        const snapshots = raw.snapshots as CallableFunction;
        // Journal retains per call do not grow with the iteration count: the
        // carried Arrays keep one stable slot and no iteration republishes.
        const retained: number[] = [];
        for (const count of [2, 64, 512, 64, 512]) {
          const before = counter("retains");
          const order = expectedOrder(count);
          let expected = 0;
          for (let i = 0; i < count; i++) expected += (i + 1) * order[i];
          assert.equal(checksum(count), expected);
          retained.push(counter("retains") - before);
          assert.equal(counter("roots"), 0);
          assert.equal(counter("leases"), 0);
        }
        assert.equal(new Set(retained).size, 1, `retains ${retained}`);
        // A live snapshot, an escape into another Array and swapped carries
        // force the copy path or a real slot store on every edit.
        const escapes = raw.escapes as CallableFunction;
        const swaps = raw.swaps as CallableFunction;
        for (const count of [0, 1, 17, 300]) {
          assert.equal(snapshots(count), count * (count + 1) / 2 * 1000);
          assert.equal(escapes(count), expectedEscapes(count));
          assert.equal(swaps(count), expectedSwaps(count));
          assert.equal(counter("roots"), 0);
          assert.equal(counter("leases"), 0);
        }
        const guest = await instantiateGuest(module);
        try {
          for (const count of [0, 1, 2, 3, 100, 257]) {
            assert.deepEqual(
              Array.from(guest.call("order", count) as Uint32Array),
              expectedOrder(count),
            );
          }
          for (const count of [0, 1, 9, 1000]) {
            assert.deepEqual(
              Array.from(guest.call("paths", count) as Float32Array),
              expectedPaths(count),
            );
          }
          // Thousands of calls carrying an Array of references: replaced
          // children retire and committed memory stays at its warmed size.
          const expected = expectedPaths(256);
          for (let index = 0; index < 50; index++) guest.call("paths", 256);
          const warm = guest.memoryBytes();
          assert(warm > 0);
          for (let index = 0; index < 3000; index++) {
            const values = guest.call("paths", 256) as Float32Array;
            if (index % 500 === 0) assert.deepEqual(Array.from(values), expected);
          }
          assert.equal(guest.memoryBytes(), warm);
          for (let index = 0; index < 20; index++) guest.call("order", 512);
          const sorted = guest.memoryBytes();
          for (let index = 0; index < 200; index++) guest.call("order", 512);
          assert.equal(guest.memoryBytes(), sorted);
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
