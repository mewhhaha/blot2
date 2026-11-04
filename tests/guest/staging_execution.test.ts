import { compileAndRun, equal } from "./compile_helpers.ts";

Deno.test("staged member lookup finishes a constant before draining its dependents", async () => {
  await compileAndRun(`
type Box is data = $Box U32
const Box.get = func box => return case box of
  $Box value => value
const read = func value => return value.get
const first = read ($Box 40)
const second = @u32.add first 2
entry const answer = func () => return @u32.add first second
`, guest => equal(guest.call("answer", null), 82));
});

Deno.test("generic effect witnesses retain heterogeneous record storage after private proof", async () => {
  await compileAndRun(`
const apple = 0.0
type Pair is data = $Pair { zebra: U32, apple: F32 }
type State a is effect = { get: Unit -> a, set: a -> Unit }
const get = func (witness: p -> a) : a => return State.get ()
const state = @effect.state (State.get Pair) (State.set Pair) ($Pair { zebra: 42, apple: 1.5 })
entry const integer = func (value: U32) => return do:
  let (_, result) = do state:
    use State.set ($Pair { apple: 1.5, zebra: value })
    use current <- get $Pair
    break current.zebra
  break result
entry const floating = func (value: F32) => return do:
  let (_, result) = do state:
    use State.set ($Pair { apple: value, zebra: 42 })
    use current <- get $Pair
    break current.apple
  break result
`, guest => {
    for (const value of [0, 42, 0xffffffff]) equal(guest.call("integer", value), value);
    for (const value of [0, 1.5, -1.25, 1.23456789]) equal(guest.call("floating", value), Math.fround(value));
  });
});

Deno.test("curried pure members keep the ambient row through their returned function", async () => {
  await compileAndRun(`
effect Read: Unit -> U32
type Box is data = $Box U32
const Box.add: Box -> U32 -> U32 = func box => return func offset => return case box of
  $Box value => @u32.add value offset
const reader = @effect.provider Read (func () => return 2)
entry const answer = func () => return do reader:
  use offset <- Read ()
  break ($Box 40).add offset
`, guest => equal(guest.call("answer", null), 42));
});

Deno.test("nested State scopes retain independently typed captures and callback rows", async () => {
  await compileAndRun(`
type State a is effect = { get: Unit -> a, set: a -> Unit }
type Builder [world,scope] is data = $Builder { initial: world, scope: world -> scope }
const empty = func () => return do:
  let scope = func world => return func action => return do:
    use result <- action ()
    break (world,result)
  break $Builder { initial: (), scope }
const insert = func initial => return func builder => return do:
  let $Builder { initial: previous_initial, scope: previous_scope } = builder
  let scope = func world => return func action => return do:
    let (current,previous) = world
    use outcome <- @effect.run State.get State.set current (func () => return previous_scope previous action)
    let (next,(previous_next,result)) = outcome
    break ((next,previous_next),result)
  break $Builder { initial: (initial,previous_initial), scope }
const built = insert 42 (insert 1.5 (empty ()))
entry const answer = func () => return do:
  let $Builder { initial,scope } = built
  let (_,result) = scope initial (func () => return #[42])
  break result
`, guest => equal((guest.call("answer", null) as Uint32Array)[0], 42));
});

Deno.test("staged record closures survive value and layout side-table growth", async () => {
  const fields = 48;
  const declarations = Array.from({ length: fields }, (_, index) => `
type Cell${index} is data = $Cell${index} { value: U32 }
const make${index} = func (cell: Cell${index}) => return func (value: U32) => return @u32.add cell.value value`);
  const name = (index: number) => `f${String(index).padStart(3, "0")}`;
  const types = Array.from({ length: fields }, (_, index) => `${name(index)}: U32 -> U32`);
  const values = Array.from({ length: fields }, (_, index) =>
    `${name(index)}: make${index} ($Cell${index} { value: ${index} })`).reverse();
  await compileAndRun(`${declarations.join("\n")}
type Table is data = $Table { ${types.join(", ")} }
const staged = $Table { ${values.join(", ")} }
entry const answer = func (value: U32) => return @u32.add (staged.f000 value) (staged.f047 value)
`, guest => {
    for (let value = 0; value < 100; value++) equal(guest.call("answer", value), 2 * value + 47);
  });
});

Deno.test("exported function aliases and staged or initialized closures retain their values", async () => {
  await compileAndRun(`
const identity = func value => return value
entry const alias: U32 -> U32 = identity
const build = func base => return func value => return @u32.add base value
entry const captured = build 40
entry let initialized = build 20
type Box value is data = $Box value
const Box.pure = identity (func value => return $Box value)
const Box.bind = identity (func candidate => return func next => return case candidate of
  $Box value => next value)
entry const monadic = func () => return do:
  let $Box value = do (@do.monad Box):
    use value <- $Box 40
    break @u32.add value 2
  break value
`, guest => {
    for (let value = 0; value < 100; value++) {
      equal(guest.call("alias", value), value);
      equal(guest.call("captured", value), value + 40);
      equal(guest.call("initialized", value), value + 20);
      equal(guest.call("monadic", null), 42);
    }
  });
});

Deno.test("staged builders retain composed closures and static captures across calls", async () => {
  await compileAndRun(`
type Builder callback is data = $Builder { run: callback }
const add_step = func (amount: U32) => return func builder => return do:
  let $Builder { run: previous } = builder
  break $Builder { run: func (value: U32) => return @u32.add (previous value) amount }
const staged = do:
  let builder = $Builder { run: func value => return value }
  builder := add_step 10 self
  builder := add_step 20 self
  break builder
const unused = @panic "unreachable constant"
entry const answer = func (value: U32) : U32 => return do:
  let $Builder { run } = staged
  break run value
const worker = do:
  let base = 40
  break func (value: U32) => return @u32.add base value
entry const work = func (value: U32) : U32 => return worker value
`, guest => {
    for (let i = 0; i < 2000; i++) {
      equal(guest.call("answer", i), i + 30);
      equal(guest.call("work", i), i + 40);
    }
  });
});

Deno.test("unannotated staged builders retain independent integer and float evidence", async () => {
  await compileAndRun(`
type Builder callback is data = $Builder { run: callback }
const add_step = func amount => return func builder => return do:
  let $Builder { run: previous } = builder
  break $Builder { run: func value => return previous value + amount }
const staged = do:
  let builder = $Builder { run: func value => return value }
  builder := add_step 10 self
  builder := add_step 20 self
  break builder
const floating = do:
  let builder = $Builder { run: func value => return value }
  builder := add_step 1.5 self
  builder := add_step 2.5 self
  break builder
entry const answer = func () => return do:
  let $Builder { run } = staged
  break run 12
entry const float = func () => return do:
  let $Builder { run } = floating
  break run 8.0
`, guest => {
    equal(guest.call("answer", null), 42);
    equal(guest.call("float", null), 12);
  });
});

Deno.test("retained pure checkpoints execute beneath ambient effects", async () => {
  const sources = [
`
type State a is effect = { get: Unit -> a, set: a -> Unit }
type Builder [world,scope,checkpoint] is data = $Builder { initial: world, scope: world -> scope, checkpoint: checkpoint }
const empty = func () => return do:
  let scope = func world => return func action => return do:
    use result <- action ()
    break (world,result)
  break $Builder { initial: (), scope, checkpoint: func () => return () }
const insert = func initial => return func builder => return do:
  let $Builder { initial: previous_initial, scope: previous_scope, checkpoint } = builder
  let scope = func world => return func action => return do:
    let (current,previous) = world
    use outcome <- @effect.run State.get State.set current (func () => return previous_scope previous action)
    let (next,(previous_next,result)) = outcome
    break ((next,previous_next),result)
  break $Builder { initial: (initial,previous_initial), scope, checkpoint }
const snapshot = func initial => return func builder => return do:
  let $Builder { checkpoint: previous_checkpoint } = builder
  let $Builder { initial: previous_initial, scope: previous_scope } = insert initial builder
  let checkpoint = func () => return do:
    use previous_checkpoint ()
    use current <- State.get ()
    use State.set (@u32.add current 1)
    break ()
  break $Builder { initial: previous_initial, scope: previous_scope, checkpoint }
const built = snapshot 41 (empty ())
entry const answer = func () => return do:
  let $Builder { initial,scope,checkpoint } = built
  let (world,_) = scope initial checkpoint
  let (current,_) = world
  break current
`,
`
effect Read: Unit -> U32
effect Touch: U32 -> Unit
const previous: Unit -> Unit = func () => return ()
const extend = func previous => return func () => return do:
  use previous ()
  use value <- Read ()
  use Touch value
  break ()
const checkpoint = extend previous
const reader = @effect.provider Read (func () => return 42)
const touch = @effect.provider Touch (func value => return ())
const run = func () => return do touch:
  use checkpoint ()
  break 42
entry const answer = func () => return do reader:
  break run ()
`,
  ];
  for (const source of sources) {
    await compileAndRun(source, guest => {
      for (let iteration = 0; iteration < 5; iteration++) equal(guest.call("answer", null), 42);
    });
  }
});

Deno.test("the source ECS example stages heterogeneous worlds and executes their scoped callbacks", async () => {
  const source = await Deno.readTextFile(new URL("../../examples/ecs.blot", import.meta.url));
  await compileAndRun(source, guest => {
    for (let repeat = 0; repeat < 3; repeat++) {
      for (const ticks of [0, 1, 2, 10, 100]) {
        equal(guest.call("run", ticks), 33 + 6 * ticks);
        equal(guest.call("ghost_count", ticks), ticks === 0 ? 0 : 4);
      }
      equal(guest.call("snapshot", null), 6);
    }
  }, { prelude: "std/prelude.blot", stdRoot: "std" });
});

Deno.test("selected binary methods retain curried results and their invocation effects", async () => {
  await compileAndRun(`
effect Read: Unit -> F32
type Box is data = $Box F32
type Deferred is data = $Deferred F32
type Scale is data = $Scale F32
const Box.mix = func left => return func right => return func weight => return do:
  let $Box base = left
  break @f32.add base (@f32.mul right weight)
const Deferred.mix = func left => return do:
  let $Deferred base = left
  use offset <- Read ()
  break func right => return func weight => return @f32.add (@f32.add base offset) (@f32.mul right weight)
const Scale.mix = func left => return func right => return func weight => return do:
  let $Scale scale = right
  break @f32.add left (@f32.mul scale weight)
const mix = func left => return func right => return @type.call "mix" left right
const reader = @effect.provider Read (func () => return 2.0)
entry const nominal = func (value: F32) => return mix ($Box value) 2.0 1.0
entry const partial = func (value: F32) => return do:
  let blend = mix ($Box value) 4.0
  break blend 0.5
entry const deferred = func (value: F32) => return do reader:
  break mix ($Deferred value) 4.0 0.5
entry const right = func (value: F32) => return mix value ($Scale 2.0) 1.0
type Live is data = $Live F32
const Live.mix = func left => return func right => return func () => return do:
  let $Live base = left
  use value <- Read ()
  break @f32.add base (@f32.add right value)
const earlier = @effect.provider Read (func () => return 100.0)
entry const live = func (value: F32) => return do:
  let callback = do earlier:
    break mix ($Live value) 0.0
  break do reader:
    break callback ()
`, guest => {
    for (let repeat = 0; repeat < 3; repeat++) {
      for (const value of [0, 2, 40, 42, -2, 1.5]) {
        for (const name of ["nominal", "partial", "right", "live"]) equal(guest.call(name, value), value + 2);
        equal(guest.call("deferred", value), value + 4);
      }
    }
  });
});

Deno.test("the prelude lerp method returns a callable after binary selection", async () => {
  await compileAndRun(`
entry const answer = func (left: F32) => return lerp left 42.0 0.5
entry const partial = func () => return do:
  let blend = lerp 10.0 30.0
  break blend 0.75
`, guest => {
    for (let repeat = 0; repeat < 3; repeat++) {
      for (const value of [0, 2, 40, 42, -2, 1.5]) equal(guest.call("answer", value), value + (42 - value) * 0.5);
      equal(guest.call("partial", null), 25);
    }
  }, { prelude: "std/prelude.blot" });
});
