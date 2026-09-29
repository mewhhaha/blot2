import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { createNativeCompiler } from "./native.ts";
import { createSourceCompiler } from "./source.ts";
import { instantiateGuest } from "./guest.ts";

for (const backend of ["javascript", "native"] as const) {
  Deno.test(`ever compacts a curried numeric-array carry and preserves pre-loop aliases (${backend})`, async () => {
    const compiler = backend === "javascript"
      ? await createSourceCompiler()
      : await createNativeCompiler();
    try {
      const artifact = await compiler.compile(`
const repeat = fn start => fn limit => do:
  let original = @array.fill 1024 start
  let state: Array F32 = original
  for ever:
    state := @array.fill 1024 (@array.get self 0 + 1.0)
    if @array.get state 0 >= limit:
      return [@array.get state 0, @array.get original 0]
entry const run = fn (limit: F32) => repeat 3.0 limit
`);
      const { instance } = await WebAssembly.instantiate(artifact.bytes);
      const pointer = (instance.exports.run as CallableFunction)(10003);
      const memory = instance.exports["blot:memory"] as WebAssembly.Memory;
      equal(
        new Float32Array(memory.buffer, pointer + 4, 2),
        new Float32Array([10003, 3]),
      );
      // More than 39 MiB was cumulatively allocated in a 16 MiB arena.
      ok(
        memory.buffer.byteLength <= 128 * 1024,
        `arena grew to ${memory.buffer.byteLength}`,
      );
    } finally {
      await compiler.dispose();
    }
  });

  Deno.test(`ever never recycles arrays retained by an enclosing state provider (${backend})`, async () => {
    const compiler = backend === "javascript"
      ? await createSourceCompiler()
      : await createNativeCompiler();
    try {
      const artifact = await compiler.compile(`
effect Saved.read: Unit -> Array F32
effect Saved.write: Array F32 -> Unit
const repeat = fn () => do:
  let state: Array F32 = [0.0]
  for ever:
    state := @array.fill 32 (@array.get self 0 + 1.0)
    if @array.get state 0 == 1.0:
      use Saved.write [42.0]
    if @array.get state 0 >= 10.0:
      return ()
entry const indirect = fn () => do:
  let (saved, _) = do (@effect.state Saved.read Saved.write [0.0]):
    return repeat ()
  return @array.get saved 0
entry const direct = fn () => do:
  let (saved, _) = do (@effect.state Saved.read Saved.write [0.0]):
    let state: Array F32 = [0.0]
    for ever:
      state := @array.fill 32 (@array.get self 0 + 1.0)
      if @array.get state 0 == 1.0:
        use Saved.write [42.0]
      if @array.get state 0 >= 10.0:
        return ()
  return @array.get saved 0
`);
      const guest = await instantiateGuest(artifact.bytes);
      try {
        equal(guest.call("indirect", null), 42);
        equal(guest.call("direct", null), 42);
      } finally {
        guest.dispose();
      }
    } finally {
      await compiler.dispose();
    }
  });

  Deno.test(`ever compacts the specialized game loop with a Foreign host parameter (${backend})`, async () => {
    const compiler = backend === "javascript"
      ? await createSourceCompiler()
      : await createNativeCompiler();
    try {
      const artifact = await compiler.compile(`
type Game [step] is data = #Game {step: step}
const run = fn game => fn schema => fn (host: F32 -> F32 ! {Foreign}) => do:
  let state: Array F32 = @array.fill 1024 (U32.to_f32 schema)
  for ever:
    use amount <- host (@array.get state 0)
    if amount >= 10003.0:
      return amount
    state := game.step self
const game = #Game {step: fn state => @array.fill 1024 (@array.get state 0 + 1.0)}
entry const main = fn host => run game 3 host
`);
      const guest = await instantiateGuest(artifact.bytes);
      try {
        let calls = 0;
        const host = guest.capability({
          parameter: "F32",
          result: "F32",
          call: (value) => {
            calls++;
            return value;
          },
        });
        equal(guest.call("main", host), 10003);
        equal(calls, 10001);
      } finally {
        guest.dispose();
      }
    } finally {
      await compiler.dispose();
    }
  });

  Deno.test(`ever carry does not inherit ownership after selecting a borrowed array (${backend})`, async () => {
    const compiler = backend === "javascript"
      ? await createSourceCompiler()
      : await createNativeCompiler();
    try {
      const artifact = await compiler.compile(`
const select = fn turn => fn borrowed => fn current => case turn of
  0 => borrowed
  _ => current
entry const main = fn (host: Unit -> U32 ! {Foreign}) => do:
  let original = [7.0]
  let state = [0.0]
  for ever:
    use turn <- host ()
    state := @array.set self 0 99.0
    state := select turn original self
    if turn == 2:
      return @array.get original 0
`);
      const guest = await instantiateGuest(artifact.bytes);
      try {
        let turn = 0;
        const host = guest.capability({
          parameter: "Unit",
          result: "U32",
          call: () => turn++,
        });
        equal(guest.call("main", host), 7);
      } finally {
        guest.dispose();
      }
    } finally {
      await compiler.dispose();
    }
  });
}
