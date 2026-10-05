import { GuestError } from "../../compiler/guest.ts";
import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

for (const name of ["parameter", "record", "capture"] as const) {
  Deno.test(`Foreign callback ${name} use composes with handled effects`, async () => {
    const source = await Deno.readTextFile(
      new URL(`../src/callback-fixtures/${name}.blot`, import.meta.url),
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

Deno.test("mixed Foreign Requests factories preserve captures cancellation and callback recovery", async () => {
  const source = await Deno.readTextFile(
    new URL("../src/callback-fixtures/factory.blot", import.meta.url),
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
        equal(
          asynchronous
            ? await guest.callAsync("cancel", host)
            : guest.call("cancel", host),
          86,
        );
      }
      equal(invoked, 200);
      const cause = new Error("callback failed");
      const bad = asynchronous
        ? guest.capabilityAsync({
          parameter: "Unit",
          result: "F32",
          call: async () => {
            await Promise.resolve();
            throw cause;
          },
        })
        : guest.capability({
          parameter: "Unit",
          result: "F32",
          call: () => {
            throw cause;
          },
        });
      for (let iteration = 0; iteration < 20; iteration++) {
        let caught = false;
        try {
          if (asynchronous) await guest.callAsync("answer", bad);
          else guest.call("answer", bad);
        } catch (error) {
          if (
            !(error instanceof GuestError) || error.code !== "host_exception" ||
            error.cause !== cause
          ) throw error;
          caught = true;
        }
        equal(caught, true);
        equal(
          asynchronous
            ? await guest.callAsync("answer", host)
            : guest.call("answer", host),
          42.5,
        );
      }
    }, { prelude: "none", asynchronous });
  }
});

Deno.test("opening callback use rows preserves closed pure callback requirements", async () => {
  const entry = "entry const answer = fn (host:Unit -> F32 ! {Foreign}) => ";
  for (
    const source of [
      "const invoke: (Unit -> F32) -> F32 = fn callback=>callback ()\n" +
      entry + "invoke host\n",
      "const invoke: (Unit -> F32) -> F32 = fn callback=>callback ()\nconst alias=invoke\n" +
      entry + "alias host\n",
      "type Invoke is data = #Invoke {run:(Unit -> F32) -> F32}\nconst invoke=#Invoke {run:fn callback=>callback ()}\n" +
      entry + "invoke.run host\n",
      "entry const answer: (Unit -> F32 ! {Foreign}) -> (Unit -> F32) = fn host=>host\n",
      entry + "do:\n  let pure:Unit -> F32=host\n  return pure ()\n",
    ]
  ) {
    await compileExpectedFailure(source, "effect_mismatch", undefined, {
      prelude: "none",
    });
  }
});
