import { strict as assert } from "node:assert";
import { compileAndRun } from "./compile_helpers.ts";

Deno.test("paired State frames keep aliases and nearer states beside forwarding providers", async () => {
  await compileAndRun(
    `
type State a is effect = { get: Unit -> a, set: a -> Unit }
type Inspect is effect = { read: Unit -> U32 }
const read = fn () => State.get ()
const write = fn value => State.set value
entry const run = fn (seed: U32) => do:
  let (final, result) = @effect.run State.get State.set #[seed, seed + 1] (fn () => do:
    use before <- read ()
    let inspect = @effect.provider Inspect.read (fn () => do:
      use outer <- read ()
      return outer[0]
    )
    let (inner_final, inner_result) = do inspect:
      return @effect.run State.get State.set #[77, 78] (fn () => do:
        use inspected <- Inspect.read ()
        use inner <- read ()
        use write #[79, 80]
        for index in 0..200:
          let pressure = @array.fill 8192 index
          if pressure[8191] != index:
            @panic "pressure"
        return #[inspected, inner[0], inner[1]]
      )
    use still_outer <- read ()
    use write #[seed + 2, seed + 3]
    return #[before[0], before[1], still_outer[0], inner_final[0], inner_result[0], inner_result[1], inner_result[2]]
  )
  return #[...result, final[0]]
`,
    (_, bytes) => {
      const module = new WebAssembly.Module(bytes);
      assert.deepEqual([
        ...new Uint8Array(
          WebAssembly.Module.customSections(module, "blot:ownership")[0],
        ),
      ], [2, 2, 0]);
      const raw = new WebAssembly.Instance(module).exports;
      const enter = raw["blot:ownership_enter"] as CallableFunction;
      const leave = raw["blot:ownership_leave"] as CallableFunction;
      const reset = raw["blot:reset"] as CallableFunction;
      const memory = raw["blot:memory"] as WebAssembly.Memory;
      let warmed = 0;
      for (const seed of [0, 8192, 65536, 0xffff_fffc, 0, 65536]) {
        enter();
        const pointer = (raw.run as CallableFunction)(seed);
        const words = new Uint32Array(memory.buffer, pointer + 4, 8);
        assert.deepEqual(
          words,
          Uint32Array.of(seed, seed + 1, seed, 79, seed, 77, 78, seed + 2),
        );
        if (warmed !== 0) assert.equal(memory.buffer.byteLength, warmed);
        warmed = memory.buffer.byteLength;
        leave(0);
        reset(0);
        assert.equal((raw["blot:rc_roots"] as WebAssembly.Global).value, 0);
        assert.equal((raw["blot:rc_leases"] as WebAssembly.Global).value, 0);
      }
    },
  );
});

Deno.test("paired State scalar slots preserve pointer-looking words and F32 snapshots", async () => {
  await compileAndRun(
    `
type State a is effect = { get: Unit -> a, set: a -> Unit }
entry const integer = fn (seed: U32) => do:
  let (final, before) = @effect.run State.get State.set seed (fn () => do:
    use before <- State.get ()
    use State.set (seed + 1)
    return before
  )
  return #[before, final]
entry const fraction = fn (seed: F32) => do:
  let (final, before) = @effect.run State.get State.set seed (fn () => do:
    use before <- State.get ()
    use State.set (seed + 0.5)
    return before
  )
  return #[before, final]
`,
    (guest, bytes) => {
      const module = new WebAssembly.Module(bytes);
      assert.deepEqual([
        ...new Uint8Array(
          WebAssembly.Module.customSections(module, "blot:ownership")[0],
        ),
      ], [2, 2, 0]);
      for (const seed of [0, 8192, 65536, 0xffff_fffc]) {
        assert.deepEqual(
          guest.call("integer", seed),
          Uint32Array.of(seed, seed + 1),
        );
      }
      for (const seed of [0, 1.5, -0.5, 8192]) {
        assert.deepEqual(
          guest.call("fraction", seed),
          Float32Array.of(seed, seed + 0.5),
        );
      }
    },
  );
});
