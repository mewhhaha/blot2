import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const repo = new URL("../../", import.meta.url).pathname;
const prelude = `${repo}std/prelude.blot`;

// Calls are selected before their instructions: named calls, closures
// called through their table entry and typed by the callee (including a
// closure held by a constant), operator methods that return a closure, and
// resolver methods. Each executes as written, retained and fresh builds agree,
// an edit to one callee updates its callers, and fresh builds count every
// shape through preparation. Statically known accessor closures are exercised
// by typed_path_execution.test.ts.
const program = (offset: number) => `
type Vec is data = #Vec U32
const Vec.add = fn (left: Vec) => do:
  let #Vec x = left
  break fn (right: Vec) -> Vec => do:
    let #Vec y = right
    break #Vec (x + y + ${offset})
const adder = fn (x: U32) => do:
  break fn (y: U32) -> U32 => x + y + ${offset}
const twice = fn (f: U32 -> U32) => fn (x: U32) -> U32 => f (f x)
const shift = (fn (k: U32) => fn (y: U32) -> U32 => y + k) ${offset + 3}
const try = monad Maybe
const both = fn left => fn right => do try:
  use first <- left
  use second <- right
  break first + second
entry const named_over = fn (v: U32) -> U32 => adder v 2
entry const indirect = fn (v: U32) -> U32 => twice (fn (y: U32) => y + 3) v
entry const closure_constant = fn (v: U32) -> U32 => twice shift v
entry const operator = fn (v: U32) -> U32 => do:
  let #Vec total = #Vec v + #Vec 5
  break total
entry const resolver = fn (v: U32) -> U32 => Maybe.unwrap_or 0 (both (#Some v) (#Some 1))
entry const captured = fn (v: U32) -> U32 => do:
  let step = fn (y: U32) => y * 2
  let apply = fn (g: U32 -> U32) => g v
  break apply step + adder 1 1
`;
Deno.test("prepared calls of every shape execute and follow edits", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-resolved-calls-" });
  const entry = `${directory}/main.blot`;
  const options = {
    executable,
    entry,
    prelude,
    cacheDirectory: false as const,
  };
  const retained = await createZigProjectCompiler(options);
  try {
    for (const offset of [0, 10, 0]) {
      const sources = { [entry]: program(offset) };
      const result = await retained.build({ sources });
      const fresh = await createZigProjectCompiler(options);
      try {
        const expected = await fresh.build({ sources });
        assert(result.success && expected.success, JSON.stringify(result));
        assert.deepEqual(result.bytes, expected.bytes);
        const guest = await instantiateGuest(result.bytes);
        try {
          assert.equal(guest.call("named_over", 40), 42 + offset);
          assert.equal(guest.call("indirect", 10), 16);
          assert.equal(guest.call("operator", 37), 42 + offset);
          assert.equal(guest.call("resolver", 41), 42);
          assert.equal(guest.call("captured", 20), 42 + offset);
          assert.equal(guest.call("closure_constant", 30), 36 + 2 * offset);
        } finally {
          guest.dispose();
        }
        // Fresh builds select every call shape through preparation.
        const counters = expected.stats.workCounters as Record<string, number>;
        for (
          const kind of [
            "resolved_bodies",
            "resolved_plan_entries",
            "resolved_plan_reads",
            "prepared_named_calls",
            "prepared_dispatch_calls",
            "prepared_resolver_calls",
            "prepared_indirect_calls",
            "prepared_extra_applications",
          ]
        ) assert(counters[kind] > 0, `${kind}: ${JSON.stringify(counters)}`);
      } finally {
        await fresh.dispose();
      }
    }
  } finally {
    await retained.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
