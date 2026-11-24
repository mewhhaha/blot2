import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

const stdRoot = new URL("../../std", import.meta.url).pathname;

Deno.test("Phase 1 executable controls: k==1 tuple Box, escape-safe nested spark, and plain-element scratch release", async () => {
  await compileAndRun(
    `type Box is data = $Box { p: (U32, U32) }

func unwrap_pos (b: Box): U32 => return case b of
  $Box (a, c) => @u32.add a c

entry func test_k1_box (x: U32): U32 =>
  let mk = $Box
  let b1 = $Box (x, 10)
  let b2 = mk (x, 4)
  return @u32.add (unwrap_pos b1) (unwrap_pos b2)

entry func test_nested_spark (): Array U32 =>
  let rows = spark #[#[x, @u32.add x 1] | x <- 0..2]
  return #[rows[0][0], rows[0][1], rows[1][0], rows[1][1]]

func scratch_iter (x: U32): U32 =>
  let tmp = @array.fill 256 x
  let acc = 0
  for i in 0..tmp.length:
    acc := @u32.add self tmp[i]
  return acc

entry func test_scratch_spark (n: U32): Array U32 => return spark #[scratch_iter x | x <- 0..n]
`,
    (guest) => {
      // (5 + 10) + (5 + 4) = 24
      equal(guest.call("test_k1_box", 5), 24);
      equal(String(guest.call("test_nested_spark", null)), "0,1,1,2");
      const sums = guest.call("test_scratch_spark", 64) as Uint32Array;
      equal(sums.length, 64);
      equal(sums[0], 0);
      equal(sums[1], 256);
      equal(sums[63], 63 * 256);
    },
  );
});

Deno.test("Phase 1 entry kernel / entry process syntax, represented handles, visibility, wire types, and opacity bans", async () => {
  // Positive: private entry func preserved, dynamic Kernel handle selection, stateless & prepared kernel, process
  await compileAndRun(
    `type Query is data = $Query { x: U32, y: F32 }
type Ctx is data = $Ctx { scale: U32, weights: #[U32] }
type PState is data = $PState { total: U32, log: #[+U32] }

func prep_ctx (w: #[U32]): Ctx => return $Ctx { scale: 2, weights: @storage.copy w }
func run_item (c: Ctx) -> (q: Query): U32 => return @u32.mul c.scale q.x
func run_item_alt (c: Ctx) -> (q: Query): U32 => return @u32.add c.scale q.x

func proc_init (seed: U32): PState =>
  let log: #[+U32] = #[seed]
  return $PState { total: seed, log: log }

func proc_step (st: own PState) -> (cmd: U32): (PState, U32) =>
  let $PState { total, log } = st
  let next = @u32.add total cmd
  return ($PState { total: next, log: log }, next)

private entry func keep_private (x: U32): U32 => return @u32.add x 1
entry kernel func double_u32 (x: U32): U32 => return @u32.mul x 2
entry kernel plan_a: Kernel [#[U32], Query, U32] = { prepare: prep_ctx, run: run_item }
entry kernel plan_b: Kernel [#[U32], Query, U32] = { prepare: prep_ctx, run: run_item_alt }
entry process counter: Process [U32, U32, U32] = { init: proc_init, step: proc_step }

func select_kernel (flag: Bool): Kernel [#[U32], Query, U32] => return if flag then plan_a else plan_b
entry func ok (x: U32): U32 =>
  let _ = select_kernel true
  let _ = counter
  let _ = double_u32
  return x
`,
    (guest) => {
      equal(guest.call("ok", 7), 7);
      equal(guest.call("keep_private", 7), 8);
    },
  );

  // Reject $Kernel / $Process forging outside std/prelude
  await compileExpectedFailure(
    `entry func forge () => return $Process 0\n`,
    "unknown_value",
  );

  // Reject private entry kernel / private entry process
  await compileExpectedFailure(
    `private entry kernel func bad (x: U32): U32 => return x\n`,
    "GPU_FRONTEND_SYNTAX_ERROR",
  );
  await compileExpectedFailure(
    `func i (x: U32): U32 => return x
func s (st: own U32) -> (c: U32): (U32, U32) => return (st, c)
private entry process bad: Process [U32, U32, U32] = { init: i, step: s }
`,
    "GPU_FRONTEND_SYNTAX_ERROR",
  );

  // Reject non-PersistentSafe process state (closure inside State)
  await compileExpectedFailure(
    `func i (_: U32): { f: Unit -> Unit } => return { f: func () => return () }
func s (st: own { f: Unit -> Unit }) -> (_: U32): ({ f: Unit -> Unit }, U32) => return (st, 0)
entry process bad_state: Process [U32, U32, U32] = { init: i, step: s }
`,
    "kernel_type",
  );

  // Reject opaque wire types (even in defining module)
  await compileExpectedFailure(
    `type Secret is opaque = U32
entry kernel func leak (x: Secret): U32 => return 0
`,
    "kernel_type",
  );

  // Reject non-FlatNumeric wire item (variable array as Item)
  await compileExpectedFailure(
    `entry kernel func bad_item (x: #[U32]): U32 => return x.length\n`,
    "kernel_type",
  );

  // Reject effectful kernel / process
  await compileExpectedFailure(
    `effect Ping: Unit -> U32
func p (w: U32): U32 ! { Ping } => return Ping ()
func r (c: U32) -> (x: U32): U32 => return x
entry kernel k: Kernel [U32, U32, U32] = { prepare: p, run: r }
`,
    "kernel_effectful",
  );

  // Reject non-function callable (value initializer returning a function, not a named function Body)
  await compileExpectedFailure(
    `func make_fn (): U32 -> U32 => return func x => return x
const not_a_func: U32 -> U32 = make_fn ()
func r (c: U32) -> (x: U32): U32 => return x
entry kernel k: Kernel [U32, U32, U32] = { prepare: not_a_func, run: r }
`,
    "kernel_callable",
  );

  // Reject `entry func` / `export` callables as kernel prepare/run or process init/step
  // (host entries are exempt from `ownedResult` and could otherwise leak a static global into `own State`).
  await compileExpectedFailure(
    `const pool: #[U32] = #[10, 20, 30]
entry func p_init (_: U32): #[U32] => return pool
func p_step (s: own #[U32]) -> (cmd: U32): (#[U32], U32) =>
  s[0] := cmd
  return (s, s[0])
entry process p: Process [U32, U32, U32] = { init: p_init, step: p_step }
`,
    "kernel_callable",
  );
  await compileExpectedFailure(
    `entry func prep (w: U32): U32 => return w
func r (c: U32) -> (x: U32): U32 => return @u32.add c x
entry kernel k: Kernel [U32, U32, U32] = { prepare: prep, run: r }
`,
    "kernel_callable",
  );

  // Reject shallow `@storage.copy` mutating nested inner arrays on composites or shared nested arrays
  await compileExpectedFailure(
    `const nested: #[#[U32]] = #[#[1, 2]]
entry func bad (): U32 =>
  let c = copy { box: nested }
  c.box[0][0] := 99
  return nested[0][0]
`,
    "aliased_update",
  );
  await compileExpectedFailure(
    `entry func bad (): U32 =>
  let s: *#[#[U32]] = freeze #[#[1, 2]]
  let c: #[#[U32]] = copy s
  c[0][0] := 99
  return s[0][0]
`,
    "aliased_update",
  );
  await compileExpectedFailure(
    `type Boxed is data = $Boxed { rows: #[#[U32]] }
const nested: #[#[U32]] = #[#[1, 2]]
entry func bad (): U32 =>
  let c = copy ($Boxed { rows: nested })
  c.rows[0][0] := 99
  return nested[0][0]
`,
    "aliased_update",
  );

  // Reject @flat.* outside std/
  await compileExpectedFailure(
    `entry kernel func k (x: U32): U32 => return x
entry func bad (): U32 => return @flat.kernel_id k
`,
    "std_only_intrinsic",
  );
});

Deno.test("Law #3 (a)-(b): indirect callee, closures, relayed closures, fresh spark source, process cross-turn global, and curried callbacks", async () => {
  // (a) fill(dst) pushing thunk mutating pool into caller-owned dst + dst[0] () (with executable control)
  const fillDecls = `const pool: #[+U32] = #[1, 2, 3]
func fill (dst: #[+(Unit -> Unit)]): Unit =>
  @storage.push dst (func () => do:
    @storage.push pool 99
    return ())
  return ()
func run_fill (): U32 =>
  let dst: #[+(Unit -> Unit)] = #[]
  fill dst
  dst[0] ()
  return pool[@u32.sub pool.length 1]
`;
  await compileAndRun(
    fillDecls + `entry func ctrl (): U32 => return run_fill ()\n`,
    (guest) => equal(guest.call("ctrl", null), 99),
  );
  await compileExpectedFailure(
    fillDecls +
      `entry func bad (xs: #[U32]): #[U32] => return spark #[run_fill () | x <- xs]\n`,
    "spark_mutates_capture",
  );

  // (b1) Control: relayed closure & returned named function actually mutate pool outside spark/kernel
  await compileAndRun(
    `const pool: #[+U32] = #[1, 2, 3]
func relay (f: Unit -> Unit): Unit -> Unit => return f
func wrap (f: Unit -> Unit): #[Unit -> Unit] => return #[f]
func touch_pool (): Unit =>
  @storage.push pool 7
  return ()
func pick (): Unit -> Unit => return touch_pool
entry func run_ctrl (): U32 =>
  let h = relay (func () => do:
    @storage.push pool 7
    return ())
  h ()
  return pool[@u32.sub pool.length 1]
entry func run_pick (): U32 =>
  (pick ()) ()
  return pool[@u32.sub pool.length 1]
`,
    (guest) => {
      equal(guest.call("run_ctrl", null), 7);
      equal(guest.call("run_pick", null), 7);
    },
  );

  // (b2) Relayed closure 1-hop, 2-hop, closure-in-array, and returned named function inside spark
  for (
    const snippet of [
      `  let h = relay (func () => do:
    @storage.push pool 7
    return ())
  h ()`,
      `  let h = relay (relay (func () => do:
    @storage.push pool 7
    return ()))
  h ()`,
      `  let arr = wrap (func () => do:
    @storage.push pool 7
    return ())
  arr[0] ()`,
      `  (pick ()) ()`,
    ]
  ) {
    await compileExpectedFailure(
      `const pool: #[+U32] = #[1, 2, 3]
func relay (f: Unit -> Unit): Unit -> Unit => return f
func wrap (f: Unit -> Unit): #[Unit -> Unit] => return #[f]
func touch_pool (): Unit =>
  @storage.push pool 7
  return ()
func pick (): Unit -> Unit => return touch_pool
func body (x: U32): U32 =>
${snippet}
  return x
entry func bad (xs: #[U32]): #[U32] => return spark #[body x | x <- xs]
`,
      "spark_mutates_capture",
    );
  }

  // (b3) Fresh-literal spark source mutation & outer-array spark source mutation
  await compileExpectedFailure(
    `func touch (row: #[+U32]): U32 =>
  @storage.push row 1
  return row[0]
entry func bad (): #[U32] =>
  let seed: #[+U32] = #[0]
  return spark #[touch row | row <- #[seed]]
`,
    "spark_mutates_capture",
  );
  await compileExpectedFailure(
    `func touch (row: #[+U32]): U32 =>
  @storage.push row 1
  return row[0]
entry func bad (): #[U32] =>
  let seed: #[+U32] = #[0]
  let xs: #[#[+U32]] = #[seed]
  return spark #[touch row | row <- xs]
`,
    "spark_mutates_capture",
  );

  // (b4) entry process global mutation, mutable-global read, & Config/Cmd mutation vs @storage.copy accepted
  await compileExpectedFailure(
    `const shared_arr: #[+U32] = #[1, 2, 3]
func p_init (_: U32): #[U32] =>
  @storage.push shared_arr 99
  return #[0]
func p_step (s: own #[U32]) -> (cmd: U32): (#[U32], U32) =>
  s[0] := cmd
  let v = s[0]
  return (s, v)
entry process bad: Process [U32, U32, U32] = { init: p_init, step: p_step }
`,
    "process_mutates_global",
  );
  await compileExpectedFailure(
    `const shared_arr: #[+U32] = #[1, 2, 3]
func p_init (_: U32): #[U32] => return #[0]
func p_step (s: own #[U32]) -> (cmd: U32): (#[U32], U32) =>
  @storage.push shared_arr cmd
  return (s, shared_arr[0])
entry process bad2: Process [U32, U32, U32] = { init: p_init, step: p_step }
`,
    "process_mutates_global",
  );
  // Flat-numeric `entry process` Config/Cmd inputs are borrowed `#[U32]`:
  // Phase 5 enforces `@simd.store` ownership at lowering (`aliased_update`)
  // before purity even runs, closing in-place mutation of borrowed wire inputs.
  await compileExpectedFailure(
    `func p_init (cfg: #[U32]): #[U32] =>
  let _ = @simd.store cfg 0 (99, 0, 0, 0)
  return #[0]
func p_step (s: own #[U32]) -> (cmd: U32): (#[U32], U32) => return (s, cmd)
entry process bad_cfg: Process [#[U32], U32, U32] = { init: p_init, step: p_step }
`,
    "aliased_update",
  );
  await compileExpectedFailure(
    `func p_init (_: U32): #[U32] => return #[0]
func p_step (s: own #[U32]) -> (cmd: #[U32]): (#[U32], U32) =>
  let _ = @simd.store cmd 0 (99, 0, 0, 0)
  return (s, cmd[0])
entry process bad_cmd: Process [U32, #[U32], U32] = { init: p_init, step: p_step }
`,
    "aliased_update",
  );
  await compileAndRun(
    `const shared_arr: #[U32] = #[1, 2, 3]
func p_init (_: U32): #[U32] => return @storage.copy shared_arr
func p_step (s: own #[U32]) -> (cmd: U32): (#[U32], U32) =>
  s[0] := cmd
  let v = s[0]
  return (s, v)
entry process good: Process [U32, U32, U32] = { init: p_init, step: p_step }
entry func ok (): U32 => return 1
`,
    (guest) => {
      equal(guest.call("ok", null), 1);
    },
  );

  // (b5) Curried 2-argument higher-order callback helper (with_search-shaped)
  const curriedBase = `func with_search (f: U32 -> U32 -> U32) -> (a: U32) -> (b: U32): U32 =>
  let step = f a
  return step b
func prep (w: #[U32]): #[+U32] =>
  let out: #[+U32] = #[w[0]]
  return out
`;
  await compileExpectedFailure(
    curriedBase + `func bad_run (ctx: #[+U32]) -> (x: U32): U32 =>
  let out: #[+U32] = #[0]
  return with_search (func a -> b => do:
    @storage.push ctx a
    @storage.push out b
    return out[@u32.sub out.length 1]) x 1
entry kernel k: Kernel [#[U32], U32, U32] = { prepare: prep, run: bad_run }
`,
    "kernel_mutates_context",
  );
  await compileAndRun(
    curriedBase + `func good_run (ctx: #[+U32]) -> (x: U32): U32 =>
  let out: #[+U32] = #[0]
  return with_search (func a -> b => do:
    @storage.push out (@u32.add ctx[0] (@u32.add a b))
    return out[@u32.sub out.length 1]) x 1
entry kernel k: Kernel [#[U32], U32, U32] = { prepare: prep, run: good_run }
entry func ok (): U32 => return 1
`,
    (guest) => {
      equal(guest.call("ok", null), 1);
    },
  );
});

Deno.test("Law #3 (c): rebinding, branch merge, loops, updatePath, index expr, trailing field store, nominal/record patterns, getters, and self", async () => {
  const mkSpark = (extraDecls: string, body: string) => `const pool: #[+U32] = #[1, 2, 3]
func push_grow (dst: #[+U32]) -> (v: U32): Unit =>
  let box = #[dst]
  @storage.push box[0] v
  return ()
${extraDecls}
func body (x: U32): U32 =>
  let scratch: #[+U32] = #[0, 0]
  ${body}
  return x
entry func bad (xs: #[U32]): #[U32] => return spark #[body x | x <- xs]
`;

  const cases: [string, string, string][] = [
    ["simple rebinding", "", `let selected = scratch\n  selected := pool\n  @storage.push selected 99`],
    ["branch merge rebinding", "", `let selected = scratch\n  if x == 1:\n    selected := pool\n  @storage.push selected 99`],
    ["multi-scrutinee guarded case", "", `let target = case x, pool of\n    0, arr if x == 0 => arr\n    _, _ => scratch\n  @storage.push target 99`],
    ["for-in loop element", "", `for row in #[pool]:\n    @storage.push row 42`],
    ["for-in destructured tuple", "", `for (_, b) in #[(scratch, pool)]:\n    @storage.push b 42`],
    ["loop carry backedge", "", `let selected: #[+U32] = #[0]\n  for i in 0..2:\n    push_grow selected i\n    selected := pool`],
    ["loop carry break", "", `let selected = scratch\n  for i in 0..2:\n    selected := pool\n    break\n  @storage.push selected 99`],
    ["loop carry continue", "", `let selected: #[+U32] = #[0]\n  for i in 0..2:\n    if i == 0:\n      selected := pool\n      continue\n    push_grow selected 99`],
    ["plain record field rebind", "", `let b0: #[+U32] = #[0]\n  let r = { a: scratch, b: b0 }\n  r.b := pool\n  push_grow r.b 98`],
    [
      "nominal field rebind",
      "type Box is data = $Box { a: #[+U32], b: #[+U32] }",
      `let b0: #[+U32] = #[0]\n  let b = $Box { a: scratch, b: b0 }\n  b.b := pool\n  let _ = case b of\n    $Box { a: _, b: q } => do:\n      push_grow q 99\n      break ()`,
    ],
    [
      "index-expression mutation",
      `func mutate_idx (p: #[+U32]): U32 =>\n  @storage.push p 77\n  return 0`,
      `scratch[mutate_idx pool] := 42`,
    ],
    ["trailing-field store on record array", "", `let b0: #[+U32] = #[0]\n  let arr = #[{ a: scratch, b: b0 }]\n  arr[0].b := pool\n  push_grow arr[0].b 99`],
    [
      "trailing-field store on nominal array (named)",
      "type Row is data = $Row { a: #[+U32], b: #[+U32] }",
      `let b0: #[+U32] = #[0]\n  let rows = #[$Row { a: scratch, b: b0 }]\n  rows[0].b := pool\n  let _ = case rows[0] of\n    $Row { a: _, b } => do:\n      push_grow b 99\n      break ()`,
    ],
    [
      "trailing-field store on nominal array (positional)",
      "type Row is data = $Row { a: #[+U32], b: #[+U32] }",
      `let b0: #[+U32] = #[0]\n  let rows = #[$Row { a: scratch, b: b0 }]\n  rows[0].b := pool\n  let _ = case rows[0] of\n    $Row (_, b) => do:\n      push_grow b 99\n      break ()`,
    ],
    ["named record destructuring", "", `let { a: _, b } = { a: scratch, b: pool }\n  @storage.push b 99`],
    [
      "1-field positional $One field proj",
      "type One is data = $One { value: #[+U32] }",
      `let b = $One pool\n  @storage.push b.value 99`,
    ],
    [
      "1-field positional $One match",
      "type One is data = $One { value: #[+U32] }",
      `let b = $One pool\n  let _ = case b of\n    $One v => do:\n      @storage.push v 99\n      break ()`,
    ],
    [
      "1-field tuple-typed $TupBox proj",
      "type TupBox is data = $TupBox { p: (#[+U32], #[+U32]) }",
      `let b = $TupBox (scratch, pool)\n  let (_, q) = b.p\n  @storage.push q 99`,
    ],
    [
      "1-field tuple-typed $TupBox positional match",
      "type TupBox is data = $TupBox { p: (#[+U32], #[+U32]) }",
      `let b = $TupBox (scratch, pool)\n  let _ = case b of\n    $TupBox (_, q) => do:\n      @storage.push q 99\n      break ()`,
    ],
    [
      "1-field tuple-typed $TupBox first-class ctor",
      "type TupBox is data = $TupBox { p: (Unit -> Unit, Unit -> Unit) }\nfunc nop (): Unit => return ()\nfunc touch_p (): Unit =>\n  @storage.push pool 99\n  return ()",
      `let mk = $TupBox\n  let b = mk (nop, touch_p)\n  let (_, q) = b.p\n  q ()`,
    ],
    [
      "multi-field positional $Pair",
      "type Pair is data = $Pair { a: #[+U32], b: #[+U32] }",
      `let p = $Pair (scratch, pool)\n  @storage.push p.b 99`,
    ],
    [
      "multi-field positional $Pair first-class ctor",
      "type Pair is data = $Pair { a: Unit -> Unit, b: Unit -> Unit }\nfunc nop (): Unit => return ()\nfunc touch_p (): Unit =>\n  @storage.push pool 99\n  return ()",
      `let mk = $Pair\n  let p = mk (nop, touch_p)\n  p.b ()`,
    ],
    [
      "non-pool module value getter",
      `func mutate_pool (): U32 =>\n  @storage.push pool 5\n  return 5\nconst outer: { number: U32 } = { number: mutate_pool () }`,
      `let _ = outer.number`,
    ],
    [
      "receiver-only method projection",
      `type Recv is data = $Recv U32\nfunc Recv.touch (_: Recv): U32 =>\n  @storage.push pool 8\n  return 8`,
      `let r = $Recv x\n  let _ = r.touch`,
    ],
    ["chained-index nested array store", "", `let wrapper = #[pool]\n  @storage.push wrapper[0] 99`],
    ["chained-index record field array store", "", `let a = #[{ b: pool }]\n  @storage.push a[0].b 99`],
    [
      "store-side self mutation on index store",
      `func mutate_self (arr: #[+U32]): #[+U32] =>\n  @storage.push arr 11\n  return @storage.copy arr`,
      `let holder = #[pool]\n  holder[0] := mutate_self self`,
    ],
    [
      "store-side self mutation on field rebind",
      `func mutate_self (arr: #[+U32]): #[+U32] =>\n  @storage.push arr 11\n  return @storage.copy arr`,
      `let box = { arr: pool }\n  box.arr := mutate_self self`,
    ],
  ];

  for (const [label, extra, body] of cases) {
    try {
      await compileExpectedFailure(
        mkSpark(extra, body),
        "spark_mutates_capture",
      );
    } catch (e) {
      throw new Error(`Law #3(c) case '${label}' failed: ${e}`);
    }
  }
});

Deno.test("Law #3 (d): ownership-clean with-cell, state_provider, stored op, and nested predecessor-handler effect witnesses", async () => {
  // 1. with-cell post-block alias via call_op () (mutating thunk is 100% ownership-clean!)
  const withCellDecls = `const pool: #[+U32] = #[1, 2, 3]
type SetSlot is effect = { set: (Unit -> Unit) -> Unit }
func call_op (): Unit ! { SetSlot } =>
  use SetSlot.set (func () => do:
    @storage.push pool 77
    return ())
  return ()
func run_with_cell (): U32 =>
  let slot: Unit -> Unit = func () => return ()
  with SetSlot = { set: func f => slot := f }:
    use call_op ()
  slot ()
  return pool[@u32.sub pool.length 1]
`;
  await compileAndRun(
    withCellDecls + `entry func ctrl (): U32 => return run_with_cell ()\n`,
    (guest) => equal(guest.call("ctrl", null), 77),
  );
  await compileExpectedFailure(
    withCellDecls +
      `entry func bad (xs: #[U32]): #[U32] => return spark #[run_with_cell () | x <- xs]\n`,
    "spark_mutates_capture",
  );

  // 2. handle / state_provider final-state tuple alias via call_set_pool ()
  const stateProvDecls = `const pool: #[+U32] = #[1, 2, 3]
effect GetS: Unit -> (Unit -> Unit)
effect PutS: (Unit -> Unit) -> Unit
func call_set_pool (): Unit ! { PutS } => return PutS (func () => do:
  @storage.push pool 88
  return ())
func run_state_prov (): U32 =>
  let (final_st, _) = do @effect.state GetS PutS (func () => return ()):
    use _ <- call_set_pool ()
    break 0
  final_st ()
  return pool[@u32.sub pool.length 1]
`;
  await compileAndRun(
    stateProvDecls + `entry func ctrl (): U32 => return run_state_prov ()\n`,
    (guest) => equal(guest.call("ctrl", null), 88),
  );
  await compileExpectedFailure(
    stateProvDecls +
      `entry func bad (xs: #[U32]): #[U32] => return spark #[run_state_prov () | x <- xs]\n`,
    "spark_mutates_capture",
  );

  // 3. Stored first-class effect operation invoked under a later handler
  const storedOpDecls = `const pool: #[+U32] = #[1, 2, 3]
effect Fire: Unit -> Unit
func touch_pool (_: Unit): Unit =>
  @storage.push pool 66
  return ()
func run_stored_op (): U32 =>
  let f = Fire
  let _ = do @effect.provider Fire touch_pool:
    use f ()
    break ()
  return pool[@u32.sub pool.length 1]
`;
  await compileAndRun(
    storedOpDecls + `entry func ctrl (): U32 => return run_stored_op ()\n`,
    (guest) => equal(guest.call("ctrl", null), 66),
  );
  await compileExpectedFailure(
    storedOpDecls +
      `entry func bad (xs: #[U32]): #[U32] => return spark #[run_stored_op () | x <- xs]\n`,
    "spark_mutates_capture",
  );

  // 4. Nested with handler whose inner handler invokes Op () executing predecessor outer handler
  const nestedWithDecls = `const pool: #[+U32] = #[1, 2, 3]
type Bump is effect = { bump: Unit -> Unit }
func touch_pool (): Unit =>
  @storage.push pool 55
  return ()
func run_nested_with (): U32 =>
  with Bump = { bump: func () => touch_pool () }:
    with Bump = { bump: func () => use Bump.bump () }:
      use Bump.bump ()
  return pool[@u32.sub pool.length 1]
`;
  await compileAndRun(
    nestedWithDecls + `entry func ctrl (): U32 => return run_nested_with ()\n`,
    (guest) => equal(guest.call("ctrl", null), 55),
  );
  await compileExpectedFailure(
    nestedWithDecls +
      `entry func bad (xs: #[U32]): #[U32] => return spark #[run_nested_with () | x <- xs]\n`,
    "spark_mutates_capture",
  );
});

Deno.test("Law #3 (e)-(i): array.slice, pop, append/prepend, spreads, nested fresh, non-array copy, and external mutation of const pool", async () => {
  // (e) array.slice / @array.generate passed into named helper write_first
  await compileExpectedFailure(
    `import * as array from "std/array"
const pool: #[+U32] = #[1, 2, 3]
func write_first (rows: #[#[+U32]]): U32 =>
  @storage.push rows[0] 99
  return rows[0][0]
func body (_: U32): U32 =>
  let rows = array.slice 0 1 #[pool]
  return write_first rows
entry func bad (xs: #[U32]): #[U32] => return spark #[body x | x <- xs]
`,
    "spark_mutates_capture",
    undefined,
    { stdRoot },
  );

  // (f) @storage.pop returning a nested owner subsequently mutated
  await compileExpectedFailure(
    `const pool: #[+U32] = #[1, 2, 3]
func body (x: U32): U32 =>
  let stack: #[~#[+U32]] = #[pool]
  let popped = @storage.pop stack
  @storage.push popped 99
  return x
entry func bad (xs: #[U32]): #[U32] => return spark #[body x | x <- xs]
`,
    "spark_mutates_capture",
  );

  // (h) append, prepend, mixed spread, single-spread identity, relay-wrapped make, fill_nested
  for (
    const [label, body] of [
      ["append", `let seed: #[+U32] = #[0]\n  let ys = @array.append #[seed] pool\n  @storage.push ys[1] 99`],
      ["prepend", `let seed: #[+U32] = #[0]\n  let ys = @array.prepend #[seed] pool\n  @storage.push ys[0] 99`],
      ["mixed spread", `let seed: #[+U32] = #[0]\n  let ys = #[...#[seed], pool]\n  @storage.push ys[1] 99`],
      ["relay-wrapped make", `let ys = relay_make pool\n  @storage.push ys[0][0] 99`],
      ["fill_nested", `let dst: #[+(Unit -> Unit)] = #[]\n  fill_nested dst pool\n  dst[0] ()`],
    ]
  ) {
    try {
      await compileExpectedFailure(
        `const pool: #[+U32] = #[1, 2, 3]
func make_nested (p: a): #[#[a]] => return #[#[p]]
func relay_make (p: a): #[#[a]] => return make_nested p
func fill_nested (dst: #[+(Unit -> Unit)]) -> (p: #[+U32]): Unit =>
  @storage.push dst (func () => do:
    let nested = #[p]
    @storage.push nested[0] 99
    return ())
  return ()
func body (x: U32): U32 =>
  ${body}
  return x
entry func bad (xs: #[U32]): #[U32] => return spark #[body x | x <- xs]
`,
        "spark_mutates_capture",
      );
    } catch (e) {
      throw new Error(`Law #3(h) case '${label}' failed: ${e}`);
    }
  }
  await compileExpectedFailure(
    `const pool: #[+U32] = #[1, 2, 3, 4]
func push_grow (dst: #[+U32]) -> (v: U32): Unit =>
  @storage.push dst v
  return ()
func body (x: U32): U32 =>
  let ys = #[...#[pool]]
  push_grow ys[0] 99
  return x
entry func bad (xs: #[U32]): #[U32] => return spark #[body x | x <- xs]
`,
    "spark_mutates_capture",
  );

  // (i) non-array @storage.copy forwarding descriptor & external entry mutating const pool
  await compileExpectedFailure(
    `type Holder is data = $Holder { arr: #[U32] }
func body (sw: *Holder) -> (x: U32): U32 =>
  let r: Holder = copy sw
  let _ = @simd.store r.arr 0 (99, 0, 0, 0)
  return x
entry func bad (xs: #[U32]): #[U32] =>
  let sw: *Holder = freeze ($Holder { arr: #[1, 2, 3, 4] })
  return spark #[body sw x | x <- xs]
`,
    "spark_mutates_capture",
  );

  // (i2) Op.ref (`&pool`) + `@storage.load` tracks the referenced storage into purity!
  await compileExpectedFailure(
    `const pool: #[+U32] = #[1, 2, 3]
func push_grow (dst: #[+U32]) -> (v: U32): Unit =>
  @storage.push dst v
  return ()
func body (x: U32): U32 =>
  let r = &pool
  let p = @storage.load r
  push_grow p 99
  return x
entry func bad (xs: #[U32]): #[U32] => return spark #[body x | x <- xs]
`,
    "spark_mutates_capture",
  );

  // External entry mutating const pool -> NOT deeply immutable -> kernel read rejected
  await compileExpectedFailure(
    `const table: #[+U32] = #[1, 2, 3]
entry func mutate_outside (v: U32): U32 =>
  @storage.push table v
  return table[0]
entry kernel func read_table (x: U32): U32 => return @u32.add x table[0]
`,
    "kernel_mutates_context",
  );

  // Immutable-typed const pool aliasing a mutable global via view -> NOT deeply immutable -> kernel read rejected,
  // while an unrelated pure const pool in the same module remains accepted.
  await compileExpectedFailure(
    `const mut_table: #[+U32] = #[1, 2, 3]
const view_table: #[&[U32]] = #[&mut_table[0..1]]
entry kernel func read_view (x: U32): U32 => return @u32.add x view_table[0][0]
`,
    "kernel_mutates_context",
  );
  await compileAndRun(
    `const mut_table: #[+U32] = #[1, 2, 3]
const pure_table: #[U32] = #[10, 20, 30]
entry kernel func read_pure (x: U32): U32 => return @u32.add x pure_table[1]
entry func ok (): U32 => return @u32.add mut_table[0] pure_table[1]
`,
    (guest) => equal(guest.call("ok", null), 21),
  );
});

Deno.test("Law #3 (j): 20-level binary diamond scalability & 17-call-site widening soundness", async () => {
  // (j1) 20-level binary diamond (2^20 raw paths) using lent generic functions
  const diamondLines: string[] = [
    "const pool: #[+U32] = #[1, 2, 3]",
    "func f20 (a: t) -> (_: Bool): t => return a",
  ];
  for (let i = 19; i >= 0; i--) {
    diamondLines.push(
      `func f${i} (a: t) -> (flag: Bool): t => return if flag then f${i + 1} a flag else f${i + 1} a flag`,
    );
  }
  const diamondSrc = diamondLines.join("\n") + `
func body (x: U32): U32 =>
  let p = f0 pool (x == 0)
  @storage.push p 99
  return x
entry func bad (xs: #[U32]): #[U32] => return spark #[body x | x <- xs]
`;
  await compileExpectedFailure(diamondSrc, "spark_mutates_capture");

  // (j2) 17-call-site widening witness (> MAX_PATHS_PER_SITE = 16) including recursive origin
  const widenCalls: string[] = [];
  for (let i = 0; i < 18; i++) {
    widenCalls.push(`  if n == ${i}:\n    return wrap_rec 0 p`);
  }
  const widenSrc = `const pool: #[+U32] = #[1, 2, 3]
func wrap_rec (d: U32) -> (p: a): #[a] =>
  if d > 0:
    return wrap_rec (@u32.sub d 1) p
  return #[p]
func dispatch (n: U32) -> (p: a): #[a] =>
${widenCalls.join("\n")}
  return wrap_rec 1 p
func body (x: U32): U32 =>
  let w = dispatch x pool
  @storage.push w[0] 99
  return x
entry func bad (xs: #[U32]): #[U32] => return spark #[body x | x <- xs]
`;
  await compileExpectedFailure(widenSrc, "spark_mutates_capture");
});

Deno.test("Law #3 (k): positive precision tests (labelled fields, disjoint scratch, computed const pools, @storage.copy, two-factory relay)", async () => {
  await compileAndRun(
    `const pool: #[U32] = #[10, 20, 30]
func build_lut (): #[U32] =>
  let out = @array.fill 4 0
  for i in 0..4:
    out[i] := @u32.mul i 10
  return out
const computed_lut: #[U32] = build_lut ()

type Row is data = $Row { a: #[+U32], b: #[U32] }
type TupBox is data = $TupBox { p: (#[+U32], #[U32]) }
type Pair is data = $Pair { a: #[+U32], b: #[U32] }

func push_grow (dst: #[+U32]) -> (v: U32): Unit =>
  let box = #[dst]
  @storage.push box[0] v
  return ()
func read_only (rows: #[#[U32]]): U32 => return @u32.add rows[0][0] rows[1][0]
func identity (x: a): a => return x
func make_one_box (v: a): #[a] => return #[v]
func relay_two (p: a) -> (s: b): #[b] =>
  let _ = make_one_box p
  let b = make_one_box s
  return b

entry kernel func read_computed_lut (x: U32): U32 => return @u32.add x computed_lut[2]

func precise_body (x: U32): U32 =>
  let scratch: #[U32] = #[1, 2, 0, 0]
  let _ = read_only #[scratch, pool]
  let scratch_own: #[U32] = #[1, 2, 0, 0]
  let _ = @simd.store scratch_own 0 (99, 0, 0, 0)

  let r = { a: scratch_own, b: pool }
  let _ = @simd.store r.a 0 (98, 0, 0, 0)

  let a0: #[+U32] = #[1]
  let arr = #[{ a: a0, b: #[0, 0, 0, 0] }]
  arr[0].b := pool
  push_grow arr[0].a 97

  let a1: #[+U32] = #[1]
  let rows = #[$Row { a: a1, b: #[0, 0, 0, 0] }]
  rows[0].b := pool
  let _ = case rows[0] of
    $Row { a: ra, b: _ } => do:
      push_grow ra 96
      break ()

  let a2: #[+U32] = #[1]
  let tb = $TupBox (a2, pool)
  let (t0, _) = tb.p
  push_grow t0 95

  let a3: #[+U32] = #[1]
  let pr = $Pair (a3, pool)
  push_grow pr.a 94

  let a4: #[+U32] = #[1]
  let { a: local_a, b: _ } = { a: a4, b: pool }
  push_grow local_a 93

  let grow_s: #[+U32] = #[1]
  for (la, _) in #[(grow_s, pool)]:
    @storage.push la 42

  let ref_s: #[+U32] = #[1]
  let ref_box = &ref_s
  push_grow (@storage.load ref_box) 91

  let fresh_r = pool
  fresh_r := #[1]
  fresh_r[0] := 92

  let copied = @storage.copy pool
  copied[0] := 91

  let id_seed: #[+U32] = #[1]
  let id_local = identity id_seed
  push_grow id_local 90
  let _ = identity pool

  let fresh_s: #[+U32] = #[1]
  let disjoint = relay_two pool fresh_s
  @storage.push disjoint[0] 89

  return @u32.add x (@u32.add copied[0] computed_lut[1])

entry func precise_spark (xs: #[U32]): #[U32] => return spark #[precise_body x | x <- xs]
`,
    (guest) => {
      // copied[0] = 91, computed_lut[1] = 10 -> x + 101
      equal(String(guest.call("precise_spark", Uint32Array.of(1, 2))), "102,103");
    },
  );

  // Positive precision for `entry kernel`: plain-record context projection,
  // nested higher-order callable captures (`array.map` -> `array.generate`),
  // curried multi-arg callbacks, and pure-scalar `WireCtx` elements pushed
  // into locally allocated storage without false aliasing to `WireCtx`.
  await compileAndRun(
    `import * as array from "std/array"
type Storage is data = $Storage { values: #[~F32] }
type PreparedCtx = { storage: Storage, count: U32 }

func with_curried (xs: #[F32]) -> consume =>
  return consume xs.length xs

func append_into (storage: Storage) -> (xs: #[F32]): U32 =>
  for x in xs:
    @storage.push storage.values x
  return xs.length

func prep (wire: #[F32]): PreparedCtx =>
  let values: #[~F32] = #[]
  let storage = $Storage { values }
  let scaled = array.map (func v => v * 2.0) wire
  let count = with_curried scaled (func n -> ys =>
    let _ = append_into storage ys
    return n)
  return { storage, count }

func solve (ctx: PreparedCtx) -> (idx: U32): F32 =>
  if idx < ctx.count:
    return ctx.storage.values[idx]
  return 0.0

entry kernel k: Kernel [#[F32], U32, F32] = { prepare: prep, run: solve }
entry func smoke (): U32 => return 1
`,
    (guest) => {
      equal(guest.call("smoke", null), 1);
    },
    { stdRoot },
  );
});
