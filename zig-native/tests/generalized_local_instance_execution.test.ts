import { compileAndRun, compileExpectedFailure, equal } from "./compile_helpers.ts";

// Issue #10: generalized locals whose instances agree on one layout prepare
// checked storage at that instance instead of an erased payload.
const builder = `
type B [w, s] is data = #B { initial: w, s: w -> s }
const base = fn world => fn action => (world, action ())
const empty = fn () => #B { initial: (), s: base }
const run = fn b => fn action => do:
  let #B { initial, s } = b
  return s initial action
`;

async function returnsArgument(source: string): Promise<void> {
  await compileAndRun(source, (guest) => {
    equal(guest.call("main", 7), 7);
    for (let index = 0; index < 16; index++) guest.call("main", index);
    const settled = guest.memoryBytes();
    for (let index = 0; index < 2048; index++) equal(guest.call("main", index), index);
    equal(guest.memoryBytes(), settled);
  });
}

Deno.test("generalized local aliases take the concrete instance of the alias use", async () => {
  await returnsArgument(`${builder}
entry const main = fn (x: U32) => do:
  let b = empty ()
  let c = b
  let (_, result) = run c (fn () => x)
  return result
`);
});

Deno.test("generalized locals ignore an unused alias of themselves", async () => {
  await returnsArgument(`${builder}
entry const main = fn (x: U32) => do:
  let b = empty ()
  let c = b
  let (_, result) = run b (fn () => x)
  return result
`);
});

Deno.test("generalized locals used repeatedly at one layout share that instance", async () => {
  await returnsArgument(`${builder}
entry const main = fn (x: U32) => do:
  let b = empty ()
  let (_, first) = run b (fn () => x)
  let (_, second) = run b (fn () => x)
  return second
`);
});

Deno.test("generalized partial applications take the concrete instance of their use", async () => {
  await returnsArgument(`
const pair = fn a => fn b => (a, b)
const wrap = fn scope => fn value => scope value
entry const main = fn (x: U32) => do:
  let left = pair 1
  let twice = wrap (fn p => (p, p))
  let (_, value) = left x
  let (_, same) = twice value
  return same
`);
});

Deno.test("rebound generalized builders close every link of the chain", async () => {
  await returnsArgument(`
type Builder [world, scope, schema] is data = #Builder { initial: world, scope: world -> scope, schema: schema }
type End is data = #End
type State a is effect = {
  get: Unit -> a
  set: a -> Unit
}
const empty_scope = fn world => fn action => do:
  use result <- action ()
  return (world, result)
const empty = fn () => #Builder { initial: (), scope: empty_scope, schema: #End }
const insert_cell = fn initial => fn builder => do:
  let #Builder { initial: previous_initial, scope: previous_scope, schema } = builder
  let scope = fn world => fn action => do:
    let (current, previous) = world
    use outcome <- @effect.run State.get State.set current (fn () => previous_scope previous action)
    let (next, (previous_next, result)) = outcome
    return ((next, previous_next), result)
  return #Builder { initial: (initial, previous_initial), scope, schema }
const create = fn builder => fn action => do:
  let #Builder { initial, scope } = builder
  return scope initial action
entry const main = fn (x: U32) => do:
  let builder = empty ()
  builder := insert_cell 1 self
  let (_, result) = create builder (fn () => x)
  return result
`);
});

Deno.test("unobserved generalized locals choose storage for their holes", async () => {
  await returnsArgument(`${builder}
const pair = fn a => fn b => (a, b)
const choose = fn () => pair
entry const main = fn (x: U32) => do:
  let unused = choose ()
  let builder = empty ()
  return x
`);
});

Deno.test("closed generalized locals used at different layouts keep their evaluator value", async () => {
  await returnsArgument(`${builder}
const twice = fn f => fn value => f (f value)
entry const main = fn (x: U32) => do:
  let b = empty ()
  let (_, first) = run b (fn () => x)
  let (_, second) = run b (fn () => (x, 1.5))
  let same = twice (fn v => v)
  let fraction = same 2.5
  return same first
`);
});

Deno.test("a compilation that fails after promoting a generalized local reports the ordinary diagnostic", async () => {
  await compileExpectedFailure(`${builder}
const pair = fn a => fn b => (a, b)
entry const main = fn (x: U32) => do:
  let b = empty ()
  let (_, first) = run b (fn () => x)
  let (_, second) = run b (fn () => (x, 1.5))
  let k = pair x
  let (a, _) = k first
  let (c, _) = k 1.0
  return a
`, "ownership_unproved");
});

Deno.test("runtime-dependent generalized locals used at different layouts still decline checked storage", async () => {
  await compileExpectedFailure(`
const pair = fn a => fn b => (a, b)
entry const main = fn (x: U32) => do:
  let k = pair x
  let (a, _) = k x
  let (b, _) = k 1.0
  return a
`, "ownership_unproved");
});
