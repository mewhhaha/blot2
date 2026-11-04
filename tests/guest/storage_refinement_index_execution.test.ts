import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const fields = 72;
const source = `const read = func row => return {${
  Array.from({ length: fields }, (_, index) => `f${index}: row.f${index}`).join(
    ", ",
  )
}}
entry const answer = func (input: U32) => return do:
  let values: Array U32 = #[input]
  values[0] := input
  let selected = read {${
  Array.from({ length: fields }, (_, index) =>
    `f${index}: @u32.add values[0] ${index}`).join(", ")
}}
  let total: U32 = 0
${
  Array.from({ length: fields }, (_, index) =>
    `  total := @u32.add total selected.f${index}\n`).join("")
}  return total
`;
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`wide fields use scoped indexes or forward complete result words (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-refinement-index-",
    });
    const entry = `${directory}/main.blot`;
    const stdRoot = new URL("../../std", import.meta.url).pathname;
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0],
      entry,
      stdRoot,
      prelude: `${stdRoot}/prelude.blot`,
      cacheDirectory: false,
      codegenTier,
    });
    try {
      const result = await compiler.build({ sources: { [entry]: source } });
      assert(result.success, JSON.stringify(result));
      const counters = result.stats.workCounters as Record<string, number>;
      // A completed identity result may forward every field without needing
      // to materialize the old refinement environment at all.
      const forwarded = counters.scoped_function_plan_definitions > 0 &&
        counters.scoped_result_store_words_avoided >= fields &&
        counters.scoped_result_load_words_avoided >= fields;
      assert(
        counters.scoped_refinement_indexed_bindings > 0 || forwarded,
        JSON.stringify(counters),
      );
      assert.equal(counters.scoped_refinement_index_declines, 0);
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(result.bytes, { asynchronous });
        try {
          for (const input of [0, 1, 12345, 0xffffffff]) {
            const actual = asynchronous
              ? await guest.callAsync("answer", input)
              : guest.call("answer", input);
            assert.equal(
              actual,
              (fields * input + fields * (fields - 1) / 2) >>> 0,
            );
          }
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
