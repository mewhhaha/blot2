import { GuestError } from "../../host/guest.ts";
import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

for (const name of ["parameter", "record", "capture"] as const) {
  Deno.test(`Foreign callback ${name} use composes with handled effects`, async () => {
    const source = await Deno.readTextFile(
      new URL(`../../compiler-goose/tests/fixtures/callback-fixtures/${name}.blot`, import.meta.url),
    );
    for (const asynchronous of [false, true]) {
      await compileAndRun(source, async (guest) => {
        let invoked = 0;
        const host = asynchronous
          ? guest.capabilityAsync({
            parameter: "Unit",
            result: "F32",
            call: async () => {
              await Promise.resolve();
              invoked++;
              return 41.5;
            },
          })
          : guest.capability({
            parameter: "Unit",
            result: "F32",
            call: () => {
              invoked++;
              return 41.5;
            },
          });
        for (let iteration = 0; iteration < 100; iteration++) {
          equal(
            asynchronous
              ? await guest.callAsync("answer", host)
              : guest.call("answer", host),
            42.5,
          );
        }
        equal(invoked, 100);
      }, { prelude: "none", asynchronous });
    }
  });
}

Deno.test("opening callback use rows preserves closed pure callback requirements", async () => {
  const entry = "#entry const answer = func (host:Unit -> F32 ! {Foreign}) => return ";
  for (
    const source of [
      "const invoke: (Unit -> F32) -> F32 = func callback=> return callback ()\n" +
      entry + "invoke host\n",
      "const invoke: (Unit -> F32) -> F32 = func callback=> return callback ()\nconst alias=invoke\n" +
      entry + "alias host\n",
      "type Invoke is data = $Invoke {run:(Unit -> F32) -> F32}\nconst invoke= $Invoke {run:func callback=> return callback ()}\n" +
      entry + "invoke.run host\n",
      "#entry const answer: (Unit -> F32 ! {Foreign}) -> (Unit -> F32) = func host=> return host\n",
      entry + "do:\n  let pure:Unit -> F32=host\n  break pure ()\n",
    ]
  ) {
    await compileExpectedFailure(source, "effect_mismatch", undefined, {
      prelude: "none",
    });
  }
});
