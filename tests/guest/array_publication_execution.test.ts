import { strict as assert } from "node:assert";
import { compileAndRun } from "./compile_helpers.ts";

Deno.test("dynamic Array copies preserve reference aliases and retire discarded snapshots", async () => {
  await compileAndRun(
    `
entry const run = func (count: U32) => return do:
  let item = #[41, 8192]
  let left = @array.fill count item
  let right = @array.fill count #[42, 65536]
  let joined = @array.concat left right
  let selected = @array.slice joined count count
  for index in 0..200:
    let discarded = @array.concat left right
    if discarded[count][0] != 42:
      @panic "copy"
  break #[left[0][1], joined[count][0], selected[0][1]]
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
      for (const size of [64, 64, 64]) {
        enter();
        const before = count("destroyed");
        const pointer = (raw.run as CallableFunction)(size);
        assert.deepEqual(
          new Uint32Array(memory.buffer, pointer + 4, 3),
          Uint32Array.of(8192, 42, 65536),
        );
        assert(
          count("destroyed") > before + 100,
          "retirement must occur during the entry",
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
