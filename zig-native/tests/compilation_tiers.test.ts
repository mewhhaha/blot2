import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

Deno.test("compilation tiers and machine sharing preserve calls, captures, traps and retained edits", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-tiers-" });
  const entry = `${directory}/main.blot`;
  const executable = Deno.args[0] ??
    new URL("../zig-out/bin/blotc", import.meta.url);
  const source = (increment: number) => `
const left = fn (value: U32) => @u32.add (@u32.mul value 3) (@u32.div value 2)
const right = fn (value: U32) => @u32.add (@u32.mul value 3) (@u32.div value ${increment})
const make = fn (offset: U32) => fn (value: U32) => @u32.add offset (@u32.mul value 2)
entry const direct = fn value => @u32.add (left value) (right value)
entry const indirect = fn (value: U32) => do:
  let selected = if @u32.eq value 8 then left else right
  return selected value
entry const captured = fn value => (make 1) value
entry const other = fn value => (make 7) value
entry const trap = fn value => @u32.div 10 value
`;
  try {
    for (const codegenTier of ["optimized", "development"] as const) {
      for (const shareMachineCode of [false, true]) {
        const options = {
          executable,
          entry,
          prelude: null,
          codegenTier,
          shareMachineCode,
          codegenWorkers: 4,
        };
        const compiler = await createZigProjectCompiler(options);
        try {
          for (const divisor of [2, 4, 2]) {
            const sources = { [entry]: source(divisor) };
            const built = await compiler.build({ sources });
            assert(built.success, JSON.stringify(built));
            const optimization = built.stats.runtimeOptimization as Record<
              string,
              number | string
            >;
            assert.equal(optimization.tier, codegenTier);
            if (shareMachineCode && divisor === 2) {
              assert(
                Number(optimization.shared) > 0,
                JSON.stringify(optimization),
              );
            }
            const fresh = await createZigProjectCompiler({
              ...options,
              codegenWorkers: 1,
            });
            try {
              const rebuilt = await fresh.build({ sources });
              assert(rebuilt.success);
              assert.deepEqual(built.bytes, rebuilt.bytes);
            } finally {
              await fresh.dispose();
            }
            const guest = await instantiateGuest(built.bytes);
            try {
              assert.equal(guest.call("direct", 8), 52 + 8 / divisor);
              assert.equal(guest.call("indirect", 8), 28);
              assert.equal(guest.call("indirect", 12), 36 + 12 / divisor);
              assert.equal(guest.call("captured", 5), 11);
              assert.equal(guest.call("other", 5), 17);
              assert.throws(
                () => guest.call("trap", 0),
                WebAssembly.RuntimeError,
              );
            } finally {
              guest.dispose();
            }
          }
          const invalid = await compiler.build({
            sources: { [entry]: "entry const answer: U32 = #True\n" },
          });
          assert(!invalid.success);
          const corrected = await compiler.build({
            sources: { [entry]: source(2) },
          });
          assert(corrected.success);
        } finally {
          await compiler.dispose();
        }
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
