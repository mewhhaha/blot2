import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";

Deno.test(`copied nominal payloads and reference arrays show writes through the retained alias`, async () => {
  const compiler = await createZigProjectCompiler({
    executable: Deno.args[0],
    entry: new URL(
      "../../benchmarks/runtime-boundaries/acyclic-updates.blot",
      import.meta.url,
    ),
    prelude: new URL("../../std/prelude.blot", import.meta.url),
  });
  try {
    const built = await compiler.build();
    assert(built.success, JSON.stringify(built));
    const raw =
      new WebAssembly.Instance(new WebAssembly.Module(built.bytes)).exports;
    const memory = raw["blot:memory"] as WebAssembly.Memory;
    // `previous` aliases `world`, so it sees each write to the lane
    // (tasks/LANGUAGE_COHERENCE.md A7): every step adds `step` twice.
    let expected = 0;
    for (let step = 0; step < 4096; step++) expected += 2 * step;
    for (let repeat = 0; repeat < 4; repeat++) {
      const before = memory.buffer.byteLength;
      assert.equal(
        (raw.update_snapshots as CallableFunction)(4096),
        expected,
      );
      if (repeat > 0) assert.equal(memory.buffer.byteLength, before);
    }
  } finally {
    await compiler.dispose();
  }
});
