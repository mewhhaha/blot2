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
entry const forward = fn (count: U32) => do:
  let values: List U32 = []
  for index in 0..count:
    values := [...self, index]
  return Array.from_list values
entry const backward = fn (count: U32) => do:
  let values: List U32 = []
  for index in 0..count:
    values := [index, ...self]
  return Array.from_list values
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
const make = fn (value: U32) => #[value, value + 1]
const choose = fn (values: Array (Array U32)) => values[0]
entry const run = fn (value: U32) => do:
  let child = make value
  let parent = #[child, child]
  let alias = choose parent
  return alias[0] + parent[1][1]
entry const trapped = fn (value: U32) => do:
  let values = make value
  return values[value]
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
const make = fn (value: U32) => #[value, value + 1]
const first = fn (end: U32) => fn (value: U32) => do:
  for index in 0..end:
    let values = make (value + index)
    if index == 3:
      return values
  return make value
entry const run = fn (end: U32) => do:
  let values = make 41
  let before = values
  let previous = make 99
  for index in 0..end:
    let old = values
    values := make (old[0] + 1)
    previous := old
    if index == 6:
      break
  return before[0] + values[0] + previous[0] + (first end 100)[0]
entry const trapped = fn (end: U32) => do:
  let values = make 41
  for index in 0..end:
    values := make (self[0] + 1)
  return values[10]
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
const delay = fn ~value => value
let values = @array.fill 3 40
let saved = (fn (capture: Array U32) => fn (index: U32) => capture[index]) values
let pending = delay (@array.fill 3 (saved 0))
let alias = pending
entry const run = fn (value: U32) => do:
  let before = @force pending
  let after = @force alias
  let changed = @array.set values 0 value
  return saved 2 + before[1] + after[2] + changed[0]
entry const pressure = fn (count: U32) => do:
  let values = @array.fill count 99
  return values[count - 1]
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
const delay = fn ~value => value
entry const run = fn (value: U32) => do:
  let (_, result) = @state.run (#Cell #[value]) (fn () => do:
    let pending = delay (do:
      use cell <- @state.get (fn () => #Cell #[0])
      let #Cell values = cell
      return values)
    use before <- @force pending
    use @state.set (#Cell #[value + 100])
    use after <- @force pending
    return before[0] + after[0])
  return result
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
entry const make = fn (count: U32) => @array.generate count (fn index => index + 41)
entry const copy = fn (values: Array U32) => @array.set values 0 99
entry const first = fn (values: Array U32) => values[0]
entry const floats = fn (values: Array F32) => @array.set values 0 2.5
entry const trapped = fn (values: Array U32) => values[values[0]]
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
const delay = fn ~value => value
const pending = delay (@array.fill 3 40)
const alias = pending
const values = [#[10, 11], #[20, 21], #[30, 31]]
entry const run = fn (index: U32) => do:
  let before = @force pending
  let after = @force alias
  let total = 0
  for selected in values:
    total := self + selected[1]
  return before[1] + after[2] + total + index
entry const pressure = fn (count: U32) => do:
  let values = @array.fill count 99
  return values[count - 1]
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
const delay = fn ~value => value
const build = fn () => do:
  let children = #[40, 41]
  let pending = delay children
  let read = fn (index: U32) => children[index]
  return @list.fill 3 {pending, read}
let saved = build ()
entry const run = fn (value: U32) => do:
  let values = @array.from_list saved
  let before = values
  values[0] := {pending: delay #[value, value + 1], read: fn (index: U32) => value + index}
  let old = before[0]
  let changed = values[0]
  let cached = @force old.pending
  let current = @force changed.pending
  return cached[1] + current[1] + old.read 1 + changed.read 1
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
entry const run = fn (count: U32) => do:
  let values = #[41, 42]
  let before = values
  for index in 0..count:
    values := #[self[0] + 1, self[1] + 1]
  return before[0] + values[0]
entry const memory = fn () -> Array U32 => #[]
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
