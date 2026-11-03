import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const template = await Deno.readTextFile(
  new URL("../fixtures/packed_input.blot.in", import.meta.url),
);
const fields = Array.from(
  { length: 600 },
  (_, index) => `f${index}: @u32.add input ${index},`,
).join("");
const source = template.replace("__FIELDS__", fields);
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`packed input demand forwards fields and preserves effects (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-packed-input-" });
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
        signal: AbortSignal.timeout(10_000),
      });
      assert(built.success, JSON.stringify(built));
      const work = built.stats.workCounters as Record<string, number>;
      assert(work.scoped_owned_packed_calls > 0);
      assert(work.scoped_packed_input_words_avoided > 0);
      assert(work.scoped_packed_argument_words_avoided > 0);
      assert(work.scoped_function_plan_hits > 0);
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(built.bytes, { asynchronous });
        try {
          for (const input of [0, 1, 6, 7, 0xffff_fffe, 0xffff_ffff, 0]) {
            let selected = input;
            if (input % 2 !== 0) selected += 599;
            let variant = input;
            if (input % 2 !== 0) variant = input + input + 9;
            const expected = new Uint32Array([
              selected + input + 3 + input + 1,
              input + input + 3 + input + 1,
              1,
              input + 3,
              input + 3,
              variant,
            ]);
            let actual: unknown;
            if (asynchronous) actual = await guest.callAsync("answer", input);
            else actual = guest.call("answer", input);
            assert.deepEqual(actual, expected);
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
