import { deepStrictEqual } from "node:assert/strict";
import { compileAndRun, equal } from "./compile_helpers.ts";

Deno.test("state and memoized demands can form cycles that must be reclaimed after their scope", async () => {
  await compileAndRun(`
type State a is effect = { get: Unit -> a, set: a -> Unit }
type Node is data = #End | #Next (Unit -> Node ! {State.get Node})
const keep = fn ~value => fn () => @demand value
const get = fn (witness: Unit -> a) -> a => State.get ()
const cycle = fn (seed: U32) => do:
  let (_, result) = @effect.run State.get State.set #End (fn () => do:
    let delayed = keep (get (fn () => #End))
    use State.set (#Next delayed)
    use first <- delayed ()
    use State.set #End
    use cached <- delayed ()
    return case cached of
      #End => @panic "the demand lost its memoized cycle"
      #Next same => do:
        use again <- same ()
        return case again of
          #End => @panic "the retained closure lost its memo"
          #Next _ => seed
  )
  return result
entry const run = fn (count: U32) => do:
  let index = 0
  let sum = 0
  for ever:
    if index == count:
      return sum
    sum := self + cycle index
    index := self + 1
entry const memory = fn () -> Array U32 => #[]
`, guest => {
    equal(guest.call("run", 512), 511 * 512 / 2);
    const warmed = guest.memoryBytes();
    equal(warmed > 0, true);
    equal(guest.call("run", 20000), 19999 * 20000 / 2);
    equal(guest.memoryBytes() <= warmed + 65536, true);
  });
});

Deno.test("forever collection preserves array carries, older captures and scalar bits with bounded memory", async () => {
  await compileAndRun(
    `
entry const run = fn (limit: U32) -> U32 => do:
  let older = @array.fill 4096 65552
  let read = fn index => @array.get older index
  let values = #[0]
  let index = 0
  for ever:
    if @u32.eq index limit:
      return @u32.add (@array.get values 0) (read 4095)
    let discarded = @array.fill 8192 index
    values[0] := @u32.add self 1
    index := @u32.add self 1
entry const floating = fn (limit: U32) -> F32 => do:
  let total = 0.0
  let index = 0
  for ever:
    if @u32.eq index limit:
      return total
    let discarded = @array.fill 8192 index
    total := @f32.add self 0.5
    index := @u32.add self 1
entry const memory = fn () -> Array U32 => #[]
`,
    (guest) => {
      equal(guest.call("run", 256), 65808);
      const warmed = guest.memoryBytes();
      equal(warmed > 0, true);
      equal(guest.call("run", 2048), 67600);
      equal(guest.call("floating", 2048), 1024);
      equal(guest.memoryBytes() <= warmed + 65536, true);
    },
  );
});

Deno.test("forever collection traces updated state cells pinned before the loop", async () => {
  await compileAndRun(
    `
type State a is effect = { get: Unit -> a, set: a -> Unit }
entry const run = fn (limit: U32) -> U32 => do:
  let provider = @effect.state (State.get (Array U32)) (State.set (Array U32)) #[0]
  let (state,result) = do provider:
    let index = 0
    for ever:
      if @u32.eq index limit:
        use values <- State.get (Array U32) ()
        return @array.get values 0
      index := @u32.add self 1
      use State.set (Array U32) #[index]
      let discarded = @array.fill 8192 index
  return @u32.add (@array.get state 0) result
entry const memory = fn () -> Array U32 => #[]
`,
    (guest) => {
      equal(guest.call("run", 256), 512);
      const warmed = guest.memoryBytes();
      equal(warmed > 0, true);
      equal(guest.call("run", 2048), 4096);
      equal(guest.memoryBytes() <= warmed + 65536, true);
    },
  );
});

const jspi = WebAssembly as unknown as {
  Suspending?: unknown;
  promising?: unknown;
};
Deno.test({
  name:
    "long-lived Foreign array exchange reclaims loop temporaries and resets free lists between invocations",
  ignore: typeof jspi.Suspending !== "function" ||
    typeof jspi.promising !== "function",
  fn: async () => {
    await compileAndRun(
      `
entry const main = fn (host: Array F32 -> Array F32 ! {Foreign}) -> Unit => do:
  let pending = #[0.0, 1.0]
  for ever:
    if @f32.eq (@array.get pending 1) 0.0:
      return ()
    let discarded = @array.fill 1280 0
    use next <- host pending
    pending := next
`,
      async (guest) => {
        for (let run = 0; run < 2; run++) {
          let calls = 0;
          let warmed = 0;
          const retained: Float32Array[] = [];
          const host = guest.capabilityAsync({
            parameter: "Array F32",
            result: "Array F32",
            call: (packet) => {
              deepStrictEqual(packet, Float32Array.of(calls, 1));
              if (calls < 4) retained.push(packet);
              calls++;
              if (calls === 256) warmed = guest.memoryBytes();
              return Promise.resolve(
                Float32Array.of(calls, calls < 2048 ? 1 : 0),
              );
            },
          });
          equal(await guest.callAsync("main", host), null);
          equal(calls, 2048);
          equal(guest.memoryBytes() <= warmed + 65536, true);
          retained.forEach((packet, index) =>
            deepStrictEqual(packet, Float32Array.of(index, 1))
          );
        }
      },
      { asynchronous: true },
    );
  },
});
