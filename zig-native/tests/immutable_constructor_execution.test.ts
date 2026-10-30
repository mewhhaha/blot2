import { strict as assert } from "node:assert";
import { compileAndRun } from "./compile_helpers.ts";

Deno.test("immutable nullary cells keep nominal matches and persistent payload aliases under pressure", async () => {
  await compileAndRun(
    `
type Token a is data = #Empty | #Full a
const read = func token => return case token of
  #Empty => 7
  #Full values => values[0]
entry const run = func (seed: U32) => return do:
  let original = #[#Empty, #Full #[seed, seed + 1], #Empty]
  let changed = @array.set original 1 #Empty
  for index in 0..200:
    let discarded = @array.fill 8192 index
    if discarded[8191] != index:
      @panic "pressure"
  break #[read original[1], read changed[1], read original[0], read changed[2]]
`,
    (_, bytes) => {
      const module = new WebAssembly.Module(bytes);
      assert.deepEqual([
        ...new Uint8Array(
          WebAssembly.Module.customSections(module, "blot:ownership")[0],
        ),
      ], [2, 2, 0]);
      const raw = new WebAssembly.Instance(module).exports;
      const memory = raw["blot:memory"] as WebAssembly.Memory;
      const enter = raw["blot:ownership_enter"] as CallableFunction;
      const leave = raw["blot:ownership_leave"] as CallableFunction;
      const count = (name: string) =>
        Number((raw[`blot:rc_${name}`] as WebAssembly.Global).value);
      let warmed = 0;
      for (const seed of [41, 8192, 65536, 41]) {
        enter();
        const before = count("destroyed");
        const pointer = (raw.run as CallableFunction)(seed);
        assert.deepEqual(
          new Uint32Array(memory.buffer, pointer + 4, 4),
          Uint32Array.of(seed, 7, 7, 7),
        );
        assert(
          count("destroyed") > before + 100,
          "the tracer packet cannot keep all discarded arrays alive",
        );
        if (warmed !== 0) assert.equal(memory.buffer.byteLength, warmed);
        warmed = memory.buffer.byteLength;
        leave(0);
        assert.equal(count("roots"), 0);
        assert.equal(count("leases"), 0);
      }
      leave(2);
    },
  );
});
