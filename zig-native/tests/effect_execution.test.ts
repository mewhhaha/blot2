import { compileAndRun, equal } from "./compile_helpers.ts";

Deno.test("providers handle operations through named calls, callbacks and demands", async () => {
  await compileAndRun(
    `
effect Read: Unit -> U32
const provider = @effect.provider Read (fn () => 42)
const read = fn () => Read ()
const invoke = fn callback => callback ()
const force = fn ~value => @force value
const ignore = fn ~value => 42
entry const constant = do provider:
  return Read ()
entry const direct = fn () => do provider:
  return read ()
entry const callback = fn () => do provider:
  return invoke (fn () => Read ())
entry const delayed = fn () => do provider:
  return force (Read ())
entry const ignored = fn () => ignore (Read ())
`,
    (guest) => {
      equal(guest.read("constant"), 42);
      for (let i = 0; i < 100; i++) {
        for (const name of ["direct", "callback", "delayed", "ignored"]) {
          equal(guest.call(name, null), 42);
        }
      }
    },
  );
});

Deno.test("nested providers forward unrelated operations and exclude younger callback scopes", async () => {
  await compileAndRun(
    `
type Read is effect = { first: Unit -> U32, second: Unit -> U32 }
const outer = @effect.provider Read.first (fn () => 20)
const second = @effect.provider Read.second (fn () => Read.first ())
const younger = @effect.provider Read.first (fn () => 99)
entry const answer = fn () => do outer:
  return do second:
    return do younger:
      use first <- Read.first ()
      use forwarded <- Read.second ()
      return @u32.add first forwarded
`,
    (guest) => {
      for (let i = 0; i < 100; i++) equal(guest.call("answer", null), 119);
    },
  );
});

Deno.test("state providers start fresh and preserve earlier immutable snapshots", async () => {
  await compileAndRun(
    `
type State a is effect = { get: Unit -> a, set: a -> Unit }
const provider = @effect.state (State.get (Array U32)) (State.set (Array U32)) #[41]
entry const answer = fn () => do:
  let (state, old) = do provider:
    use old <- State.get (Array U32) ()
    let next = @array.set old 0 42
    use State.set (Array U32) next
    return old
  return @u32.add (@array.get state 0) (@array.get old 0)
`,
    (guest) => {
      for (let i = 0; i < 100; i++) equal(guest.call("answer", null), 83);
    },
  );
});

Deno.test("state cells and operation trampolines preserve F32 arguments and results", async () => {
  await compileAndRun(
    `
type State a is effect = { get: Unit -> a, set: a -> Unit }
const provider = @effect.state (State.get F32) (State.set F32) 1.75
entry const answer = fn (value: F32) => do:
  let (state, old) = do provider:
    use old <- State.get F32 ()
    use State.set F32 (@f32.add old value)
    return old
  return @f32.add state old
`,
    (guest) => {
      for (let i = 0; i < 100; i++) equal(guest.call("answer", 1.25), 4.75);
    },
  );
});

Deno.test("phantom operation type arguments select distinct provider frames", async () => {
  await compileAndRun(
    `
type Signal a is effect = { ping: U32 -> U32 }
const first = @effect.provider (Signal.ping U32) (fn value => @u32.add value 1)
const second = @effect.provider (Signal.ping F32) (fn value => @u32.add value 100)
entry const answer = fn (value: U32) => do first:
  return do second:
    use a <- Signal.ping U32 value
    use b <- Signal.ping F32 value
    return @u32.add a b
`,
    (guest) => {
      for (let i = 0; i < 100; i++) equal(guest.call("answer", 20), 141);
    },
  );
});

Deno.test("named binary callbacks preserve demanded and required effect rows", async () => {
  await compileAndRun(`
infixl 20 (&&) = choose
infixl 60 (%%) = combine
effect Read: Unit -> U32
effect Touch: U32 -> Unit
const choose = fn (left: Bool) => fn ~(right: Bool) => if left then @force right else #False
const combine = fn (left: U32) => fn (right: U32) => do:
  use Touch left
  return @u32.add left right
const receive = fn (flag: Bool) => do:
  let go = flag && #False
  if go:
    return ()
  use Touch 7
  return ()
const selected = fn (flag: Bool) => flag && (do:
  use value <- Read ()
  return @u32.eq value 42)
const merge = fn () => 20 %% 22
const reader = @effect.provider Read (fn () => 42)
const touch = @effect.provider Touch (fn value => ())
entry const answer = do touch:
  use receive #True
  return 20 %% 22
entry const loaded = do reader:
  return selected #True
entry const unforced = #False && @panic "not demanded"
type Holder a is data = #Holder a
const callbacks = #Holder receive
entry const run = fn (flag: Bool) -> U32 => do touch:
  let #Holder action = callbacks
  use action flag
  return 20 %% 22
`, guest => {
    equal(guest.read("answer"), 42);
    equal(guest.read("loaded"), true);
    equal(guest.read("unforced"), false);
    equal(guest.call("run", true), 42);
    equal(guest.call("run", false), 42);
  });
});
