import { compileAndRun, compileExpectedFailure, equal } from "./compile_helpers.ts";

// Issue #10: generalized locals whose instances agree on one layout prepare
// checked storage at that instance instead of an erased payload.
const builder = `
type B [w, s] is data = #B { initial: w, s: w -> s }
const base = fn world => fn action => (world, action ())
const empty = fn () => #B { initial: (), s: base }
const run = fn b => fn action => do:
  let #B { initial, s } = b
  break s initial action
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
  break result
`);
});

Deno.test("generalized locals ignore an unused alias of themselves", async () => {
  await returnsArgument(`${builder}
entry const main = fn (x: U32) => do:
  let b = empty ()
  let c = b
  let (_, result) = run b (fn () => x)
  break result
`);
});

Deno.test("generalized locals used repeatedly at one layout share that instance", async () => {
  await returnsArgument(`${builder}
entry const main = fn (x: U32) => do:
  let b = empty ()
  let (_, first) = run b (fn () => x)
  let (_, second) = run b (fn () => x)
  break second
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
  break same
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
  break (world, result)
const empty = fn () => #Builder { initial: (), scope: empty_scope, schema: #End }
const insert_cell = fn initial => fn builder => do:
  let #Builder { initial: previous_initial, scope: previous_scope, schema } = builder
  let scope = fn world => fn action => do:
    let (current, previous) = world
    use outcome <- @effect.run State.get State.set current (fn () => previous_scope previous action)
    let (next, (previous_next, result)) = outcome
    break ((next, previous_next), result)
  break #Builder { initial: (initial, previous_initial), scope, schema }
const create = fn builder => fn action => do:
  let #Builder { initial, scope } = builder
  break scope initial action
`;

Deno.test("rebound generalized builders close every link of the chain", async () => {
  await returnsArgument(`${cells}
entry const main = fn (x: U32) => do:
  let builder = empty ()
  builder := insert_cell 1 self
  let (_, result) = create builder (fn () => x)
  break result
`);
});

Deno.test("unobserved generalized locals choose storage for their holes", async () => {
  await returnsArgument(`${builder}
const pair = fn a => fn b => (a, b)
const choose = fn () => pair
entry const main = fn (x: U32) => do:
  let unused = choose ()
  let builder = empty ()
  break x
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
  break same first
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
  break a
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
  break a
`);
});

Deno.test("each instance of a runtime-dependent generalized local keeps its own field layout", async () => {
  await compileAndRun(`
${pair}
entry const main = fn (x: U32) => do:
  let k = pair x
  let (a, _) = k x
  let (b, _) = k 1.5
  break a
entry const fraction = fn (x: F32) => do:
  let k = pair x
  let (_, count) = k 3
  let (_, b) = k (x * 2.0)
  break b
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
  break first[3] + second.length - 64
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
  break first[0] * 100 + second[0]
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
  break same - 1
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
    break total + c
  break total
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
  break a
`);
});

Deno.test("rebound runtime builders used at different layouts instance every link", async () => {
  await returnsArgument(`${cells}
entry const main = fn (x: U32) => do:
  let builder = empty ()
  builder := insert_cell x self
  let (_, first) = create builder (fn () => x)
  let (_, (_, fraction)) = create builder (fn () => (x, 1.5))
  break first
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
    break outcome
  break #App { initial: #Trace #[], scope, render: fn (frame: U32) => frame }
const note = fn (value: U32) => do:
  use current <- State.get ()
  let #Trace values = current
  break State.set (#Trace #[...values, value])
const with_render = fn render => fn app => do:
  let #App { initial, scope } = app
  break #App { initial, scope, render }
const initial = fn app => do:
  let #App { initial } = app
  break initial
const run = fn app => fn world => fn action => do:
  let #App { scope } = app
  break scope world action
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
  break render 2 frame
entry const main = fn (x: U32) => do:
  let app = with_render (fn (scale: U32) => fn (frame: U32) => do:
    use note frame
    break frame * scale) (empty ())
  let (trace, doubled) = run app (initial app) (fn () => render app x)
  let #Trace values = trace
  break doubled - x + values.length - 1
`);
});

// A := link built only from a promoted builder and closed arguments is
// closed too, so it keeps its evaluator value instead of serializing the
// promoted builder at a layout its own open uses leave unresolved.
Deno.test("rebinding links that read a promoted builder are promoted with it", async () => {
  await returnsArgumentWithMemory(`${app}
const render = fn app => fn frame => do:
  let #App { render } = app
  break render frame
entry const main = fn (x: U32) => do:
  let app = empty ()
  app := with_render (fn (frame: U32) => do:
    use note frame
    break frame + 1) self
  let (trace, next) = run app (initial app) (fn () => render app x)
  let #Trace values = trace
  break next + values.length - 2
`);
});

// A use that leaves only ambiguous variables open (no scheme quantifies
// them) observes nothing there, so the whole body stores them as a word and
// closes an ambiguous row tail as pure (issue #10). `boxed.length` leaves the
// scope's action result open; before this, `b` was serialized at an erased
// result and reported `ownership_unproved`.
const scoped = `
type B [w, s] is data = #B { initial: w, s: w -> s }
const empty = fn () => do:
  let scope = fn world => fn action => do:
    use result <- action ()
    break (world, result)
  break #B { initial: (), s: scope }
const run = fn b => fn action => do:
  let #B { initial, s } = b
  break s initial action
entry const memory = fn () -> Array U32 => #[]
`;

Deno.test("a generalized local read only for its length stores its ambiguous hole as a word", async () => {
  await returnsArgumentWithMemory(`${scoped}
entry const main = fn (x: U32) => do:
  let b = empty ()
  let (_, r) = run b (fn () => x)
  let boxed = #[b, b]
  break r + boxed.length - 2
`);
});

// The hole `#[b, b]` leaves open is `boxed`'s own quantified variable, and
// later uses read that storage at F32 and at an array. Word storage there
// would drop the array's retains; only the `.length` use's fresh variable is
// ambiguous, so `boxed` keeps one instance per layout.
Deno.test("a quantified hole read later at a heap type keeps one instance per layout", async () => {
  await returnsArgumentWithMemory(`${scoped}
entry const main = fn (x: U32) => do:
  let b = empty ()
  let (_, r) = run b (fn () => x)
  let boxed = #[b, b]
  let (_, fraction) = run boxed[0] (fn () => 1.5)
  let (_, values) = run boxed[1] (fn () => #[x, x + 1])
  break r + values[1] - values[0] + boxed.length - 3
`);
});

// `#[k, k]` reads the runtime-dependent `k` at an ambiguous hole. The
// promoting attempt keeps such a local undecided for a promotion that cannot
// happen, so it fails and the retry evaluates one instance per layout.
Deno.test("a runtime producer read at an ambiguous hole retries with one instance per layout", async () => {
  await returnsArgumentWithMemory(`
${pair}
entry const memory = fn () -> Array U32 => #[]
entry const main = fn (x: U32) => do:
  let k = pair x
  let (a, _) = k 1.5
  let n = #[k, k].length
  break a + n - 2
`);
});

// A closure captures `boxed`, so its quantified hole has no instance and
// stays open where `#[b, b]` serializes `b`. That hole is not ambiguous, so
// it still reports `ownership_unproved` instead of taking word storage.
Deno.test("a captured local whose quantified hole stays open still declines", async () => {
  await compileExpectedFailure(`${scoped}
entry const main = fn (x: U32) => do:
  let b = empty ()
  let (_, r) = run b (fn () => x)
  let boxed = #[b, b]
  let later = fn (y: U32) => do:
    let (_, values) = run boxed[1] (fn () => #[y, y])
    break values.length
  break r + boxed.length + later x - 4
`, "ownership_unproved");
});

// Ink's effect repro c1, reduced: no use applies the route callback, so its
// type variable and effect row stay ambiguous at `create`, which reads the
// systems whole. The promoted builders serialize it as a pure `U32 -> U32`.
Deno.test("promoted builders serialize a polymorphic callback no use applies", async () => {
  await returnsArgumentWithMemory(`${scoped}
type System [route, start] is data = #Route route | #Start start
type App [engine, system] is data = #App { engine: engine, systems: Array system }
const new_with = fn route => #App { engine: empty (), systems: #[#Route route, #Start (fn () => ())] }
const finalize = fn app => do:
  let #App { engine, systems } = app
  break #App { engine, systems }
const run_start = fn systems => fn () => do:
  for system in systems:
    use case system of
      #Start start => start ()
      _ => ()
const create = fn app => fn () => do:
  let #App { engine, systems } = app
  let (world, _) = run engine (run_start systems)
  break world
entry const main = fn (x: U32) => do:
  let builder = new_with (fn (e: u) => e)
  let application = finalize builder
  let world = create application ()
  break x
`);
});

// Which declarations quantify a variable is a property of the unit, so the
// unit's size never turns an ambiguous hole into a declined one. Two hundred
// padding declarations and twenty generalized locals each read only for
// their length once exhausted a per-body search budget and reported
// `ownership_unproved`; every hole still takes word storage.
Deno.test("a large unit still stores the ambiguous holes of its generalized locals as words", async () => {
  const padding = Array.from({ length: 200 }, (_, unit) => `type Pad${unit} is data = ${Array.from({ length: 8 }, (_, tag) => `#P${unit}x${tag}`).join(" | ")}`).join("\n");
  const locals = Array.from({ length: 20 }, (_, index) => `  let boxed${index} = #[b, b]`).join("\n");
  const lengths = Array.from({ length: 20 }, (_, index) => `boxed${index}.length`).join(" + ");
  await returnsArgumentWithMemory(`${scoped}${padding}
entry const main = fn (x: U32) => do:
  let b = empty ()
  let (_, r) = run b (fn () => x)
${locals}
  break r + ${lengths} - 40
`);
});

// Local storage decisions read a per-unit def-use index, so they no longer
// stop at 4,096 Core nodes. A thousand padding functions put each program
// above that size; both used to report `ownership_unproved`.
const padding = Array.from({ length: 1000 }, (_, index) => `const pad${index} = fn (x: U32) => @u32.add (@u32.mul x ${index + 1}) ${index}`).join("\n");

Deno.test("generalized local aliases in a unit above 4,096 nodes take the instance of their use", async () => {
  await returnsArgument(`${builder}${padding}
entry const main = fn (x: U32) => do:
  let b = empty ()
  let c = b
  let (_, result) = run c (fn () => x)
  break result
`);
});

Deno.test("ambiguous holes in a unit above 4,096 nodes take word storage", async () => {
  await returnsArgumentWithMemory(`${scoped}${padding}
entry const main = fn (x: U32) => do:
  let b = empty ()
  let (_, r) = run b (fn () => x)
  let boxed = #[b, b]
  break r + boxed.length - 2
`);
});
