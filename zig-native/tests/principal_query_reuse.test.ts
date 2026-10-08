import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

Deno.test("principal query replay preserves staged values, errors, and proof ownership", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-principal-query-" });
  const entry = `${directory}/main.blot`;
  const options = {
    executable: Deno.args[0] ??
      new URL("../zig-out/bin/blotc", import.meta.url),
    entry,
    prelude: null,
  };
  const source = (divisor: number) =>
    `type Box is data = #Box U32
const extract = fn (box: Box) -> U32 => case box of
  #Box value => value
entry const answer: U32 where { type_rep U32 } = @u32.div 8 (extract (#Box ${divisor}))
`;
  const retained = await createZigProjectCompiler({
    ...options,
    profileBackend: true,
  });
  try {
    for (const [index, divisor] of [2, 4, 0, 2].entries()) {
      const sources = { [entry]: source(divisor) };
      const result = await retained.build({ sources });
      const fresh = await createZigProjectCompiler(options);
      try {
        const rebuilt = await fresh.build({ sources });
        assert.equal(result.success, rebuilt.success);
        if (divisor === 0) {
          assert(!result.success && !rebuilt.success);
          assert.deepEqual(result.diagnostics, rebuilt.diagnostics);
          continue;
        }
        assert(result.success && rebuilt.success, JSON.stringify(result));
        assert.deepEqual(result.bytes, rebuilt.bytes);
        assert.equal(
          result.stats.nativeWorkSteps,
          rebuilt.stats.nativeWorkSteps,
        );
        if (index > 0) {
          const principal = result.stats.principals as Record<string, number>;
          assert(principal.projected_empty_hits > 0, JSON.stringify(principal));
          assert(
            principal.call_publications_replayed > 0,
            JSON.stringify(principal),
          );
        }
        const timing = rebuilt.stats.backendTiming as {
          work: { inference_us: number };
        };
        assert.equal(timing.work.inference_us, 0);
        const guest = await instantiateGuest(result.bytes);
        try {
          assert.equal(guest.read("answer"), 8 / divisor);
        } finally {
          guest.dispose();
        }
      } finally {
        await fresh.dispose();
      }
    }
  } finally {
    await retained.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
