import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

Deno.test("written generic rows instantiate for pure and concrete effect callbacks", async () => {
  await compileAndRun(
    `
type State a is effect = { get: Unit -> a }
const invoke: (Unit -> a ! {| e}) -> a ! {| e} = func callback => return callback ()
const read = func (callback: Unit -> U32 ! {State.get U32 | e}) => return callback ()
const provider = @effect.provider (State.get U32) (func () => return 42)
entry const pure = func () => return invoke (func () => return 37)
entry const answer = func () => return do provider:
  break invoke (func () => return read (func () => return State.get U32 ()))
`,
    (guest) => {
      equal(guest.call("pure", null), 37);
      equal(guest.call("answer", null), 42);
    },
  );
});

Deno.test("written row binders stay local across sibling bindings", async () => {
  await compileAndRun(
    `
entry const answer = func () => return do:
  let invoke = func (callback: Unit -> U32 ! {| e}) => return callback ()
  let first = invoke (func () => return 40)
  let invoke = func (callback: Unit -> F32 ! {| e}) => return callback ()
  let second = invoke (func () => return 2.0)
  let identity = func (value: e) => return value
  break identity (@u32.add first (@f32.to_u32 second))
`,
    (guest) => equal(guest.call("answer", null), 42),
  );
});

Deno.test("written open rows reject kind collisions and effect erasure", async () => {
  await compileExpectedFailure(
    `
const bad: e -> U32 ! {| e} = func value => return 1
entry const answer = 42
`,
    "annotation_kind_mismatch",
  );
  await compileExpectedFailure(
    `
const pure = func (callback: Unit -> U32) => return callback ()
const bad = func (callback: Unit -> U32 ! {Foreign | e}) => return pure callback
entry const answer = 42
`,
    "effect_mismatch",
  );
});
