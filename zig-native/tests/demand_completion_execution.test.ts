import { strict as assert } from "node:assert";
import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

function counted(bytes: Uint8Array<ArrayBuffer>): void {
  const module = new WebAssembly.Module(bytes);
  assert.deepEqual([
    ...new Uint8Array(
      WebAssembly.Module.customSections(module, "blot:ownership")[0],
    ),
  ], [2, 2, 0]);
}

function cancellationSource(exit: "return" | "break", nested: boolean): string {
  return `
type Tick is effect = { read: U32 -> U32 }
const delay = func ~value => return value
const abort = func log => return func computation => return do:
  for request in @requests computation:
    case request of
      effect Tick.read value =>
        use log 1
        ${exit === "return" ? "return 7" : "break"}
      complete value =>
        break value
  break 7
const finish = func log => return func computation => return do:
  for request in @requests computation:
    case request of
      effect Tick.read value =>
        use log 2
        yield @u32.add value 40
      complete value =>
        break value
const scenario = func log => return do:
  let inner = delay (Tick.read 1)
  let pending = delay (do:
    use value <- ${nested ? "@demand inner" : "Tick.read 1"}
    break @u32.add value 1
  )
  let work = @computation (func () => return @demand pending)
  use first <- abort log work
  use second <- finish log work
  use third <- finish log work
  break @u32.add first (@u32.add second third)
entry const answer = func (log: U32 -> U32 ! {Foreign}) => return do:
  use result <- scenario log
  break result
entry const folded = scenario (func value => return value)
`;
}

const trappedSource = `
type Tick is effect = { read: Unit -> U32 }
const keep = func ~value => return func () => return @demand value
const saved = keep (Tick.read ())
const divided = keep (@u32.div 1 (Tick.read ()))
entry const answer = func (host: Unit -> U32 ! {Foreign}) => return do (@effect.provider Tick.read host):
  break saved ()
entry const divide = func (host: Unit -> U32 ! {Foreign}) => return do (@effect.provider Tick.read host):
  break divided ()
entry const pure = func () => return 7
`;

const recursiveSource = `
type State a is effect = { get: Unit -> a, set: a -> Unit }
type Node is data = $End | $Next (Unit -> U32 ! {State.get Node})
const keep = func ~value => return func () => return @demand value
const get = func (witness: Unit -> a) : a => return State.get ()
entry const answer = func () => return do:
  let (_, result) = @effect.run State.get State.set $End (func () => return do:
    let delayed = keep (do:
      use link <- get (func () => return $End)
      break case link of
        $End => 0
        $Next callback => callback ()
    )
    use State.set ($Next delayed)
    break delayed ()
  )
  break result
entry const pure = func () => return 7
`;

for (const asynchronous of [false, true]) {
  const mode = asynchronous ? "JSPI" : "sync";
  Deno.test(`cancelled demands retry without caching a partial result (${mode})`, async () => {
    for (const exit of ["return", "break"] as const) {
      for (const nested of [false, true]) {
        await compileAndRun(
          cancellationSource(exit, nested),
          async (guest, bytes) => {
            counted(bytes);
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
          },
          { asynchronous },
        );
      }
    }
  });

  Deno.test(`failed persistent demands remain terminal after host or Wasm traps (${mode})`, async () => {
    await compileAndRun(trappedSource, async (guest, bytes) => {
      counted(bytes);
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
    await compileAndRun(recursiveSource, async (guest, bytes) => {
      counted(bytes);
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
