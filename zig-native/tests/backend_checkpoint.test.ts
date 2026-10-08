import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

Deno.test("portable backend checkpoints survive process death and preserve source validation and revision recovery", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-checkpoint-" });
  const entry = `${directory}/main.blot`;
  const options = {
    executable: Deno.args[0] ??
      new URL("../zig-out/bin/blotc", import.meta.url),
    entry,
    prelude: null,
  };
  const source = (divisor: number) => `
type Box is data = #Box U32
const extract = fn (box: Box) -> U32 => case box of
  #Box value => value
entry const answer: U32 where { type_rep U32 } = @u32.div 8 (extract (#Box ${divisor}))
entry const runtime = fn (value: U32) => @u32.add value 2
`;
  try {
    const producer = await createZigProjectCompiler(options);
    let expected: Uint8Array<ArrayBuffer>;
    let checkpoint: Uint8Array<ArrayBuffer>;
    try {
      await assert.rejects(producer.exportCheckpoint(), /NoSuccessfulRevision/);
      const building = producer.build({ sources: { [entry]: source(2) } });
      const exporting = producer.exportCheckpoint();
      const built = await building;
      assert(built.success, JSON.stringify(built));
      expected = built.bytes;
      checkpoint = await exporting;
      assert(checkpoint.length > 0);
      const rejected = await producer.build({
        sources: { [entry]: source(0) },
      });
      assert(!rejected.success);
      assert.deepEqual(await producer.exportCheckpoint(), checkpoint);
      await Deno.writeFile(`${directory}/backend.blotcache`, checkpoint);
    } finally {
      await producer.dispose();
    }
    const onDisk = await Deno.readFile(`${directory}/backend.blotcache`);
    const starting = createZigProjectCompiler({
      ...options,
      checkpoint: onDisk,
    });
    onDisk.fill(0); // The client must already own the queued startup bytes.
    const restored = await starting;
    try {
      const built = await restored.build({ sources: { [entry]: source(2) } });
      assert(built.success, JSON.stringify(built));
      assert.deepEqual(built.bytes, expected!);
      const principal = built.stats.principals as Record<string, number>;
      assert(principal.persisted_hits > 0, JSON.stringify(principal));
      assert(principal.persisted_call_proofs > 0, JSON.stringify(principal));
      assert(
        (built.stats.runtimeOptimization as Record<string, number>).reused > 0,
      );
      const guest = await instantiateGuest(built.bytes);
      try {
        assert.equal(guest.read("answer"), 4);
        assert.equal(guest.call("runtime", 5), 7);
      } finally {
        guest.dispose();
      }
      for (const divisor of [4, 0, 2]) {
        const sources = { [entry]: source(divisor) };
        const result = await restored.build({ sources });
        const fresh = await createZigProjectCompiler(options);
        try {
          const rebuilt = await fresh.build({ sources });
          assert.equal(result.success, rebuilt.success);
          if (result.success && rebuilt.success) {
            assert.deepEqual(result.bytes, rebuilt.bytes);
            assert.equal(
              result.stats.nativeWorkSteps,
              rebuilt.stats.nativeWorkSteps,
            );
          } else if (!result.success && !rebuilt.success) {
            assert.deepEqual(result.diagnostics, rebuilt.diagnostics);
          }
        } finally {
          await fresh.dispose();
        }
      }
    } finally {
      await restored.dispose();
    }
    checkpoint![checkpoint!.length - 1] ^= 1;
    const corrupt = await createZigProjectCompiler({
      ...options,
      checkpoint: checkpoint!,
    });
    try {
      const built = await corrupt.build({ sources: { [entry]: source(2) } });
      assert(built.success);
      assert.deepEqual(built.bytes, expected!);
      assert.equal(
        (built.stats.principals as Record<string, number>).persisted_hits,
        0,
      );
    } finally {
      await corrupt.dispose();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
