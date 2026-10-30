import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const calls = 51;
const rows = 20;
const fields = 100;
const record = "{" +
  Array.from({ length: fields }, (_, index) => `f${index}: input`).join(", ") +
  "}";
const source =
  `const relay = func (host: Array U32 -> Array U32 ! {Foreign}) -> (input: U32) => return do:
  let values = #[${Array.from({ length: rows }, () => record).join(",\n    ")}]
  use reply <- host #[values[0].f0, values[${rows - 1}].f${fields - 1}]
  return @u32.add reply[0] reply[1]
entry const answer = func (host: Array U32 -> Array U32 ! {Foreign}): U32 ! {Foreign} => return do:
  let marker: GrowArray U32 = #[0]
  let total: U32 = 0
${
    Array.from({ length: calls }, (_, index) =>
      `  use reply_${index} <- relay host ${index}\n  total := @u32.add total reply_${index}\n`)
      .join("")
  }  return @u32.add total marker[0]
`;
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`finite large owned emission retains ordered Foreign calls (${codegenTier})`, async () => {
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
              observed.push(values[0]);
              return new Uint32Array([values[0], values[1]]);
            },
          });
          const actual = asynchronous
            ? await guest.callAsync("answer", host)
            : guest.call("answer", host);
          assert.equal(actual, calls * (calls - 1));
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
