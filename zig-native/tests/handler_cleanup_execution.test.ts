import { ok } from "node:assert/strict";
import { compileAndRun, equal } from "./compile_helpers.ts";

Deno.test("private effect frames are released between raw calls without a collector or host reset", async () => {
  await compileAndRun(
    `
type State a is effect = { get: Unit -> a, set: a -> Unit }
entry const exercise = fn (input: Array U32) => do:
  let seed = input[0]
  let provider = @effect.state (State.get U32) (State.set U32) seed
  let (state, value) = do provider:
    use State.set U32 (seed + 1)
    use current <- State.get U32 ()
    return current
  return state + value
entry const memory = fn () -> Array U32 => #[]
`,
    async (_, bytes) => {
      // Deliberately bypass the guest wrapper's per-call arena reset. There is
      // no source loop and therefore no loop collector in this entry point.
      // Array entries also skip the generated scalar-entry reset.
      const { instance } = await WebAssembly.instantiate(bytes);
      const exercise = instance.exports.exercise as (seed: number) => number;
      const memory = instance.exports["blot:memory"] as WebAssembly.Memory;
      const allocate = instance.exports["blot:allocate"] as (
        bytes: number,
      ) => number;
      const input = allocate(8);
      new DataView(memory.buffer).setUint32(input, 1, true);
      new DataView(memory.buffer).setUint32(input + 4, 0, true);
      equal(exercise(input), 2);
      const warmed = memory.buffer.byteLength;
      for (let seed = 1; seed <= 10000; seed++) {
        new DataView(memory.buffer).setUint32(input + 4, seed, true);
        equal(exercise(input), (seed + 1) * 2);
      }
      ok(
        memory.buffer.byteLength <= warmed + 65536,
        `private provider storage grew from ${warmed} to ${memory.buffer.byteLength} bytes across completed scopes`,
      );
    },
  );
});

Deno.test("an escaping State payload survives private frame cleanup and later storage reuse", async () => {
  await compileAndRun(
    `
type State a is effect = { get: Unit -> a, set: a -> Unit }
type Thunk is data = #Thunk (Unit -> U32)
const make = fn (seed: U32) => do:
  let provider = @effect.state (State.get Thunk) (State.set Thunk) (#Thunk (fn () => seed))
  let (state, result) = do provider:
    use State.set Thunk (#Thunk (fn () => seed + 1))
    return seed
  return state
entry const exercise = fn (seed: U32) => do:
  let #Thunk first = make seed
  let #Thunk second = make (seed + 40)
  return first () + second ()
entry const memory = fn () -> Array U32 => #[]
`,
    (guest) => {
      equal(guest.call("exercise", 1), 44);
      equal(guest.call("exercise", 20), 82);
    },
  );
});
