import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const calls = 101;
const source =
  `const relay = func (host: Array U32 -> Array U32 ! {Foreign}) -> (input: U32) => return do:
  let total = input
${
    "  total := @u32.add total 1\n".repeat(250)
  }  use reply <- host #[total, input]
  return reply[0]
entry const answer = func (host: Array U32 -> Array U32 ! {Foreign}): U32 ! {Foreign} => return do:
  let marker: GrowArray U32 = #[0]
  let total: U32 = 0
${
    Array.from({ length: calls }, (_, i) =>
      `  use reply_${i} <- relay host ${i}\n  total := @u32.add total reply_${i}\n`)
      .join("")
  }  return @u32.add total marker[0]
`;
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`scoped temporary locals execute large ordered Foreign bodies (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-emission-work-",
    });
    const entry = `${directory}/main.blot`;
    const stdRoot = new URL("../../std", import.meta.url).pathname;
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0],
      entry,
      stdRoot,
      prelude: `${stdRoot}/prelude.blot`,
      cacheDirectory: false,
      codegenTier,
      inferenceBudget: 20000000,
    });
    try {
      const result = await compiler.build({ sources: { [entry]: source } });
      assert(result.success, JSON.stringify(result));
      const counters = result.stats.workCounters as Record<
        string,
        number
      >;
      assert(
        counters.max_scoped_emission_body_steps > 100000,
        JSON.stringify(counters),
      );
      assert(counters.max_scoped_emission_body_steps <= 500000);

      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(result.bytes, { asynchronous });
        try {
          const observed: number[] = [];
          const host = guest.capability({
            parameter: "Array U32",
            result: "Array U32",
            call: (values) => {
              assert(values instanceof Uint32Array);
              observed.push(values[1]);
              return new Uint32Array([values[0], values[1]]);
            },
          });
          const actual = asynchronous
            ? await guest.callAsync("answer", host)
            : guest.call("answer", host);
          assert.equal(actual, calls * 250 + calls * (calls - 1) / 2);
          assert.deepEqual(
            observed,
            Array.from({ length: calls }, (_, index) => index),
          );
        } finally {
          guest.dispose();
        }
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
