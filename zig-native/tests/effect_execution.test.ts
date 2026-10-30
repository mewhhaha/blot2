import { compileAndRun, equal } from "./compile_helpers.ts";

Deno.test("providers handle operations through named calls, callbacks and demands", async () => {
  await compileAndRun(
    `
effect Read: Unit -> U32
const provider = @effect.provider Read (func () => return 42)
const read = func () => return Read ()
const invoke = func callback => return callback ()
const force = func ~value => return @force value
const ignore = func ~value => return 42
entry const constant = do provider:
  break Read ()
entry const direct = func () => return do provider:
  break read ()
entry const callback = func () => return do provider:
  break invoke (func () => return Read ())
entry const delayed = func () => return do provider:
  break force (Read ())
entry const ignored = func () => return ignore (Read ())
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
const outer = @effect.provider Read.first (func () => return 20)
const second = @effect.provider Read.second (func () => return Read.first ())
const younger = @effect.provider Read.first (func () => return 99)
entry const answer = func () => return do outer:
  break do second:
    break do younger:
      use first <- Read.first ()
      use forwarded <- Read.second ()
      break @u32.add first forwarded
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
entry const answer = func () => return do:
  let (state, old) = do provider:
    use old <- State.get (Array U32) ()
    let next = @array.set old 0 42
    use State.set (Array U32) next
    break old
  break @u32.add (@array.get state 0) (@array.get old 0)
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
entry const answer = func (value: F32) => return do:
  let (state, old) = do provider:
    use old <- State.get F32 ()
    use State.set F32 (@f32.add old value)
    break old
  break @f32.add state old
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
const first = @effect.provider (Signal.ping U32) (func value => return @u32.add value 1)
const second = @effect.provider (Signal.ping F32) (func value => return @u32.add value 100)
entry const answer = func (value: U32) => return do first:
  break do second:
    use a <- Signal.ping U32 value
    use b <- Signal.ping F32 value
    break @u32.add a b
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
const choose = func (left: Bool) => return func ~(right: Bool) => return if left then @force right else false
const combine = func (left: U32) => return func (right: U32) => return do:
  use Touch left
  break @u32.add left right
const receive = func (flag: Bool) => return do:
  let go = flag && false
  if go:
    break ()
  use Touch 7
  break ()
const selected = func (flag: Bool) => return flag && (do:
  use value <- Read ()
  break @u32.eq value 42)
const merge = func () => return 20 %% 22
const reader = @effect.provider Read (func () => return 42)
const touch = @effect.provider Touch (func value => return ())
entry const answer = do touch:
  use receive true
  break 20 %% 22
entry const loaded = do reader:
  break selected true
entry const unforced = false && @panic "not demanded"
type Holder a is data = #Holder a
const callbacks = #Holder receive
entry const run = func (flag: Bool) : U32 => return do touch:
  let #Holder action = callbacks
  use action flag
  break 20 %% 22
`, guest => {
    equal(guest.read("answer"), 42);
    equal(guest.read("loaded"), true);
    equal(guest.read("unforced"), false);
    equal(guest.call("run", true), 42);
    equal(guest.call("run", false), 42);
  });
});
