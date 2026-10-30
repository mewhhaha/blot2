import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
import { observeGuestAllocations } from "../../scripts/bench/guest_heap_observer.ts";

Deno.test("a direct scalar record reader can shed its short-lived caller allocation in the optimized tier", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-record-reader-" });
  const entry = `${directory}/main.blot`;
  const executable = Deno.args[0] ??
    new URL("../zig-out/bin/blotc", import.meta.url);
  const source = `
const score = func (fields: { a: U32, b: U32, c: U32, d: U32 }) => return
  @u32.add (@u32.mul fields.a fields.b) (@u32.mul fields.c fields.d)
const divide = func (fields: { numerator: U32, denominator: U32 }) => return
  @u32.div fields.numerator fields.denominator
entry const answer = func (input: U32) => return score { d: 4, c: 3, b: 2, a: input }
entry const snapshot = func (input: U32) => return do:
  let row = { a: input, b: 2, c: 3, d: 4 }
  let retained = row
  row.a := 0
  return score retained
entry const trap = func (input: U32) => return divide { denominator: input, numerator: 7 }
entry const order = func (host: U32 -> U32 ! {Foreign}) => return
  score { d: 4, c: 3, b: host 2, a: host 1 }
`;
  try {
    for (const codegenTier of ["development", "optimized"] as const) {
      const compiler = await createZigProjectCompiler({
        executable,
        entry,
        prelude: null,
        cacheDirectory: false,
        codegenTier,
      });
      try {
        const result = await compiler.build({ sources: { [entry]: source } });
        assert(result.success, JSON.stringify(result));
        const guest = await instantiateGuest(result.bytes);
        try {
          assert.equal(guest.call("answer", 5), 22);
          assert.equal(guest.call("snapshot", 5), 22);
          assert.equal(guest.call("trap", 1), 7);
          assert.throws(() => guest.call("trap", 0), WebAssembly.RuntimeError);
          const calls: number[] = [];
          const host = guest.capability({
            parameter: "U32",
            result: "U32",
            call: (value: number) => {
              calls.push(value);
              return value;
            },
          });
          assert.equal(guest.call("order", host), 14);
          assert.deepEqual(calls, [2, 1]);
        } finally {
          guest.dispose();
        }
        const traffic = observeGuestAllocations(result.bytes, [[
          "answer",
          5,
          22,
        ]]);
        assert.equal(
          traffic.rounded_allocation_bytes,
          codegenTier === "optimized" ? 0 : 4800,
        );
        assert.equal(traffic.retains, 0);
        assert.equal(traffic.releases, codegenTier === "optimized" ? 0 : 100);
      } finally {
        await compiler.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
