import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const fixture = (name: string) =>
  Deno.readTextFile(new URL(`../fixtures/${name}`, import.meta.url));
const template = await fixture("fresh_owner_return.blot.in");

function sourceFor(width: number) {
  const types: string[] = [];
  const fields: string[] = [];
  const first: string[] = [];
  const second: string[] = [];
  const reads: string[] = [];
  for (let index = 0; index < width; index++) {
    types.push(`f${index}: Array U32,`);
    fields.push(`f${index}: words,`);
    first.push(`f${index}: original,`);
    second.push(`f${index}: later,`);
    reads.push(
      `  first_total := @u32.add self first.f${index}[0]\n  second_total := @u32.add self second.f${index}[1]`,
    );
  }
  return template.replaceAll("__TYPES__", types.join(""))
    .replaceAll("__INPUT_TYPES__", types.join(""))
    .replaceAll("__NESTED_TYPES__", types.join(""))
    .replace("__FIELDS__", fields.join(""))
    .replace("__FIRST__", first.join(""))
    .replace("__SECOND__", second.join(""))
    .replace("__READS__", reads.join("\n"));
}

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`fresh fixed owner calls transfer aliases and reclaim storage (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-fresh-owner-" });
    const entry = `${directory}/main.blot`;
    const open = (temporaryBytes: number) =>
      createZigProjectCompiler({
        executable: Deno.args[0],
        entry,
        prelude: null,
        cacheDirectory: false,
        codegenTier,
        storage: {
          temporaryBytes,
          growerBytes: 256,
          persistentBytes: 256,
          transportBytes: 32768,
          ownerCapacity: 32,
        },
      });
    let compiler = await open(16384);
    try {
      for (const width of [8, 128]) {
        const built = await compiler.build({
          sources: { [entry]: sourceFor(width) },
          signal: AbortSignal.timeout(5000),
        });
        assert(built.success, JSON.stringify(built));
        const work = built.stats.workCounters as Record<string, number>;
        assert(work.scoped_completed_plan_definitions >= 2);
        assert(work.scoped_function_plan_hits > 0);
        assert(work.scoped_result_owner_transfer_definitions > 0);
        assert(work.scoped_transferred_result_owners > 0);
        assert.equal(work.scoped_completed_plan_rollbacks, 0);
        if (width === 8) {
          assert(work.scoped_owned_word_calls > 0);
          assert.equal(work.scoped_owned_packed_calls, 0);
        } else assert(work.scoped_owned_packed_calls > 0);
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(built.bytes, { asynchronous });
          try {
            assert.equal(guest.abi.version, 8);
            for (const input of [0, 7, 0xffff_ffff, 0]) {
              const expected = [
                input + 20,
                input + 20,
                input + 20,
                input + 1,
                input + 10,
                input + 41,
                input + 41,
                (input + 20) * width,
                (input + 41) * width,
              ];
              let actual: unknown;
              if (asynchronous) actual = await guest.callAsync("answer", input);
              else actual = guest.call("answer", input);
              assert.deepEqual(actual, new Uint32Array(expected));
            }
          } finally {
            guest.dispose();
          }
        }
      }
      const compacted = await compiler.build({
        sources: { [entry]: await fixture("fresh_owner_compacted_roles.blot") },
        signal: AbortSignal.timeout(5000),
      });
      assert(compacted.success, JSON.stringify(compacted));
      const compactedWork = compacted.stats.workCounters as Record<
        string,
        number
      >;
      assert(compactedWork.scoped_result_owner_transfer_definitions > 0);
      assert(compactedWork.scoped_transferred_result_owners >= 4);
      assert.equal(compactedWork.scoped_completed_plan_rollbacks, 0);
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(compacted.bytes, { asynchronous });
        try {
          assert.equal(guest.abi.version, 8);
          for (const input of [0, 7, 0xffff_ffff, 0]) {
            let actual: unknown;
            if (asynchronous) actual = await guest.callAsync("answer", input);
            else actual = guest.call("answer", input);
            assert.deepEqual(
              actual,
              new Uint32Array([
                input + 11,
                input + 2,
                input + 2,
                input + 114,
                input + 103,
                input + 103,
                input,
              ]),
            );
          }
        } finally {
          guest.dispose();
        }
      }
      await compiler.dispose();
      compiler = await open(1024);
      const cleanup = await compiler.build({
        sources: { [entry]: await fixture("fresh_owner_cleanup.blot") },
        signal: AbortSignal.timeout(5000),
      });
      assert(cleanup.success, JSON.stringify(cleanup));
      const work = cleanup.stats.workCounters as Record<string, number>;
      assert(work.scoped_function_plan_hits > 0);
      assert(work.scoped_result_owner_transfer_definitions > 0);
      assert(work.scoped_transferred_result_owners > 0);
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(cleanup.bytes, { asynchronous });
        try {
          assert.equal(guest.abi.version, 8);
          const call = async (name: string, input: number) => {
            if (asynchronous) return await guest.callAsync(name, input);
            return guest.call(name, input);
          };
          // Thousands of results cannot fit simultaneously in the 1 KiB lane.
          for (const count of [0, 1, 2, 17, 4096, 17]) {
            const half = Math.floor(count / 2);
            assert.deepEqual(
              await call("cleanup", count),
              new Uint32Array([half * (half + 1), count, 7]),
            );
          }
          await assert.rejects(
            () => call("bounds", 2),
            WebAssembly.RuntimeError,
          );
          assert.equal(await call("bounds", 1), 42);
          assert.deepEqual(
            await call("cleanup", 4096),
            new Uint32Array([4196352, 4096, 7]),
          );
        } finally {
          guest.dispose();
        }
      }
      for (
        const name of [
          "fresh_owner_borrow_escape.blot",
          "fresh_owner_stored_borrow_escape.blot",
        ]
      ) {
        const rejected = await compiler.build({
          sources: { [entry]: await fixture(name) },
          signal: AbortSignal.timeout(5000),
        });
        assert(!rejected.success, name);
        assert(
          rejected.diagnostics.some((item) => item.code === "storage_escape"),
          JSON.stringify(rejected),
        );
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
