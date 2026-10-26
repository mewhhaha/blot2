import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`copied nominal payloads and reference arrays preserve the whole-graph proof (${codegenTier})`, async () => {
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0],
      entry: new URL(
        "../../benchmarks/runtime-boundaries/acyclic-updates.blot",
        import.meta.url,
      ),
      prelude: new URL("../../std/prelude.blot", import.meta.url),
      cacheDirectory: false,
      codegenTier,
    });
    try {
      const built = await compiler.build();
      assert(built.success, JSON.stringify(built));
      const raw =
        new WebAssembly.Instance(new WebAssembly.Module(built.bytes)).exports;
      const memory = raw["blot:memory"] as WebAssembly.Memory;
      let expected = 0;
      const lanes = Array.from({ length: 256 }, (_, i) => i);
      for (let step = 0; step < 4096; step++) {
        expected += lanes[step % 256] + step;
        lanes[step % 256] = step;
      }
      for (let repeat = 0; repeat < 4; repeat++) {
        const before = memory.buffer.byteLength;
        assert.equal(
          (raw.update_snapshots as CallableFunction)(4096),
          expected,
        );
        if (repeat > 0) assert.equal(memory.buffer.byteLength, before);
        for (
          const name of [
            "cycle_passes",
            "cycle_vertices",
            "cycle_edges",
            "rc_roots",
            "rc_leases",
          ]
        ) {
          assert.equal(
            (raw[`blot:${name}`] as WebAssembly.Global).value,
            0,
            name,
          );
        }
      }
      assert(
        Number((raw["blot:rc_destroyed"] as WebAssembly.Global).value) > 4096,
      );
    } finally {
      await compiler.dispose();
    }
  });
}
