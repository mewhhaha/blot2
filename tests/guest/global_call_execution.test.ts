import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const fixture = (name: string) =>
  Deno.readTextFile(new URL(`../../compiler/fixtures/${name}`, import.meta.url));

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`global owner plans retain initialization aliases and cross-export mutation (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-global-call-" });
    const entry = `${directory}/main.blot`;
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0],
      entry,
      prelude: null,
      cacheDirectory: false,
      codegenTier,
      storage: {
        temporaryBytes: 16384,
        growerBytes: 16384,
        persistentBytes: 16384,
        transportBytes: 16384,
        ownerCapacity: 128,
      },
    });
    try {
      for (
        const name of [
          "global_call_read.blot",
          "global_call_conditional.blot",
          "global_call_mutation.blot",
          "global_call_initialization.blot",
        ]
      ) {
        const built = await compiler.build({
          sources: { [entry]: await fixture(name) },
          signal: AbortSignal.timeout(5000),
        });
        assert(built.success, JSON.stringify(built));
        const work = built.stats.workCounters as Record<string, number>;
        assert(work.scoped_global_plan_definitions > 0, JSON.stringify(work));
        assert(work.scoped_global_plan_loads > 0, JSON.stringify(work));
        if (name === "global_call_read.blot") {
          assert(work.scoped_global_plan_definitions <= 2);
          assert(work.scoped_function_plan_hits >= 8);
        } else if (name === "global_call_mutation.blot") {
          assert(work.scoped_function_plan_write_events > 0);
        }
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(built.bytes, { asynchronous });
          const call = async (
            exportName: string,
            input: number | boolean | null,
          ) => {
            if (asynchronous) return await guest.callAsync(exportName, input);
            return guest.call(exportName, input);
          };
          try {
            assert.equal(guest.abi.version, 8);
            if (name === "global_call_read.blot") {
              for (const index of [0, 1, 2, 1, 0]) {
                const expected = [5, 11, 17][index] + index;
                assert.equal(await call("twice", index), expected * 2);
                assert.deepEqual(
                  await call("eight", index),
                  new Uint32Array(8).fill(expected),
                );
              }
              await assert.rejects(
                () => call("twice", 3),
                WebAssembly.RuntimeError,
              );
              assert.equal(await call("twice", 0), 10);
            } else if (name === "global_call_conditional.blot") {
              // The branch can be the first syntactic global reference while
              // the first executed reference occurs after that branch.
              for (const flag of [false, true, false, true]) {
                let expected = 10;
                if (flag) expected = 32;
                assert.equal(await call("answer", flag), expected);
              }
            } else if (name === "global_call_mutation.blot") {
              let value = 4;
              let count = 1;
              assert.equal(await call("count", null), count);
              for (const input of [0, 2, 5, 0xffff_ffff, 0, 7]) {
                const compared = (value + input * 2 + 1) * 2;
                value = (value + input * 2 + 3) >>> 0;
                assert.deepEqual(
                  await call("mutate", input),
                  new Uint32Array([
                    count,
                    count + 1,
                    compared,
                    value,
                    value,
                    count + 1,
                  ]),
                );
                count++;
                assert.equal(await call("observe", 0), value);
                assert.equal(await call("observe", count - 1), input);
                assert.equal(await call("count", null), count);
              }
              // The same helper also sees an argument distinct from its global.
              value = (value + 1) >>> 0;
              assert.deepEqual(
                await call("separate", 41),
                new Uint32Array([43, value, value + 43, count]),
              );
              assert.equal(await call("observe", 0), value);
              for (const flag of [false, true, false]) {
                let mixed = value * 2;
                let variant = value + 7;
                if (flag) {
                  mixed = value + 99;
                  variant = value * 2;
                }
                assert.equal(await call("mixed", flag), mixed >>> 0);
                assert.equal(await call("inactive", flag), variant >>> 0);
                assert.equal(await call("observe", 0), value);
              }
            } else {
              // Initializers append 1 then 2 to the audit; helper publication
              // and repeated entry calls must not replay either operation.
              assert.deepEqual(
                await call("answer", 0),
                new Uint32Array([12, 1, 13, 26, 26]),
              );
              let audit = 12;
              for (const input of [3, 4, 0, 7]) {
                audit = (audit * 10 + input) >>> 0;
                assert.equal(await call("advance", input), audit);
                const expected = new Uint32Array([
                  audit,
                  1,
                  13,
                  audit + 19,
                  audit + 19,
                ]);
                assert.deepEqual(await call("answer", 5), expected);
                assert.deepEqual(await call("answer", 5), expected);
              }
            }
          } finally {
            guest.dispose();
          }
        }
      }
      for (
        const [name, code] of [
          ["global_call_freeze.blot", "storage_borrow_conflict"],
          ["global_call_borrow_escape.blot", "storage_escape"],
        ]
      ) {
        const rejected = await compiler.build({
          sources: { [entry]: await fixture(name) },
          signal: AbortSignal.timeout(5000),
        });
        assert(!rejected.success, name);
        assert(
          rejected.diagnostics.some((item) => item.code === code),
          JSON.stringify(rejected),
        );
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
