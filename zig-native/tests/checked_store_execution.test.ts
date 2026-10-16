import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const source = `
entry const integers = fn (seed: U32) => @array.from_list [@u32.add value seed | value <- #[1, 2, 3]]
entry const floating = fn (seed: F32) => @array.from_list [@f32.add seed 0.5 | value <- #[1, 2, 3]]
entry const zero_width = fn (count: U32) => @list.length [() | value <- @array.fill count 9]
entry const reference = fn (seed: U32) => do:
  let rows = #[@array.fill 256 seed, @array.fill 256 (@u32.add seed 1)]
  let kept = rows[1]
  rows[1] := @array.fill 256 99
  let pressure = @array.fill 8192 42
  return if @u32.eq pressure[0] 42 then kept else @panic "pressure changed"
`;
for (const codegenTier of ["optimized", "development"] as const) {
  Deno.test(`checked collection stores retain scalar widths zero-width rows and owning elements (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir();
    const entry = `${directory}/main.blot`;
    const compiler = await createZigProjectCompiler({
      executable,
      entry,
      prelude: null,
      codegenTier,
      cacheDirectory: false,
    });
    try {
      const first = await compiler.build({ sources: { [entry]: source } });
      assert(first.success, JSON.stringify(first));
      const retained = await compiler.build({ sources: { [entry]: source } });
      assert(retained.success, JSON.stringify(retained));
      assert.deepEqual(retained.bytes, first.bytes);
      const module = new WebAssembly.Module(first.bytes);
      assert.deepEqual([
        ...new Uint8Array(
          WebAssembly.Module.customSections(module, "blot:ownership")[0],
        ),
      ], [2, 2, 0]);
      const guest = await instantiateGuest(module);
      try {
        assert.deepEqual(
          guest.call("integers", 40),
          new Uint32Array([41, 42, 43]),
        );
        assert.deepEqual(
          guest.call("floating", 1.25),
          new Float32Array([1.75, 1.75, 1.75]),
        );
        for (const count of [0, 1, 3, 64, 241, 242, 513]) {
          assert.equal(guest.call("zero_width", count), count);
        }
        assert.deepEqual(
          guest.call("reference", 40),
          new Uint32Array(256).fill(41),
        );
        const warmBytes = guest.memoryBytes();
        for (let index = 0; index < 12; index++) {
          assert.deepEqual(
            guest.call("reference", index),
            new Uint32Array(256).fill(index + 1),
          );
          assert.equal(guest.call("zero_width", 513), 513);
        }
        assert.equal(guest.memoryBytes(), warmBytes);
      } finally {
        guest.dispose();
      }
      const raw = new WebAssembly.Instance(module).exports;
      assert.equal((raw.zero_width as (count: number) => number)(513), 513);
      assert.equal((raw["blot:rc_roots"] as WebAssembly.Global).value, 0);
      assert.equal((raw["blot:rc_leases"] as WebAssembly.Global).value, 0);
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
