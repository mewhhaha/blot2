import { compileAndRun, equal } from "./compile_helpers.ts";

Deno.test("effect runner: generic_run", async () => {
  await compileAndRun(
    `type State a is effect = { get: Unit -> a, set: a -> Unit }
const run = fn initial => fn action => @effect.run State.get State.set initial action
entry const answer = fn () => do:
  let (next,previous) = run 41 (fn () => do:
    use previous <- State.get ()
    use State.set (@u32.add previous 1)
    return previous)
  return @u32.add next previous
`,
    (guest) => {
      for (let i = 0; i < 100; i++) equal(guest.call("answer", null), 83);
    },
  );
});

Deno.test("effect runner: reader_function_witness", async () => {
  await compileAndRun(
    `type State a is effect = { get: Unit -> a, set: a -> Unit }
entry const answer = fn () -> U32 => @effect.reader State.get (fn () -> U32 => @panic "witness called") (fn () => 42) (fn () -> U32 => State.get ())
`,
    (guest) => {
      for (let i = 0; i < 100; i++) equal(guest.call("answer", null), 42);
    },
  );
});

Deno.test("effect runner: writer_forwarding", async () => {
  await compileAndRun(
    `type State a is effect = { get: Unit -> a, set: a -> Unit }
entry const answer = fn () => do:
  let (next,result) = @effect.run State.get State.set 0 (fn () =>
    @effect.writer State.set (fn () -> U32 => @panic "witness called") (fn value => State.set value) (fn () => do:
      use State.set 42
      return 42))
  return @u32.add next result
`,
    (guest) => {
      for (let i = 0; i < 100; i++) equal(guest.call("answer", null), 84);
    },
  );
});

Deno.test("effect runner: action_operand_before_installation", async () => {
  await compileAndRun(
    `type State a is effect = { get: Unit -> a, set: a -> Unit }
entry const answer = fn () => do:
  let (next,result) = @effect.run State.get State.set 41 (fn () =>
    @effect.reader State.get 0 (fn () => 99) (do:
      use before <- State.get ()
      return (fn () -> U32 => before)))
  return @u32.add next result
`,
    (guest) => {
      for (let i = 0; i < 100; i++) equal(guest.call("answer", null), 82);
    },
  );
});
