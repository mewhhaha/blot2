import { compileAndRun, equal } from "./compile_helpers.ts";

Deno.test("effect runner: generic_run", async () => {
  await compileAndRun(
    `type State a is effect = { get: Unit -> a, set: a -> Unit }
const run = func initial => return func action => return @effect.run State.get State.set initial action
entry const answer = func () => return do:
  let (next,previous) = run 41 (func () => return do:
    use previous <- State.get ()
    use State.set (@u32.add previous 1)
    break previous)
  break @u32.add next previous
`,
    (guest) => {
      for (let i = 0; i < 100; i++) equal(guest.call("answer", null), 83);
    },
  );
});

Deno.test("effect runner: reader_function_witness", async () => {
  await compileAndRun(
    `type State a is effect = { get: Unit -> a, set: a -> Unit }
entry const answer = func () : U32 => return @effect.reader State.get (func () : U32 => return @panic "witness called") (func () => return 42) (func () : U32 => return State.get ())
`,
    (guest) => {
      for (let i = 0; i < 100; i++) equal(guest.call("answer", null), 42);
    },
  );
});

Deno.test("effect runner: writer_forwarding", async () => {
  await compileAndRun(
    `type State a is effect = { get: Unit -> a, set: a -> Unit }
entry const answer = func () => return do:
  let (next,result) = @effect.run State.get State.set 0 (func () => return
    @effect.writer State.set (func () : U32 => return @panic "witness called") (func value => return State.set value) (func () => return do:
      use State.set 42
      break 42))
  break @u32.add next result
`,
    (guest) => {
      for (let i = 0; i < 100; i++) equal(guest.call("answer", null), 84);
    },
  );
});

Deno.test("effect runner: action_operand_before_installation", async () => {
  await compileAndRun(
    `type State a is effect = { get: Unit -> a, set: a -> Unit }
entry const answer = func () => return do:
  let (next,result) = @effect.run State.get State.set 41 (func () => return
    @effect.reader State.get 0 (func () => return 99) (do:
      use before <- State.get ()
      break (func () : U32 => return before)))
  break @u32.add next result
`,
    (guest) => {
      for (let i = 0; i < 100; i++) equal(guest.call("answer", null), 82);
    },
  );
});
