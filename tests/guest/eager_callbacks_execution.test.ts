import { strict as assert } from "node:assert";
import { compileAndRun } from "./compile_helpers.ts";

for (const owned of [false, true]) {
  for (const asynchronous of [false, true]) {
    Deno.test(`primitive Boolean operators and explicit fallback callbacks preserve effects (${owned}, ${asynchronous})`, async () => {
      let storage = "";
      if (owned) storage = "  let marker = #[0]\n  marker[0] := 1\n";
      await compileAndRun(
        `entry const answer = func (host: U32 -> U32 ! {Foreign}) => return do:
${storage}  use skipped_and <- false and (host 100 == 100)
  use skipped_or <- true or (host 200 == 200)
  use selected_and <- true and (host 3 == 3)
  use selected_or <- false or (host 4 == 4)
  use present <- Maybe.unwrap_or_else (func () => return host 1) ($Some 40)
  let success_value: Result [U32, Unit] = $Ok 2
  use success <- Result.unwrap_or_else (func () => return host 2) success_value
  use absent <- Maybe.unwrap_or_else (func () => return host 5) $Nothing
  use failure <- Result.unwrap_or_else (func () => return host 6) ($Err ())
  break present + success + absent + failure
`,
        async (guest) => {
          const calls: number[] = [];
          const host = guest.capability({
            parameter: "U32",
            result: "U32",
            call(value) {
              calls.push(value);
              return value;
            },
          });
          let answer: unknown;
          if (asynchronous) answer = await guest.callAsync("answer", host);
          else answer = guest.call("answer", host);
          assert.equal(answer, 53);
          assert.deepEqual(calls, [3, 4, 5, 6]);
        },
        { asynchronous },
      );
    });
  }
}

Deno.test("ordinary callbacks repeat work and explicit local values share results", async () => {
  await compileAndRun(
    `const repeat = func callback => return do:
  use first <- callback ()
  use second <- callback ()
  break first + second
const share = func callback => return do:
  use value <- callback ()
  break value + value
entry const repeated = func (host: Unit -> U32 ! {Foreign}) => return repeat host
entry const shared = func (host: Unit -> U32 ! {Foreign}) => return share host
`,
    (guest) => {
      let calls = 0;
      const host = guest.capability({
        parameter: "Unit",
        result: "U32",
        call: () => ++calls,
      });
      assert.equal(guest.call("repeated", host), 3);
      assert.equal(calls, 2);
      assert.equal(guest.call("shared", host), 6);
      assert.equal(calls, 3);
    },
  );
});
