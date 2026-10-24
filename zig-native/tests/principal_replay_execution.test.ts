import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";

Deno.test("retained principal results omit deep optional call proofs and preserve edits errors recovery and execution", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-principal-depth-" });
  const entry = `${directory}/main.blot`;
  // Cross the retained proof importer's 128-level depth bound, while staying
  // within ordinary inference's 256-level bound. These are linear-size values.
  const layers = Array.from(
    { length: 130 },
    (_, i) => `  let layer_${i + 1} = wrap layer_${i}`,
  ).join("\n");
  const source = (value: number) =>
    `const wrap = fn value => (value, 0)
const ignore = fn value => 1
entry const answer: U32 where { type_rep U32 } = do:
  let seed = ${value}
  let layer_0 = wrap seed
${layers}
  break @u32.div 8 (@u32.mul seed (ignore layer_130))
`;
  try {
    await Deno.writeTextFile(entry, source(2));
    for (const codegenTier of ["optimized", "development"] as const) {
      const options = {
        executable: Deno.args[0] ??
          new URL("../zig-out/bin/blotc", import.meta.url).pathname,
        entry,
        prelude: null,
        codegenTier,
        codegenWorkers: 1,
        cacheDirectory: false as const,
      };
      const retained = await createZigProjectCompiler(options);
      try {
        for (const [revision, value] of [2, 4, 0, 2, 1].entries()) {
          const sources = { [entry]: source(value) };
          const built = await retained.build({ sources });
          const fresh = await createZigProjectCompiler(options);
          try {
            const expected = await fresh.build({ sources });
            if (value === 0) {
              assert(!built.success && !expected.success);
              assert.deepEqual(built.diagnostics, expected.diagnostics);
              assert.equal(built.diagnostics[0].code, "integer_divide_by_zero");
              continue;
            }
            assert(built.success, JSON.stringify(built));
            assert(expected.success, JSON.stringify(expected));
            assert.deepEqual(built.bytes, expected.bytes);
            const { instance } = await WebAssembly.instantiate(built.bytes);
            const answer = instance.exports.answer;
            assert.equal(
              typeof answer === "function"
                ? answer()
                : (answer as WebAssembly.Global).value,
              Math.floor(8 / value),
            );
            if (revision > 0) {
              const principals = built.stats.principals as Record<
                string,
                number
              >;
              assert.equal(principals.projected_empty_hits, 1);
              assert.equal(principals.fresh_regions, 0);
              assert(principals.call_publications_replayed > 0);
              assert.equal(principals.projected_import_declines, 0);
              if (revision === 1) {
                assert(principals.call_publications_declined > 0);
              } else {
                // The next capture owns only successfully translated proofs.
                assert.equal(principals.call_publications_declined, 0);
              }
            }
          } finally {
            await fresh.dispose();
          }
        }
      } finally {
        await retained.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
