import { compileAndRun, compileExpectedFailure } from "./compile_helpers.ts";
import {
  checkGuest,
  program,
  variant,
} from "./effectful_dictionary_closure_helpers.ts";

for (const helper of ["fn value => Render.show value", "Render.show"]) {
  for (const asynchronous of [false, true]) {
    Deno.test(`effectful ${helper} preserves the first application before returned closure calls (${asynchronous})`, async () => {
      await compileAndRun(variant(helper), async (guest) => {
        await checkGuest(guest, asynchronous);
      }, { prelude: "none", asynchronous });
    });
  }
}

Deno.test("effectful dictionary closure rows cannot be erased or moved into callback parameters", async () => {
  await compileExpectedFailure(
    program.replace("(U32 -> U32) ! {Read}", "(U32 -> U32) ! {}"),
    "effect_mismatch",
    undefined,
    { prelude: "none" },
  );
  await compileExpectedFailure(
    `effect Read: Unit -> U32
const consume: (Unit -> U32 ! {}) -> U32 = fn callback => callback ()
entry const answer: Unit -> U32 ! {Read} = fn unit => consume Read
`,
    "effect_mismatch",
    undefined,
    { prelude: "none" },
  );
});
