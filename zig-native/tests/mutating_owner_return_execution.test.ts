import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const fixture = (name: string) =>
  Deno.readTextFile(new URL(`../fixtures/${name}`, import.meta.url));
const template = await fixture("mutating_owner_return.blot.in");
const nestedTemplate = await fixture("mutating_owner_return_nested.blot.in");

function sourceFor(width: number, source = template) {
  const types: string[] = [];
  const distinct: string[] = [];
  const shared: string[] = [];
  const reads: string[] = [];
  for (let index = 0; index < width; index++) {
    types.push(`f${index}: Array U32,`);
    let owner = "first";
    if (index % 2 !== 0) owner = "second";
    distinct.push(`f${index}: ${owner},`);
    shared.push(`f${index}: second,`);
    reads.push(`current.f${index}[0],`);
  }
  return source.replace("__TYPES__", types.join(""))
    .replace("__DISTINCT__", distinct.join(""))
    .replace("__SHARED__", shared.join(""))
    .replace("__READS__", reads.join(""));
}

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`mutating owner results retain caller roots and lifetime checks (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-mutating-owner-",
    });
    const entry = `${directory}/main.blot`;
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0],
      entry,
      prelude: null,
      cacheDirectory: false,
      codegenTier,
    });
    try {
      for (const width of [8, 128]) {
        const built = await compiler.build({
          sources: { [entry]: sourceFor(width) },
          signal: AbortSignal.timeout(5000),
        });
        assert(built.success, JSON.stringify(built));
        const work = built.stats.workCounters as Record<string, number>;
        // Returned logical lanes can have a different exact-word partition.
        assert(work.scoped_function_plan_definitions > 0);
        assert(work.scoped_function_plan_write_events > 0);
        assert.equal(
          work.scoped_completed_plan_rollbacks,
          work.scoped_addressed_retries,
        );
        if (width === 8) {
          assert(work.scoped_owned_word_calls > 0);
          assert.equal(work.scoped_owned_packed_calls, 0);
        } else {
          assert(work.scoped_packed_plans_promoted > 0);
          assert(work.scoped_owned_word_calls > 0);
        }
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(built.bytes, { asynchronous });
          try {
            for (const input of [0, 1, 6, 7, 0xffff_fffe, 0xffff_ffff, 0]) {
              let first = input + 2;
              let second = input + 11;
              let selected = first;
              if (input % 2 === 0) {
                first += 4;
                selected = first;
              } else {
                second += 4;
                selected = second;
              }
              const expected = [first, second, first, second, selected];
              for (let index = 0; index < width; index++) {
                let value = second;
                if (input % 2 === 0 && index % 2 === 0) value = first;
                expected.push(value);
              }
              let actual: unknown;
              if (asynchronous) actual = await guest.callAsync("answer", input);
              else actual = guest.call("answer", input);
              assert.deepEqual(actual, new Uint32Array(expected));
            }
          } finally {
            guest.dispose();
          }
        }
        const nested = await compiler.build({
          sources: { [entry]: sourceFor(width, nestedTemplate) },
          signal: AbortSignal.timeout(5000),
        });
        assert(nested.success, JSON.stringify(nested));
        const nestedWork = nested.stats.workCounters as Record<string, number>;
        assert(nestedWork.scoped_function_plan_hits > 0);
        assert(nestedWork.scoped_function_plan_write_events > 0);
        assert.equal(
          nestedWork.scoped_completed_plan_rollbacks,
          nestedWork.scoped_addressed_retries,
        );
        assert(nestedWork.scoped_result_store_words_avoided >= width * 4);
        assert(nestedWork.scoped_result_load_words_avoided >= width * 4);
        if (width === 8) {
          assert(nestedWork.scoped_owned_word_calls > 0);
          assert.equal(nestedWork.scoped_owned_packed_calls, 0);
        } else {
          assert(nestedWork.scoped_packed_plans_promoted > 0);
          assert(nestedWork.scoped_owned_word_calls > 0);
        }
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(nested.bytes, { asynchronous });
          try {
            for (const input of [0, 7, 0xffff_ffff, 0]) {
              const expected = [input + 11, input + 10, input + 11];
              for (let index = 0; index < width; index++) {
                let value = input + 11;
                if (index % 2 !== 0) value = input + 10;
                expected.push(value);
              }
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
      const fresh = await compiler.build({
        sources: { [entry]: await fixture("mutating_owner_return_fresh.blot") },
        signal: AbortSignal.timeout(5000),
      });
      assert(fresh.success, JSON.stringify(fresh));
      const work = fresh.stats.workCounters as Record<string, number>;
      assert(work.scoped_completed_plan_definitions > 0);
      assert(work.scoped_function_plan_hits > 0);
      assert.equal(
        work.scoped_completed_plan_rollbacks,
        work.scoped_addressed_retries,
      );
      const guest = await instantiateGuest(fresh.bytes);
      try {
        for (const input of [0, 7, 0xffff_ffff, 0]) {
          assert.deepEqual(
            guest.call("answer", input),
            new Uint32Array([input + 2, input + 1, input + 2]),
          );
        }
      } finally {
        guest.dispose();
      }
      for (
        const [name, code] of [
          ["mutating_owner_return_lifetime.blot", "storage_escape"],
          ["mutating_owner_return_event_escape.blot", "storage_escape"],
          ["mutating_owner_return_truncate.blot", "storage_borrow_conflict"],
        ]
      ) {
        const rejected = await compiler.build({
          sources: { [entry]: await fixture(name) },
          signal: AbortSignal.timeout(5000),
        });
        assert(!rejected.success, name);
        assert(
          rejected.diagnostics.some((diagnostic) => diagnostic.code === code),
          JSON.stringify(rejected),
        );
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
