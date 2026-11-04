import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const ordinary = await Deno.readTextFile(
  new URL("../../compiler/fixtures/identity_join.blot", import.meta.url),
);
const addressed = await Deno.readTextFile(
  new URL("../../compiler/fixtures/identity_join_address.blot", import.meta.url),
);

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`identity joins preserve callback captures and heap aliases (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-identity-join-" });
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
        const [source, names] of [[ordinary, [
          "joined",
          "changed_capture",
          "changed_reader",
        ]], [addressed, ["active_address"]]] as const
      ) {
        const built = await compiler.build({
          sources: { [entry]: source },
          signal: AbortSignal.timeout(5_000),
        });
        assert(built.success, JSON.stringify(built));
        const work = built.stats.workCounters as Record<string, number>;
        if (source === addressed) {
          assert.equal(work.scoped_transport_words_avoided, 0);
        } else assert(work.scoped_transport_words_avoided > 0);
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(built.bytes, { asynchronous });
          try {
            for (const input of [0, 1, 6, 7, 0xffff_ffff, 0]) {
              let delta = 20;
              let second = 5;
              let capture = input + 8;
              let changedRow = input + 2;
              let changedReader = [input + 3, input + 3];
              let activeRow = input + 2;
              if (input % 2 === 0) {
                delta = 10;
                second = 4;
                capture = input + 107;
                changedRow = input;
                changedReader = [input + 100, input];
                activeRow = input + 1;
              }
              if (input < 5) second = 6;
              const changed = input + delta;
              const expected: Record<string, number[]> = {
                joined: [
                  input,
                  changed,
                  changed,
                  changed,
                  second,
                  input + 7,
                  changed + 9,
                  17,
                ],
                changed_capture: [capture, input + 8, changedRow],
                changed_reader: changedReader,
                active_address: [input, changed, input + 7, activeRow],
              };
              for (const name of names) {
                let actual: unknown;
                if (asynchronous) actual = await guest.callAsync(name, input);
                else actual = guest.call(name, input);
                assert.deepEqual(
                  actual,
                  new Uint32Array(expected[name]),
                  JSON.stringify({ name, input, asynchronous, codegenTier }),
                );
                checks += 1;
              }
            }
          } finally {
            guest.dispose();
          }
        }
      }
      assert.equal(checks, 48);
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
