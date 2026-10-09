import { strict as assert } from "node:assert";
import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

function cancellationSource(exit: "return" | "break", nested: boolean): string {
  return `
type Tick is effect = { read: U32 -> U32 }
const delay = fn ~value => value
const abort = fn log => fn computation => do:
  for request in @requests computation:
    case request of
      effect Tick.read value =>
        use log 1
        ${exit === "return" ? "return 7" : "break"}
      complete value =>
        return value
  return 7
const finish = fn log => fn computation => do:
  for request in @requests computation:
    case request of
      effect Tick.read value =>
        use log 2
        yield @u32.add value 40
      complete value =>
        return value
const scenario = fn log => do:
  let inner = delay (Tick.read 1)
  let pending = delay (do:
    use value <- ${nested ? "@demand inner" : "Tick.read 1"}
    return @u32.add value 1
  )
  let work = @computation (fn () => @demand pending)
  use first <- abort log work
  use second <- finish log work
  use third <- finish log work
  return @u32.add first (@u32.add second third)
entry const answer = fn (log: U32 -> U32 ! {Foreign}) => do:
  use result <- scenario log
  return result
entry const folded = scenario (fn value => value)
`;
}

const trappedSource = `
type Tick is effect = { read: Unit -> U32 }
const keep = fn ~value => fn () => @demand value
const saved = keep (Tick.read ())
const divided = keep (@u32.div 1 (Tick.read ()))
entry const answer = fn (host: Unit -> U32 ! {Foreign}) => do (@effect.provider Tick.read host):
  return saved ()
entry const divide = fn (host: Unit -> U32 ! {Foreign}) => do (@effect.provider Tick.read host):
  return divided ()
entry const pure = fn () => 7
`;

const recursiveSource = `
type State a is effect = { get: Unit -> a, set: a -> Unit }
type Node is data = #End | #Next (Unit -> U32 ! {State.get Node})
const keep = fn ~value => fn () => @demand value
const get = fn (witness: Unit -> a) -> a => State.get ()
entry const answer = fn () => do:
  let (_, result) = @effect.run State.get State.set #End (fn () => do:
    let delayed = keep (do:
      use link <- get (fn () => #End)
      return case link of
        #End => 0
        #Next callback => callback ()
    )
    use State.set (#Next delayed)
    return delayed ()
  )
  return result
entry const pure = fn () => 7
`;

for (const asynchronous of [false, true]) {
  const mode = asynchronous ? "JSPI" : "sync";
  Deno.test(`cancelled demands retry without caching a partial result (${mode})`, async () => {
    for (const exit of ["return", "break"] as const) {
      for (const nested of [false, true]) {
        await compileAndRun(cancellationSource(exit, nested), async (guest) => {
          const events: number[] = [];
          const log = asynchronous
            ? guest.capabilityAsync({
              parameter: "U32",
              result: "U32",
              call: async (value) => {
                await Promise.resolve();
                events.push(value);
                return value;
              },
            })
            : guest.capability({
              parameter: "U32",
              result: "U32",
              call: (value) => {
                events.push(value);
                return value;
              },
            });
          for (let repetition = 0; repetition < 3; repetition++) {
            equal(
              asynchronous
                ? await guest.callAsync("answer", log)
                : guest.call("answer", log),
              91,
            );
          }
          // Cancellation does not roll back effects already performed. A
          // successful retry caches once for both aliases of the computation.
          assert.deepEqual(events, [1, 2, 1, 2, 1, 2]);
          equal(guest.read("folded"), 91);
        }, { asynchronous });
      }
    }
  });

  Deno.test(`failed persistent demands remain terminal after host or Wasm traps (${mode})`, async () => {
    await compileAndRun(trappedSource, async (guest) => {
      let calls = 0;
      const good = asynchronous
        ? guest.capabilityAsync({
          parameter: "Unit",
          result: "U32",
          call: async () => {
            await Promise.resolve();
            calls++;
            return 42;
          },
        })
        : guest.capability({
          parameter: "Unit",
          result: "U32",
          call: () => {
            calls++;
            return 42;
          },
        });
      const fault = asynchronous
        ? guest.capabilityAsync({
          parameter: "Unit",
          result: "U32",
          call: async () => {
            await Promise.resolve();
            calls++;
            throw new Error("demand callback failed");
          },
        })
        : guest.capability({
          parameter: "Unit",
          result: "U32",
          call: () => {
            calls++;
            throw new Error("demand callback failed");
          },
        });
      const zero = asynchronous
        ? guest.capabilityAsync({
          parameter: "Unit",
          result: "U32",
          call: async () => {
            await Promise.resolve();
            calls++;
            return 0;
          },
        })
        : guest.capability({
          parameter: "Unit",
          result: "U32",
          call: () => {
            calls++;
            return 0;
          },
        });
      if (asynchronous) {
        await assert.rejects(() => guest.callAsync("answer", fault));
        await assert.rejects(() => guest.callAsync("answer", good));
        await assert.rejects(() => guest.callAsync("divide", zero));
        await assert.rejects(() => guest.callAsync("divide", good));
      } else {
        assert.throws(() => guest.call("answer", fault));
        assert.throws(() => guest.call("answer", good));
        assert.throws(() => guest.call("divide", zero));
        assert.throws(() => guest.call("divide", good));
      }
      equal(calls, 2);
      equal(
        asynchronous
          ? await guest.callAsync("pure", null)
          : guest.call("pure", null),
        7,
      );
    }, { asynchronous });
  });

  Deno.test(`reentrant demand through State fails without poisoning another entry (${mode})`, async () => {
    await compileAndRun(recursiveSource, async (guest) => {
      for (let repetition = 0; repetition < 3; repetition++) {
        if (asynchronous) {
          await assert.rejects(() => guest.callAsync("answer", null));
          equal(await guest.callAsync("pure", null), 7);
        } else {
          assert.throws(() => guest.call("answer", null));
          equal(guest.call("pure", null), 7);
        }
      }
    }, { asynchronous });
  });
}

Deno.test("compile-time reentrant forcing reports a constant-expression failure", async () => {
  await compileExpectedFailure(
    `${recursiveSource}\nentry const folded = answer ()\n`,
    "constant_expression",
  );
});
