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

const cells = `
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
`;

Deno.test("rebound generalized builders close every link of the chain", async () => {
  await returnsArgument(`${cells}
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

// A closure capturing a local whose uses disagree keeps it on its unproven
// runtime path, so both the promoting attempt and the retry without
// promotions fail; the retry owns the reported diagnostic.
Deno.test("a compilation that fails after promoting a generalized local reports the ordinary diagnostic", async () => {
  await compileExpectedFailure(`${builder}
const pair = fn a => fn b => (a, b)
entry const main = fn (x: U32) => do:
  let b = empty ()
  let (_, first) = run b (fn () => x)
  let (_, second) = run b (fn () => (x, 1.5))
  let k = pair x
  let later = fn (y: U32) => k y
  let (a, _) = later first
  let (c, _) = k 1.0
  return a
`, "ownership_unproved");
});

// Uses at different layouts share no physical value: closure ABI and field
// words depend on the layout. A pure runtime producer instead runs once per
// distinct use layout, and each use reads its own instance.
const pair = "const pair = fn a => fn b => (a, b)";

Deno.test("runtime-dependent generalized locals used at different layouts evaluate one instance per layout", async () => {
  await returnsArgument(`
${pair}
entry const main = fn (x: U32) => do:
  let k = pair x
  let (a, _) = k x
  let (b, _) = k 1.5
  return a
`);
});

Deno.test("each instance of a runtime-dependent generalized local keeps its own field layout", async () => {
  await compileAndRun(`
${pair}
entry const main = fn (x: U32) => do:
  let k = pair x
  let (a, _) = k x
  let (b, _) = k 1.5
  return a
entry const fraction = fn (x: F32) => do:
  let k = pair x
  let (_, count) = k 3
  let (_, b) = k (x * 2.0)
  return b
`, (guest) => {
    equal(guest.call("main", 7), 7);
    equal(guest.call("fraction", 1.25), 2.5);
    for (let index = 0; index < 16; index++) guest.call("fraction", index);
    const settled = guest.memoryBytes();
    for (let index = 0; index < 2048; index++) {
      equal(guest.call("fraction", index + 0.5), index * 2 + 1);
      equal(guest.call("main", index), index);
    }
    equal(guest.memoryBytes(), settled);
  });
});

Deno.test("allocating runtime producers release every instance", async () => {
  await compileAndRun(`
${pair}
entry const main = fn (x: U32) => do:
  let k = pair (@array.fill 64 x)
  let (first, _) = k x
  let (second, _) = k 1.5
  return first[3] + second.length - 64
entry const memory = fn () -> Array U32 => #[]
`, (guest) => {
    equal(guest.call("main", 7), 7);
    for (let index = 0; index < 16; index++) guest.call("main", index);
    const settled = guest.memoryBytes();
    if (settled === 0) throw new Error("Expected exported guest memory");
    for (let index = 0; index < 4096; index++) equal(guest.call("main", index), index);
    equal(guest.memoryBytes(), settled);
  });
});

// A second evaluation would edit the already edited array (and return 909).
Deno.test("producers with a proven in-place collection edit still decline", async () => {
  await compileExpectedFailure(`
${pair}
entry const main = fn (x: U32) => do:
  let values = @array.fill 4 x
  let k = pair (@array.set values 0 (values[0] + 1))
  let (first, _) = k x
  let (second, _) = k 1.5
  return first[0] * 100 + second[0]
`, "ownership_unproved");
});

Deno.test("repeated uses at one layout share their instance", async () => {
  await returnsArgument(`
${pair}
entry const main = fn (x: U32) => do:
  let k = pair x
  let (_, whole) = k (x + 1)
  let (_, half) = k 1.5
  let (a, same) = k whole
  return same - 1
`);
});

Deno.test("uses in loops and early-returning branches read their own instance", async () => {
  await compileAndRun(`
${pair}
entry const main = fn (x: U32) => do:
  let k = pair x
  let total = 0
  for index in 0..3:
    let (a, step) = k index
    total := total + a + step
  let (_, fraction) = k 1.5
  if fraction > 1.0:
    let (c, _) = k 2
    return total + c
  return total
`, (guest) => {
    equal(guest.call("main", 7), 31);
    for (let index = 0; index < 16; index++) guest.call("main", index);
    const settled = guest.memoryBytes();
    for (let index = 0; index < 2048; index++) equal(guest.call("main", index), index * 4 + 3);
    equal(guest.memoryBytes(), settled);
  });
});

Deno.test("an alias of a runtime-dependent generalized local instances both links", async () => {
  await returnsArgument(`
${pair}
entry const main = fn (x: U32) => do:
  let k = pair x
  let g = k
  let (a, _) = g x
  let (b, _) = g 1.5
  return a
`);
});

Deno.test("rebound runtime builders used at different layouts instance every link", async () => {
  await returnsArgument(`${cells}
entry const main = fn (x: U32) => do:
  let builder = empty ()
  builder := insert_cell x self
  let (_, first) = create builder (fn () => x)
  let (_, (_, fraction)) = create builder (fn () => (x, 1.5))
  return first
`);
});

// Ink's app builders (issue #10). Closed builders whose uses disagree keep
// their evaluator value. `run` reads only the scope, so the render callback's
// rows stay open there and the callback is serialized at the instance its own
// body infers, every arrow of a curried literal included. `initial` and
// `render` leave the scope's action result open; they read the fields they
// select.
const app = `
type State a is effect = {
  get: Unit -> a
  set: a -> Unit
}
type App [world, scope, render] is data = #App { initial: world, scope: world -> scope, render: render }
type Trace is data = #Trace (Array U32)
const empty = fn () => do:
  let scope = fn world => fn action => do:
    use outcome <- @effect.run State.get State.set world action
    return outcome
  return #App { initial: #Trace #[], scope, render: fn (frame: U32) => frame }
const note = fn (value: U32) => do:
  use current <- State.get ()
  let #Trace values = current
  return State.set (#Trace #[...values, value])
const with_render = fn render => fn app => do:
  let #App { initial, scope } = app
  return #App { initial, scope, render }
const initial = fn app => do:
  let #App { initial } = app
  return initial
const run = fn app => fn world => fn action => do:
  let #App { scope } = app
  return scope world action
entry const memory = fn () -> Array U32 => #[]
`;

async function returnsArgumentWithMemory(source: string): Promise<void> {
  await compileAndRun(source, (guest) => {
    equal(guest.call("main", 7), 7);
    for (let index = 0; index < 16; index++) guest.call("main", index);
    const settled = guest.memoryBytes();
    if (settled === 0) throw new Error("Expected exported guest memory");
    for (let index = 0; index < 2048; index++) equal(guest.call("main", index), index);
    equal(guest.memoryBytes(), settled);
  });
}

Deno.test("promoted builders serialize curried callbacks whose rows a use leaves open", async () => {
  await returnsArgumentWithMemory(`${app}
const render = fn app => fn frame => do:
  let #App { render } = app
  return render 2 frame
entry const main = fn (x: U32) => do:
  let app = with_render (fn (scale: U32) => fn (frame: U32) => do:
    use note frame
    return frame * scale) (empty ())
  let (trace, doubled) = run app (initial app) (fn () => render app x)
  let #Trace values = trace
  return doubled - x + values.length - 1
`);
});

// A := link built only from a promoted builder and closed arguments is
// closed too, so it keeps its evaluator value instead of serializing the
// promoted builder at a layout its own open uses leave unresolved.
Deno.test("rebinding links that read a promoted builder are promoted with it", async () => {
  await returnsArgumentWithMemory(`${app}
const render = fn app => fn frame => do:
  let #App { render } = app
  return render frame
entry const main = fn (x: U32) => do:
  let app = empty ()
  app := with_render (fn (frame: U32) => do:
    use note frame
    return frame + 1) self
  let (trace, next) = run app (initial app) (fn () => render app x)
  let #Trace values = trace
  return next + values.length - 2
`);
});
