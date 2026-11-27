import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const fixture = (name: string) =>
  Deno.readTextFile(new URL(`../../compiler-goose/tests/fixtures/${name}`, import.meta.url));

function createCompiler(entry: string) {
  return createZigProjectCompiler({
    executable: Deno.args[0],
    entry,
    prelude: null,
    storage: {
      temporaryBytes: 16384,
      growerBytes: 16384,
      persistentBytes: 16384,
      transportBytes: 16384,
      ownerCapacity: 128,
    },
  });
}

for (
  const name of [
    "global_call_read.sq",
    "global_call_conditional.sq",
    "global_call_initialization.sq",
    "global_call_mutation.sq",
  ]
) {
  const test = Deno.test;
  test(`globals retain initialization aliases across calls: ${name}`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "squid-global-call-" });
    const entry = `${directory}/main.sq`;
    const compiler = await createCompiler(entry);
    try {
      {
        const built = await compiler.build({
          sources: { [entry]: await fixture(name) },
          signal: AbortSignal.timeout(5000),
        });
        assert(built.success, JSON.stringify(built));
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
            if (name === "global_call_read.sq") {
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
            } else if (name === "global_call_conditional.sq") {
              // The branch can be the first syntactic global reference while
              // the first executed reference occurs after that branch.
              for (const flag of [false, true, false, true]) {
                let expected = 10;
                if (flag) expected = 32;
                assert.equal(await call("answer", flag), expected);
              }
            } else if (name === "global_call_initialization.sq") {
              assert.deepEqual(
                await call("answer", 5),
                new Uint32Array([10, 101, 203, 319, 319]),
              );
              assert.equal(await call("advance", 7), 107);
            } else {
              assert.deepEqual(
                await call("mutate", 3),
                new Uint32Array([1, 2, 4, 9, 3]),
              );
              assert.equal(await call("observe", 0), 4);
              assert.equal(await call("count", null), 1);
              assert.equal(await call("mixed", false), 8);
              assert.equal(await call("mixed", true), 103);
              assert.equal(await call("inactive", false), 11);
              assert.equal(await call("inactive", true), 8);
            }
          } finally {
            guest.dispose();
          }
        }
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}

// Ownership is checked at compile time: mutating a module const global is
// rejected as aliased_update.
for (const name of ["global_call_freeze.sq"]) {
  Deno.test(`mutating a module const global is rejected at compile time: ${name}`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "squid-global-call-" });
    const entry = `${directory}/main.sq`;
    const compiler = await createCompiler(entry);
    try {
      const built = await compiler.build({
        sources: { [entry]: await fixture(name) },
        signal: AbortSignal.timeout(5000),
      });
      assert(!built.success, JSON.stringify(built));
      assert(
        built.diagnostics.some((d) => d.code === "aliased_update"),
        JSON.stringify(built),
      );
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
