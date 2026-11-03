import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const source = await Deno.readTextFile(
  new URL("../fixtures/deferred_join.blot", import.meta.url),
);
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`deferred joins preserve control exits loop swaps and variants (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-deferred-join-" });
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
      assert(work.scoped_join_words_shared > 0, JSON.stringify(work));
      let checks = 0;
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(built.bytes, { asynchronous });
        try {
          for (const input of [0, 1, 2, 3, 17, 0xffff_fffe]) {
            const wide = Array.from({ length: 8 }, (_, index) => input + index);
            if (input > 1) wide[3] = input + 30;
            let conditional = input + 3;
            if (input % 2 !== 0) conditional = input + 40;
            let matched = input + 3;
            if (input % 3 === 2) matched = input + 50;
            let variant = input;
            if (input === 0) variant = 99;
            let changedVariant = 99;
            if (input % 2 === 0) changedVariant = input + 9;
            const expected: Record<string, number[]> = {
              three_exits: wide,
              conditional: [input, conditional, input + 7],
              matched: [input, matched, input + 7],
              single_edge: [input + 1, input + 61],
              loop_swap: [input + 100, input, input + 100, input],
              variants: [variant, input, input + 7, changedVariant],
            };
            for (const [name, words] of Object.entries(expected)) {
              let actual: unknown;
              if (asynchronous) actual = await guest.callAsync(name, input);
              else actual = guest.call(name, input);
              assert.deepEqual(
                actual,
                new Uint32Array(words),
                JSON.stringify({ codegenTier, asynchronous, name, input }),
              );
              checks += 1;
            }
          }
        } finally {
          guest.dispose();
        }
      }
      assert.equal(checks, 72);
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
