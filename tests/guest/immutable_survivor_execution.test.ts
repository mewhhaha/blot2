import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const source = await Deno.readTextFile(
  new URL("../../compiler/fixtures/immutable_survivor.blot", import.meta.url),
);
const addressed = source + "\n" + await Deno.readTextFile(
  new URL("../../compiler/fixtures/identity_join_address.blot", import.meta.url),
);
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`immutable survivors retain live values and fallback carriers (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-survivor-" });
    const entry = `${directory}/main.blot`;
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0],
      entry,
      prelude: null,
      cacheDirectory: false,
      codegenTier,
    });
    let checks = 0;
    try {
      for (
        const [text, names] of [[source, ["single", "rowed"]], [addressed, [
          "single",
          "rowed",
          "active_address",
        ]]] as const
      ) {
        const built = await compiler.build({
          sources: { [entry]: text },
          signal: AbortSignal.timeout(5_000),
        });
        assert(built.success, JSON.stringify(built));
        const work = built.stats.workCounters as Record<string, number>;
        if (text === addressed) {
          assert.equal(work.scoped_immutable_survivor_bindings, 0);
        } else assert(work.scoped_immutable_survivor_bindings > 0);
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(built.bytes, { asynchronous });
          try {
            for (const input of [0, 1, 6, 7, 0xffff_ffff, 0]) {
              let single = [input + 3, input, input + 7];
              if (input === 0) single = [99];
              let scalar = input + 20;
              let row = input + 2;
              if (input % 2 === 0) {
                scalar = input + 10;
                row = input + 1;
              }
              const expected: Record<string, number[]> = {
                single,
                rowed: [input],
                active_address: [input, scalar, input + 7, row],
              };
              for (const name of names) {
                let actual: unknown;
                if (asynchronous) actual = await guest.callAsync(name, input);
                else actual = guest.call(name, input);
                assert.deepEqual(
                  actual,
                  new Uint32Array(expected[name]),
                  JSON.stringify({ codegenTier, asynchronous, input, name }),
                );
                checks += 1;
              }
            }
          } finally {
            guest.dispose();
          }
        }
      }
      assert.equal(checks, 60);
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
