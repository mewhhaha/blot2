import { compileAndRun, compileExpectedFailure, equal } from "./compile_helpers.ts";
import { monadLoopCases } from "./monad_loop_cases.ts";
const options = { prelude: new URL("../../std/prelude.blot", import.meta.url).pathname };
for (const item of monadLoopCases) {
  if (!("expected" in item)) continue;
  Deno.test(`native monad iteration preserves ${item.name}`, async () => {
    await compileAndRun(item.source, guest => {
      for (const [name, expected] of Object.entries(item.expected)) {
        equal(guest.abi.constants.some(value => value.name === name) ? guest.read(name) : guest.call(name, null), expected);
      }
    }, options);
  });
}
Deno.test("native monad loops require the selected source iterate member", async () => {
  for (const item of monadLoopCases) {
    if (!("error" in item)) continue;
    await compileExpectedFailure(item.source, item.error, undefined, options);
  }
});
