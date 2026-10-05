import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

Deno.test("effect reflection inspects checked rows without evaluating reflected functions", async () => {
  await compileAndRun(
    `
effect Read: Unit -> U32
effect Other: Unit -> U32
const read: Unit -> U32 ! {Read,Read} = fn () => @panic "reflected function invoked"
const count = fn (effects: EffectSet) => @effect.count effects
const contains = fn effects => fn operation => @effect.has effects operation
const same = fn (left: EffectDescriptor) => fn right => @effect.same left right
const requirements = @effect.of read
const reader = @effect.descriptor Read
const make = fn extra => fn () => @u32.add (Read ()) extra
const invoke = fn () => (make 2) ()
entry const total = count requirements
entry const present = contains requirements reader
entry const absent = contains requirements (@effect.descriptor Other)
entry const identical = same reader (@effect.descriptor Read)
entry const different = same reader (@effect.descriptor Other)
entry const foreign = @effect.same (@effect.descriptor Foreign) (@effect.descriptor Foreign)
entry const creation_effects = @effect.count (@effect.of make)
entry const invocation_effects = @effect.count (@effect.of invoke)
entry const run = fn () => total
`,
    (guest) => {
      equal(guest.read("total"), 1);
      equal(guest.read("present"), true);
      equal(guest.read("absent"), false);
      equal(guest.read("identical"), true);
      equal(guest.read("different"), false);
      equal(guest.read("foreign"), true);
      equal(guest.read("creation_effects"), 0);
      equal(guest.read("invocation_effects"), 1);
      for (let index = 0; index < 100; index++) {
        equal(guest.call("run", null), 1);
      }
    },
  );
});

Deno.test("effect descriptors preserve generic operation arguments and deduplicate repeated labels", async () => {
  await compileAndRun(
    `
type State a is effect = {get: Unit -> a,set: a -> Unit}
const read = fn () => do:
  use State.get U32 ()
  use State.get U32 ()
  return State.get F32 ()
const effects = @effect.of read
entry const total = @effect.count effects
entry const present = @effect.has effects (State.get F32)
entry const absent = @effect.has effects (State.set F32)
entry const different = @effect.same (@effect.descriptor (State.get U32)) (@effect.descriptor (State.get F32))
`,
    (guest) => {
      equal(guest.read("total"), 2);
      equal(guest.read("present"), true);
      equal(guest.read("absent"), false);
      equal(guest.read("different"), false);
    },
  );
});

Deno.test("reflection rejects open rows, aliased function targets and runtime metadata", async () => {
  await compileExpectedFailure(
    `const invoke = fn work => work ()
const invalid = @effect.of invoke
entry const answer = 42
`,
    "open_effect_descriptor",
  );
  await compileExpectedFailure(
    `const read = fn () => 42
const alias = read
entry const count = @effect.count (@effect.of alias)
`,
    "function_target",
  );
  await compileExpectedFailure(
    `const read = fn () => 42
const requirements = @effect.of read
const count = fn effects => @effect.count effects
entry const run = fn () => count requirements
`,
    "backend_const_only",
  );
  await compileExpectedFailure(
    `const read = fn () => 42
entry const invalid = @effect.of read
`,
    "entry_type",
  );
});

Deno.test("opaque reflection metadata cannot become State or type identity through nested values", async () => {
  const base = `const read = fn () => 42
const requirements = @effect.of read
`;
  await compileExpectedFailure(
    base + `entry const answer = do:
  let (_, result) = @state.run #[requirements] (fn () => 42)
  return result
`,
    "ambiguous_state",
  );
  await compileExpectedFailure(
    base + `entry const answer = do:
  let (_, result) = @state.run (requirements,42) (fn () => 42)
  return result
`,
    "ambiguous_state",
  );
  await compileExpectedFailure(
    base +
      `entry const answer = @state.reader requirements (fn () => requirements) (fn () => 42)
`,
    "ambiguous_state",
  );
  await compileExpectedFailure(
    base + `entry const invalid = @type.same (requirements,42) (requirements,42)
`,
    "ambiguous_state",
  );
});
