import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`rectangular record map flatten builds one destination (${codegenTier})`, async () => {
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0],
      entry: new URL(
        "../../benchmarks/runtime-boundaries/main.blot",
        import.meta.url,
      ),
      prelude: new URL("../../std/prelude.blot", import.meta.url),
      stdRoot: new URL("../../std", import.meta.url),
      cacheDirectory: false,
      codegenTier,
    });
    try {
      const built = await compiler.build();
      assert(built.success, JSON.stringify(built));
      const raw =
        new WebAssembly.Instance(new WebAssembly.Module(built.bytes)).exports;
      const retired = () =>
        Number((raw["blot:rc_destroyed"] as WebAssembly.Global).value) >>> 0;
      const invoke = (n: number, name = "pipeline") => {
        (raw["blot:ownership_enter"] as CallableFunction)();
        const result = (raw[name] as CallableFunction)(n) >>> 0;
        (raw["blot:ownership_leave"] as CallableFunction)(0);
        return result;
      };
      invoke(0);
      for (const count of [0, 1, 2, 32, 2000]) {
        const before = retired();
        assert.equal(invoke(count), (count * 24 * (count * 24 - 1) / 2) >>> 0);
        if (codegenTier === "optimized") {
          assert.equal(
            retired() - before,
            1,
            `count ${count}: fold and pipeline retain only output storage`,
          );
        }
        const beforeValues = retired();
        assert(invoke(count, "pipeline_values") > 0);
        assert.equal(
          retired() - beforeValues,
          1,
          `count ${count}: pipeline itself builds only output storage in both tiers`,
        );
      }
    } finally {
      await compiler.dispose();
    }
  });
}

const controls = `import * as array from "std/array"
type Command is data = #Command {lanes: Array U32, audit: U32}
entry const saved = fn (count: U32) => do:
  let commands = array.generate count (fn i => #Command {lanes: array.generate 3 (fn j => i * 3 + j), audit: i})
  let chunks = array.map (fn c => c.lanes) commands
  let lanes = array.flatten chunks
  break lanes.length + (if count == 0 then 0 else commands[0].audit + chunks[0][2])
entry const ragged = fn (count: U32) => do:
  let commands = array.generate count (fn i => #Command {lanes: array.generate (i + 1) (fn j => i + j), audit: i})
  let chunks = array.map (fn c => c.lanes) commands
  let lanes = array.flatten chunks
  break lanes.length
entry const trap = fn (divisor: U32) => do:
  let commands = array.generate 2 (fn i => #Command {lanes: array.generate 3 (fn j => i + j), audit: 1 / divisor})
  let chunks = array.map (fn c => c.lanes) commands
  let lanes = array.flatten chunks
  break lanes[0]
const constant = array.flatten #[#[3, 4], #[], #[5]]
entry const constant_read = fn (index: U32) => constant[index]
type Floating is data = #Floating {lanes: Array F32}
entry const floats = fn (seed: F32) => do:
  let commands = array.generate 3 (fn i => #Floating {lanes: array.generate 24 (fn j => (seed + @u32.to_f32 i) * @u32.to_f32 j)})
  let chunks = array.map (fn c => c.lanes) commands
  let lanes = array.flatten chunks
  break lanes
`;
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`pipeline fallback preserves snapshots ragged lengths traps and F32 order (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-pipeline-controls-",
    });
    const entry = `${directory}/main.blot`;
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0],
      entry,
      prelude: new URL("../../std/prelude.blot", import.meta.url),
      stdRoot: new URL("../../std", import.meta.url),
      cacheDirectory: false,
      codegenTier,
    });
    try {
      const built = await compiler.build({ sources: { [entry]: controls } });
      assert(built.success, JSON.stringify(built));
      const { instantiateGuest } = await import("../../compiler/guest.ts");
      const guest = await instantiateGuest(built.bytes);
      try {
        for (const count of [0, 1, 2, 32, 128]) {
          assert.equal(
            guest.call("saved", count),
            count * 3 + (count === 0 ? 0 : 2),
          );
          assert.equal(guest.call("ragged", count), count * (count + 1) / 2);
        }
        assert.throws(() => guest.call("trap", 0), WebAssembly.RuntimeError);
        assert.equal(guest.call("trap", 1), 0);
        for (const [index, expected] of [3, 4, 5].entries()) {
          assert.equal(guest.call("constant_read", index), expected);
        }
        for (const seed of [-0, 1.234567, Infinity, -Infinity]) {
          const expected = Float32Array.from(
            { length: 72 },
            (_, index) =>
              Math.fround(
                Math.fround(Math.fround(seed) + Math.floor(index / 24)) *
                  (index % 24),
              ),
          );
          const actual = guest.call("floats", seed) as Float32Array;
          for (let i = 0; i < expected.length; i++) {
            assert(Object.is(actual[i], expected[i]), `lane ${i}`);
          }
        }
      } finally {
        guest.dispose();
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
