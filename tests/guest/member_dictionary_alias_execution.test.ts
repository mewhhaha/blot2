import {
  compileAndRun,
  equal,
} from "./compile_helpers.ts";

Deno.test("operation aliases remain values and execute only when invoked", async () => {
  await compileAndRun(
    `effect Read: Unit -> U32
const alias = Read
io const answer = func (host: Unit -> U32 ! {Foreign}) => return do:
  let provider = @effect.provider Read host
  break do provider:
    break @u32.add (alias ()) (alias ())
`,
    (guest) => {
      let calls = 0;
      equal(
        guest.call(
          "answer",
          guest.capability({
            parameter: "Unit",
            result: "U32",
            call: () => ++calls,
          }),
        ),
        3,
      );
      equal(calls, 2);
    },
    { prelude: "none" },
  );
});
