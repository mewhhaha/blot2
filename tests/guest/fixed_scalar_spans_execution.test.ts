import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const source = await Deno.readTextFile(
  new URL("../../compiler/fixtures/fixed_scalar_spans.blot", import.meta.url),
);
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`fixed scalar spans preserve invocation lengths lazy reads lifetimes and nested carries (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-fixed-spans-" });
    const entry = `${directory}/main.blot`;
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0],
      entry,
      prelude: null,
      cacheDirectory: false,
      codegenTier,
    });
    try {
      const built = await compiler.build({
        sources: { [entry]: source },
        signal: AbortSignal.timeout(5_000),
      });
      assert(built.success, JSON.stringify(built));
      const work = built.stats.workCounters as Record<string, number>;
      assert(work.scoped_fixed_spans > 0);
      assert(work.scoped_fixed_span_accesses > 0);
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(built.bytes, { asynchronous });
        try {
          assert.equal(guest.abi.version, 8);
          const call = async (name: string, input: number | null) => {
            if (asynchronous) return await guest.callAsync(name, input);
            return guest.call(name, input);
          };
          for (const limit of [0, 1, 2, 3, 4, 9, 33, 2, 0, 17]) {
            let expected = 0;
            for (let turn = 0; turn < limit; turn++) {
              if (turn % 4 > 0) expected += turn;
            }
            assert.equal(await call("varying", limit), expected);
            assert.deepEqual(
              await call("fresh", limit),
              Uint32Array.of(expected, expected),
            );
            let value = 10;
            let total = 0;
            let replaced = 10;
            for (let step = 0; step < limit; step++) {
              if (step === 1) continue;
              value++;
              total += value;
              replaced += step;
              if (step === 3) break;
            }
            assert.deepEqual(
              await call("carried", limit),
              Uint32Array.of(total, value),
            );
            assert.equal(await call("replacement", limit), replaced);
          }
          for (const cutoff of [0, 127, 256, 512, 513]) {
            assert.deepEqual(
              await call("filtered", cutoff),
              Uint32Array.from(
                { length: Math.max(0, 512 - cutoff) },
                (_, index) => cutoff + index + 1,
              ),
            );
          }
          assert.equal(await call("event_count", null), 0);
          for (const index of [2, 0xffff_ffff]) {
            await assert.rejects(
              () => call("ordered", index),
              WebAssembly.RuntimeError,
            );
            assert.equal(await call("event_count", null), 0);
          }
          assert.equal(await call("ordered", 0), 42);
          assert.equal(await call("ordered", 1), 7);
          assert.equal(await call("event_count", null), 2);
          await assert.rejects(
            () => call("ordered", 2),
            WebAssembly.RuntimeError,
          );
          assert.equal(await call("event_count", null), 2);
        } finally {
          guest.dispose();
        }
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
