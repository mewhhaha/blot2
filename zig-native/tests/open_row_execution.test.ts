import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

Deno.test("written generic rows instantiate for pure and concrete effect callbacks", async () => {
  await compileAndRun(
    `
type State a is effect = { get: Unit -> a }
const invoke: (Unit -> a ! {| e}) -> a ! {| e} = fn callback => callback ()
const read = fn (callback: Unit -> U32 ! {State.get U32 | e}) => callback ()
const provider = @effect.provider (State.get U32) (fn () => 42)
entry const pure = fn () => invoke (fn () => 37)
entry const answer = fn () => do provider:
  return invoke (fn () => read (fn () => State.get U32 ()))
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
entry const answer = fn () => do:
  let invoke = fn (callback: Unit -> U32 ! {| e}) => callback ()
  let first = invoke (fn () => 40)
  let invoke = fn (callback: Unit -> F32 ! {| e}) => callback ()
  let second = invoke (fn () => 2.0)
  let identity = fn (value: e) => value
  return identity (@u32.add first (@f32.to_u32 second))
`,
    (guest) => equal(guest.call("answer", null), 42),
  );
});

Deno.test("written open rows reject kind collisions and polymorphic labels", async () => {
  await compileExpectedFailure(
    `
const bad: e -> U32 ! {| e} = fn value => 1
entry const answer = 42
`,
    "annotation_kind_mismatch",
  );
  await compileExpectedFailure(
    `
type State a is effect = { get: Unit -> a }
const bad: Unit -> a ! {State.get a | e} = fn () => 42
entry const answer = 42
`,
    "unsupported_polymorphic_effect_label",
  );
  await compileExpectedFailure(
    `
const pure = fn (callback: Unit -> U32) => callback ()
const bad = fn (callback: Unit -> U32 ! {Foreign | e}) => pure callback
entry const answer = 42
`,
    "effect_mismatch",
  );
});
