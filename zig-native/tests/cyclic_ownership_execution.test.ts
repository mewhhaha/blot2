import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../compiler/guest.ts";
import { compileAndRun } from "./compile_helpers.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";

const cycleDefinitions = `
type State a is effect = { get: Unit -> a, set: a -> Unit }
type Node is data = #End | #Next (Unit -> Node ! {State.get Node})
const keep = func ~value => return func () => return @demand value
const get = func (witness: Unit -> a) : a => return State.get ()
const cycle = func (seed: U32) => return do:
  let (_, result) = @effect.run State.get State.set #End (func () => return do:
    let delayed = keep (get (func () => return #End))
    use State.set (#Next delayed)
    use first <- delayed ()
    use State.set #End
    use cached <- delayed ()
    break case cached of
      #End => @panic "the demand lost its memoized cycle"
      #Next same => do:
        use again <- same ()
        break case again of
          #End => @panic "the retained closure lost its memo"
          #Next _ => seed
  )
  break result
`;

const cycleSource = `${cycleDefinitions}
entry const run = func (count: U32) => return do:
  let index = 0
  let sum = 0
  for ever:
    if index == count:
      break sum
    sum := self + cycle index
    index := self + 1
entry const memory = func () : Array U32 => return #[]
`;

async function compileCyclesInBothTiers(
  source: string,
  run: (
    bytes: Uint8Array<ArrayBuffer>,
    tier: "development" | "optimized",
  ) => void,
) {
  const directory = await Deno.makeTempDir({
    prefix: "blot-cycle-retirement-",
  });
  const entry = `${directory}/main.blot`;
  try {
    for (const codegenTier of ["development", "optimized"] as const) {
      const compiler = await createZigProjectCompiler({
        executable: Deno.args[0],
        entry,
        codegenTier,
        cacheDirectory: false,
        prelude: new URL("../../std/prelude.blot", import.meta.url),
        stdRoot: new URL("../../std/", import.meta.url),
      });
      try {
        const built = await compiler.build({ sources: { [entry]: source } });
        assert(built.success, JSON.stringify(built));
        run(built.bytes, codegenTier);
      } finally {
        await compiler.close();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
}

Deno.test("source State and strong demand cycles retire locally during sustained execution", async () => {
  await compileCyclesInBothTiers(cycleSource, (bytes, tier) => {
    const module = new WebAssembly.Module(bytes);
    assert.deepEqual([
      ...new Uint8Array(
        WebAssembly.Module.customSections(module, "blot:ownership")[0],
      ),
    ], [2, 2, 0]);
    assert.deepEqual([
      ...new Uint8Array(
        WebAssembly.Module.customSections(module, "blot:cycles")[0],
      ),
    ], [1, 1]);
    const raw = new WebAssembly.Instance(module).exports;
    const count = (name: string) =>
      Number((raw[`blot:${name}`] as WebAssembly.Global).value);
    const run = raw.run as CallableFunction;
    let allocationsPerCycle = 1;
    // The scalar seed lives directly in its callback environment word.
    if (tier === "development") allocationsPerCycle = 3;
    const destroyed = count("rc_destroyed");
    assert.equal(run(512), 511 * 512 / 2);
    const memory = raw["blot:memory"] as WebAssembly.Memory;
    const warm = memory.buffer.byteLength;
    const passes = count("cycle_passes"), reclaimed = count("cycle_bytes");
    if (reclaimed === 0) {
      assert.equal(passes, 0);
      assert.equal(
        count("rc_destroyed") - destroyed,
        512 * allocationsPerCycle,
      );
    } else {
      assert(passes > 0);
    }
    assert.equal(run(20000), 19999 * 20000 / 2);
    if (reclaimed === 0) {
      for (
        const name of [
          "cycle_passes",
          "cycle_vertices",
          "cycle_edges",
          "cycle_bytes",
        ]
      ) {
        assert.equal(count(name), 0);
      }
      assert.equal(
        count("rc_destroyed") - destroyed,
        20512 * allocationsPerCycle,
      );
    } else {
      assert(count("cycle_passes") > passes);
      assert(count("cycle_bytes") > reclaimed);
    }
    assert.equal(memory.buffer.byteLength, warm);
    assert.equal(count("rc_roots"), 0);
    assert.equal(count("rc_leases"), 0);
    (raw["blot:ownership_leave"] as CallableFunction)(2);
  });
});

Deno.test("an unconfined State graph retains real local cycle collection under sustained execution", async () => {
  await compileCyclesInBothTiers(
    cycleSource.replace(
      "    use State.set #End",
      "    use State.set (#Next delayed)",
    ),
    (bytes) => {
      const module = new WebAssembly.Module(bytes);
      assert.deepEqual([
        ...new Uint8Array(
          WebAssembly.Module.customSections(module, "blot:ownership")[0],
        ),
      ], [2, 2, 0]);
      assert.deepEqual([
        ...new Uint8Array(
          WebAssembly.Module.customSections(module, "blot:cycles")[0],
        ),
      ], [1, 1]);
      const raw = new WebAssembly.Instance(module).exports;
      const count = (name: string) =>
        Number((raw[`blot:${name}`] as WebAssembly.Global).value);
      const run = raw.run as CallableFunction;
      assert.equal(run(512), 511 * 512 / 2);
      const memory = raw["blot:memory"] as WebAssembly.Memory;
      const warm = memory.buffer.byteLength;
      const passes = count("cycle_passes"), reclaimed = count("cycle_bytes");
      assert(
        reclaimed > 0,
        "local deletion must reclaim source cycles; tracing alone cannot satisfy this law",
      );
      assert.equal(run(20000), 19999 * 20000 / 2);
      assert(count("cycle_passes") > passes);
      assert(count("cycle_bytes") > reclaimed);
      assert.equal(memory.buffer.byteLength, warm);
      assert.equal(count("rc_roots"), 0);
      assert.equal(count("rc_leases"), 0);
      (raw["blot:ownership_leave"] as CallableFunction)(2);
    },
  );
});

Deno.test("a large retained heap preserves its owner while local cycle passes use their own traffic trigger", async () => {
  const source = cycleSource.replace(
    "  let index = 0",
    "  let older = @array.fill 1048576 7\n  let index = 0",
  )
    .replace("      break sum", "      break sum + older[1048575]");
  await compileCyclesInBothTiers(source, (bytes, tier) => {
    const module = new WebAssembly.Module(bytes);
    assert.deepEqual([
      ...new Uint8Array(
        WebAssembly.Module.customSections(module, "blot:ownership")[0],
      ),
    ], [2, 2, 0]);
    const raw = new WebAssembly.Instance(module).exports;
    const count = (name: string) =>
      Number((raw[`blot:${name}`] as WebAssembly.Global).value);
    let allocationsPerCycle = 1;
    // The scalar seed lives directly in its callback environment word.
    if (tier === "development") allocationsPerCycle = 3;
    const destroyed = count("rc_destroyed");
    assert.equal((raw.run as CallableFunction)(20000), 199990007);
    const reclaimed = count("cycle_bytes");
    if (reclaimed === 0) {
      for (
        const name of [
          "cycle_passes",
          "cycle_vertices",
          "cycle_edges",
          "cycle_bytes",
        ]
      ) {
        assert.equal(count(name), 0);
      }
      assert.equal(
        count("rc_destroyed") - destroyed,
        20000 * allocationsPerCycle + 1,
      );
    } else {
      assert(count("cycle_passes") > 1);
    }
    const memory = raw["blot:memory"] as WebAssembly.Memory;
    const warm = memory.buffer.byteLength;
    const warmedDestroyed = count("rc_destroyed");
    assert.equal((raw.run as CallableFunction)(20000), 199990007);
    assert.equal(memory.buffer.byteLength, warm);
    if (reclaimed === 0) {
      assert.equal(
        count("rc_destroyed") - warmedDestroyed,
        20000 * allocationsPerCycle + 1,
      );
      assert.equal(count("cycle_bytes"), 0);
    } else {
      assert(count("cycle_bytes") > reclaimed);
    }
    assert.equal((raw["blot:rc_roots"] as WebAssembly.Global).value, 0);
    assert.equal((raw["blot:rc_leases"] as WebAssembly.Global).value, 0);
    (raw["blot:ownership_leave"] as CallableFunction)(2);
  });
});

const suspendedSource = `${cycleDefinitions}

entry const run = func (host: Unit -> U32 ! {Foreign}) => return do:
  use outcome <- @effect.run State.get State.set #End (func () => return do:
    let delayed = keep (get (func () => return #End))
    use State.set (#Next delayed)
    use first <- delayed ()
    use State.set #End
    for index in 0..4000:
      let discarded = cycle index
    use seed <- host ()
    use cached <- delayed ()
    break case cached of
      #End => @panic "the suspended memo lost its cycle"
      #Next same => do:
        use again <- same ()
        break case again of
          #End => @panic "the suspended closure lost its memo"
          #Next _ => seed
  )
  let (_, result) = outcome
  break result
entry const memory = func () : Array U32 => return #[]
`;

Deno.test("live JSPI memo cycles survive local pressure and retire on settlement or rejection", async () => {
  await compileAndRun(suspendedSource, async (_, bytes) => {
    const module = new WebAssembly.Module(bytes);
    assert.deepEqual([
      ...new Uint8Array(
        WebAssembly.Module.customSections(module, "blot:ownership")[0],
      ),
    ], [2, 2, 0]);
    const jspi = WebAssembly as unknown as {
      Suspending: new (
        callback: (reference: unknown) => Promise<number>,
      ) => WebAssembly.ImportValue;
      promising(fn: CallableFunction): (...args: unknown[]) => Promise<number>;
    };
    let settle: ((value: number) => void) | undefined;
    let reject: ((reason: unknown) => void) | undefined;
    const raw = new WebAssembly.Instance(module, {
      "blot:host/1": {
        call_unit_u32: new jspi.Suspending(() =>
          new Promise<number>((resolve, fail) => {
            settle = resolve;
            reject = fail;
          })
        ),
      },
    }).exports;
    const count = (name: string) =>
      Number((raw[`blot:${name}`] as WebAssembly.Global).value);
    const enter = raw["blot:ownership_enter"] as CallableFunction;
    const leave = raw["blot:ownership_leave"] as CallableFunction;
    const run = jspi.promising(raw.run as CallableFunction);
    const memory = raw["blot:memory"] as WebAssembly.Memory;
    enter();
    const pending = run({});
    assert(count("cycle_passes") > 0);
    assert(count("cycle_bytes") > 0);
    assert(count("rc_roots") > 0);
    assert(count("rc_leases") > 0);
    settle!(42);
    assert.equal(await pending, 42);
    leave(0);
    assert.equal(count("rc_roots"), 0);
    assert.equal(count("rc_leases"), 0);
    const reclaimed = count("cycle_bytes");
    const warm = memory.buffer.byteLength;
    enter();
    const failed = run({});
    reject!(new Error("cycle host rejection"));
    await assert.rejects(failed, /cycle host rejection/);
    leave(1);
    assert.equal(count("rc_roots"), 0);
    assert.equal(count("rc_leases"), 0);
    assert(count("cycle_bytes") > reclaimed);
    assert.equal(memory.buffer.byteLength, warm);
    leave(2);
  });
});

const cancellationSource = `${cycleDefinitions}

type Tick is effect = { read: U32 -> U32 }
const abort = func computation => return do:
  for request in @requests computation:
    case request of
      effect Tick.read value =>
        break 7
      complete value =>
        break value
  break 7
entry const run = func (count: U32) => return do:
  let sum = 0
  for index in 0..count:
    let work = @computation (func () => return do:
      use outcome <- @effect.run State.get State.set #End (func () => return do:
        let delayed = keep (get (func () => return #End))
        use State.set (#Next delayed)
        use first <- delayed ()
        use State.set #End
        for pressure in 0..64:
          let discarded = cycle pressure
        use resumed <- Tick.read index
        use cached <- delayed ()
        break case cached of
          #End => @panic "the request lost its ready memo"
          #Next _ => resumed
      )
      let (_, result) = outcome
      break result
    )
    let result = abort work
    sum := self + result
  break sum
entry const memory = func () : Array U32 => return #[]
`;

Deno.test("canceling suspended request cycles removes roots and reclaims ready memo graphs", async () => {
  await compileAndRun(cancellationSource, (_, bytes) => {
    const module = new WebAssembly.Module(bytes);
    assert.deepEqual([
      ...new Uint8Array(
        WebAssembly.Module.customSections(module, "blot:ownership")[0],
      ),
    ], [2, 2, 0]);
    const raw = new WebAssembly.Instance(module).exports;
    const count = (name: string) =>
      Number((raw[`blot:${name}`] as WebAssembly.Global).value);
    const run = raw.run as CallableFunction;
    assert.equal(run(64), 448);
    const warm = (raw["blot:memory"] as WebAssembly.Memory).buffer.byteLength;
    const reclaimed = count("cycle_bytes");
    assert.equal(run(2048), 14336);
    assert(count("cycle_bytes") > reclaimed);
    assert.equal(count("rc_roots"), 0);
    assert.equal(count("rc_leases"), 0);
    assert.equal(
      (raw["blot:memory"] as WebAssembly.Memory).buffer.byteLength,
      warm,
    );
    (raw["blot:ownership_leave"] as CallableFunction)(2);
  });
});

Deno.test("scalar List constructors snapshots and edits skip cycle scans", async () => {
  await compileAndRun(
    `
entry const run = func (count: U32) => return do:
  let values = @list.fill count 42
  let original = values
  values := [1, 2, 3, ...self]
  let joined_array = @array.from_list values
  let original_array = @array.from_list original
  break joined_array[3] + original_array[0]
entry const memory = func () : Array U32 => return #[]
`,
    (_, bytes) => {
      const module = new WebAssembly.Module(bytes);
      assert.deepEqual([
        ...new Uint8Array(
          WebAssembly.Module.customSections(module, "blot:ownership")[0],
        ),
      ], [2, 2, 0]);
      const raw = new WebAssembly.Instance(module).exports;
      assert.equal((raw.run as CallableFunction)(8192), 84);
      assert.equal((raw["blot:cycle_passes"] as WebAssembly.Global).value, 0);
      assert.equal((raw["blot:cycle_edges"] as WebAssembly.Global).value, 0);
      assert.equal((raw["blot:rc_roots"] as WebAssembly.Global).value, 0);
      assert.equal((raw["blot:rc_leases"] as WebAssembly.Global).value, 0);
      (raw["blot:ownership_leave"] as CallableFunction)(2);
    },
  );
});

Deno.test("zero-child admitted source keeps cycle work absent and validates counter metadata", async () => {
  await compileAndRun(
    `
entry const run = func (count: U32) => return do:
  let values = @array.fill count 42
  let original = values
  values[0] := 7
  break original[0] + values[0]
`,
    async (_, bytes) => {
      const module = new WebAssembly.Module(bytes);
      assert.deepEqual([
        ...new Uint8Array(
          WebAssembly.Module.customSections(module, "blot:ownership")[0],
        ),
      ], [2, 2, 0]);
      const raw = new WebAssembly.Instance(module).exports;
      for (let i = 0; i < 100; i++) {
        assert.equal(
          (raw.run as CallableFunction)(8192),
          49,
        );
      }
      assert.equal((raw["blot:cycle_passes"] as WebAssembly.Global).value, 0);
      assert.equal((raw["blot:cycle_edges"] as WebAssembly.Global).value, 0);
      assert.equal((raw["blot:rc_roots"] as WebAssembly.Global).value, 0);
      assert.equal((raw["blot:rc_leases"] as WebAssembly.Global).value, 0);
      (raw["blot:ownership_leave"] as CallableFunction)(2);
      const name = new TextEncoder().encode("blot:cycles");
      const invalid = bytes.slice();
      const position = invalid.findIndex((_, i) =>
        name.every((byte, j) => invalid[i + j] === byte)
      );
      assert(position >= 0);
      invalid[position + name.length] = 2;
      await assert.rejects(
        () => instantiateGuest(invalid),
        /Invalid cycle section/,
      );
      const duplicate = new Uint8Array(bytes.length + name.length + 5);
      duplicate.set(bytes);
      duplicate.set(
        [0, name.length + 3, name.length, ...name, 1, 1],
        bytes.length,
      );
      await assert.rejects(
        () => instantiateGuest(duplicate),
        /Duplicate cycle section/,
      );
    },
  );
});
