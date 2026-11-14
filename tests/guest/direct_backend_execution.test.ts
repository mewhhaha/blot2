// The direct backend (tasks/FAST_COMPILE.md) must run each fixture's entries
// to the same results as the scoped backend.
import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

type Call = [name: string, argument: number, expected: number];
const cases: Record<string, Call[]> = {
  "calls.blot": [["answer", 40, 42]],
  "data_and_control.blot": [
    ["shape_area", 0, 12],
    ["shape_area", 1, 12],
    ["shape_area", 2, 0],
    ["swapped", 3, 1003],
    ["record_field", 4, 5],
    ["maybe", 9, 18],
    ["maybe", 2, 7],
    ["generic", 3, 5.5],
    ["factorial", 5, 120],
    ["sum_to", 10, 38],
    ["first_big", 20, 8],
  ],
  "closures.blot": [
    ["offset_twice", 2, 6],
    ["partials", 1, 123],
    ["composed", 4, 15],
    ["counter", 10, 46],
    ["moved", 7, 1705],
    ["maybe_map", 21, 42],
    ["ctor_value", 5, 5],
  ],
};

for (const [fixture, calls] of Object.entries(cases)) {
  for (const backend of ["direct", "scoped"] as const) {
    Deno.test(`${fixture} entries run on the ${backend} backend`, async () => {
      const entry = new URL(`../../compiler/fixtures/direct/${fixture}`, import.meta.url).pathname;
      const compiler = await createZigProjectCompiler({
        executable: Deno.args[0],
        entry,
        prelude: new URL("../../std/prelude.blot", import.meta.url).pathname,
        stdRoot: new URL("../../std", import.meta.url).pathname,
        cacheDirectory: false,
        backend,
      });
      try {
        const built = await compiler.build({ signal: AbortSignal.timeout(20000) });
        if (!built.success) assert.fail(JSON.stringify(built));
        const guest = await instantiateGuest(built.bytes);
        for (const [name, argument, expected] of calls) {
          assert.equal(guest.call(name, argument), expected, `${name} ${argument}`);
        }
      } finally {
        await compiler.close();
      }
    });
  }
}
