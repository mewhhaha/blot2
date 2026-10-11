import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const repo = new URL("../../", import.meta.url).pathname;
const prelude = `${repo}std/prelude.blot`;
const stdRoot = `${repo}std`;

// A constant with obligations records its principal region's dynamic inputs.
// That region drains independent summary jobs for a generic higher-order
// helper, including witness-callback jobs that publish no validated call.
// Their reads pass through the same recorder, so the principal keeps a
// complete input key. Only such keys are portable to the restart cache.
const probe = (schema: number) => `
const probe_with = fn pick => fn value => do:
  let (_, count) = run_scoped simulation (create ()) (fn () => do:
    use time <- get #Time
    let #Time { seconds } = time
    return pick ())
  return value + value + count
entry const probe_schema: U32 = ${schema}
entry const probe: U32 where { type_rep U32 } = probe_with (fn () => probe_schema) 3
`;
Deno.test("principal inputs survive summary jobs drained inside the recorded region", async () => {
  const ecs = await Deno.readTextFile(`${repo}examples/ecs.blot`);
  const directory = await Deno.makeTempDir({ prefix: "blot-summary-jobs-" });
  const entry = `${directory}/main.blot`;
  const options = {
    executable,
    entry,
    prelude,
    stdRoot,
    cacheDirectory: `${directory}/cache`,
  };
  const fresh = async (text: string) => {
    const compiler = await createZigProjectCompiler({
      ...options,
      cacheDirectory: false,
    });
    try {
      return await compiler.build({ sources: { [entry]: text } });
    } finally {
      await compiler.dispose();
    }
  };
  try {
    await Deno.writeTextFile(entry, ecs + probe(7));
    const first = await createZigProjectCompiler(options);
    try {
      const built = await first.build();
      assert(built.success, JSON.stringify(built));
      assert.equal(built.stats.restartCacheLoaded, false);
    } finally {
      await first.dispose();
    }
    const retained = await createZigProjectCompiler(options);
    try {
      const restored = await retained.build();
      assert(restored.success, JSON.stringify(restored));
      assert.equal(restored.stats.restartCacheLoaded, true);
      const principals = restored.stats.principals as Record<string, number>;
      assert(principals.persisted_hits > 0, JSON.stringify(principals));
      const reference = await fresh(ecs + probe(7));
      assert(reference.success);
      assert.deepEqual(restored.bytes, reference.bytes);
      // Literal edits, a failure and recovery keep fresh-identical output.
      for (
        const text of [
          ecs + probe(8),
          `${ecs}${probe(8)}\nconst broken_probe: U32 = #Wrong\n`,
          ecs + probe(9),
          ecs + probe(7),
        ]
      ) {
        const result = await retained.build({ sources: { [entry]: text } });
        const expected = await fresh(text);
        assert.equal(result.success, expected.success);
        if (!result.success && !expected.success) {
          assert.deepEqual(result.diagnostics, expected.diagnostics);
          continue;
        }
        assert(result.success && expected.success);
        assert.deepEqual(result.bytes, expected.bytes);
        assert.equal(
          result.stats.nativeWorkSteps,
          expected.stats.nativeWorkSteps,
        );
      }
    } finally {
      await retained.dispose();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
