import { instantiateGuest } from "../../host/guest.ts";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

const executable = Deno.args[0] ??
  new URL("../../compiler-goose/build/squidc-goose", import.meta.url).pathname;
const stdRoot = new URL("../../std", import.meta.url).pathname;
const prelude = `${stdRoot}/prelude.sq`;

async function buildProjectFiles(
  files: Record<string, string>,
  entryName = "main.sq",
  extra: { testMode?: boolean } = {},
) {
  const dir = await Deno.makeTempDir({ prefix: "squid-audit-reg-" });
  try {
    for (const [name, content] of Object.entries(files)) {
      await Deno.writeTextFile(`${dir}/${name}`, content);
    }
    const client = await createZigProjectCompiler({
      executable,
      entry: `${dir}/${entryName}`,
      prelude,
      stdRoot,
      testMode: extra.testMode,
    });
    try {
      return await client.build();
    } finally {
      await client.dispose();
    }
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
}

Deno.test("audit: trait associated output constraints are enforced at concrete calls", async () => {
  await compileExpectedFailure(
    `
type Mul left { right, out } is trait = { mul: left -> right -> out }
const U32.Mul: Mul U32 { right: U32, out: U32 } = { mul: U32.mul }
func bad (x: a): F32 where { Mul a { right: a, out: F32 } } => x * x
io main (): F32 => bad 5
`,
    "type_mismatch",
  );

  await compileExpectedFailure(
    `
type Conv a { out } is trait = { conv: a -> out }
const Array.Conv: Conv #[F32] { out: #[F32] } = { conv: func xs => xs.copy }
func transmute (x: a): b where { Conv a { out: b } } => Conv.conv x
io main (): U32 =>
  let arr: #[U32] = transmute #[1.0, 2.0, -0.0]
  return arr[0]
`,
    "type_mismatch",
  );
});

Deno.test("audit: traitIsReadOnly rejects lifting traits with own on non-first parameters to *T", async () => {
  await compileExpectedFailure(
    `
type Mut2 a is trait = { set0: U32 -> own a -> a }
func arr_set0 (v: U32) -> (xs: own #[U32]): #[U32] =>
  xs[0] := v
  return xs
const Array.Mut2: Mut2 #[U32] = { set0: arr_set0 }
io main (): U32 =>
  let xs: #[U32] = #[10, 20]
  let f: *#[U32] = freeze xs
  let alias: *#[U32] = f
  let updated = Mut2.set0 99 (own f)
  return alias[0] * 100 + updated[0]
`,
    "missing_implementation",
  );
});

Deno.test("audit: #for #fields, #variants, .(field), and builders respect is opaque encapsulation", async () => {
  const sec = `
private func secret_seed (): U32 => return 777
type Secret is opaque = { key: U32 = secret_seed () }
func make (): Secret => $Secret { key: 123 }
`;
  for (
    const main of [
      `import * as sec from "./sec"
io main (): U32 =>
  let s = sec.make ()
  let acc: U32 = 0
  #for f in #fields sec.Secret:
    acc := acc + s.(f)
  return acc
`,
      `import * as sec from "./sec"
func dump (v: t): U32 =>
  let acc: U32 = 0
  #for f in #fields t:
    acc := acc + v.(f)
  return acc
io main (): U32 => dump (sec.make ())
`,
      `import * as sec from "./sec"
io main (): U32 =>
  let vlen: U32 = 0
  #for v in #variants sec.Secret:
    vlen := vlen + v.name.length
  return vlen
`,
      `import * as sec from "./sec"
io main (): U32 =>
  let _forged: sec.Secret = #for f in #fields sec.Secret:
    break f.default
  return 0
`,
    ]
  ) {
    const res = await buildProjectFiles({ "sec.sq": sec, "main.sq": main });
    equal(res.success, false);
  }
});

Deno.test("audit: fork rejects indirect Foreign via enclosing handler", async () => {
  await compileExpectedFailure(
    `
type Boom is effect = { fire: U32 -> U32 }
io main (cb: U32 -> U32 ! {Foreign}): U32 =>
  let xs = #[1, 2]
  handler h_boom: Boom =>
    fire x => return use cb x
  use v <- (func () =>
    use r <- fork xs:
      xs[0] := 99
      use res <- Boom.fire 42
      return res + xs[0]
    return r
  ).handle h_boom
    .run ()
  return v * 100 + xs[0]
`,
    "sealed_effect",
  );
});

Deno.test("audit: exiting branch arms do not end live borrows (C1)", async () => {
  await compileExpectedFailure(
    `
io main (cond: Bool): U32 =>
  let xs = #[10, 20]
  let alias = xs
  if cond:
    let v = alias[0]
    return v
  xs[0] := 999
  return alias[0]
`,
    "aliased_update",
  );
});

Deno.test("audit: generic #for builders and updates cannot launder const pools or borrowed arrays (C2)", async () => {
  await compileExpectedFailure(
    `
const POOL: #[U32] = #[10, 20, 30, 40]
type Box1 = { a: #[U32] }
func launder (x: a): t =>
  return #for f in #fields t:
    break x
io main (): U32 =>
  let b: Box1 = launder POOL
  b.a[0] := 99
  return POOL[0]
`,
    "result_not_owned",
  );

  await compileExpectedFailure(
    `
type Pair = { left: #[U32], right: #[U32] }
func set_all (val: own t) -> (x: a): t =>
  #for f in #fields t:
    val.(f) := x
  return val
io main (): U32 =>
  let xs = #[10, 20]
  let p: Pair = set_all (own { left: #[0], right: #[0] }) xs
  p.left[0] := 77
  return xs[0]
`,
    "aliased_update",
  );
});

Deno.test("audit: @simd.store, own *#[T], and fork *#[T] reject mutating frozen pools (C3)", async () => {
  await compileExpectedFailure(
    `
const frozen_pool: *#[U32] = freeze #[10, 20, 30, 40]
func bump_frozen (s: own *#[U32]): U32 =>
  let v = s[0]
  let _ = @simd.store s 0 (v + 1, 20, 30, 40)
  return v
io main (): U32 => bump_frozen (own frozen_pool)
`,
    "type_mismatch",
  );
});

Deno.test("audit: generic freeze cannot freeze closures capturing linear arrays (C4)", async () => {
  await compileExpectedFailure(
    `
func generic_freeze (x: a): *a =>
  return freeze x
io main (): U32 =>
  let xs = #[10, 20, 30]
  let f: *(U32 -> U32) = generic_freeze (func i => xs[i])
  let v1 = f 0
  xs[0] := 999
  return v1 + f 0
`,
    "own_argument",
  );
});

Deno.test("audit: deep copy isolates nested arrays (C5) and deep recursive ADTs past depth 16 (C6)", async () => {
  await compileAndRun(
    `
type ArrList is data =
  | $Nil
  | $Cons { head: #[U32], tail: ArrList }

func build (n: U32): ArrList =>
  let cur: ArrList = $Nil
  for i in 0..n:
    cur := $Cons { head: #[i + 1], tail: cur }
  return cur

func last_val (xs: ArrList): U32 =>
  case xs of
    $Nil => 0
    $Cons { head, tail } =>
      case tail of
        $Nil => head[0]
        $Cons _ => last_val tail

func set_last (xs: own ArrList) -> (v: U32): ArrList =>
  let $Cons { head, tail } = xs else:
    return $Nil
  let $Cons { head: h2, tail: t2 } = tail else:
    head[0] := v
    return $Cons { head, tail: $Nil }
  let rest = $Cons { head: h2, tail: t2 }
  let next = set_last (own rest) v
  return $Cons { head, tail: next }

io run (n: U32): U32 =>
  let orig = build n
  let cloned = copy orig
  let cloned2 = set_last (own cloned) 999
  return last_val orig * 1000 + last_val cloned2
`,
    (guest) => {
      equal(guest.call("run", 10), 1999);
      equal(guest.call("run", 17), 1999);
      equal(guest.call("run", 25), 1999);
    },
  );
});

Deno.test("audit: handler shadowing records, returning cells, and inside fork are sound (C7, C8, C9)", async () => {
  await compileExpectedFailure(
    `
type Ping is effect = { ping: Unit -> *#[U32] }
io main (): U32 =>
  let r = { a: #[10, 20], b: #[30, 40] }
  handler h_ping: Ping =>
    ping () =>
      let f = freeze r.a
      r.b[0] := 31
      return f
  let leaked = (func () => return use Ping.ping ()).handle h_ping
    .run ()
  r.a[0] := 999
  return leaked[0] * 1000 + r.a[0]
`,
    "spent_value",
  );

  await compileExpectedFailure(
    `
type Store is effect = { get: Unit -> #[U32] }
io main (): U32 =>
  let arr = #[10, 20]
  handler h_store: Store =>
    get () =>
      arr[1] := 21
      return arr
  let alias = (func () => return use Store.get ()).handle h_store
    .run ()
  arr[0] := 999
  return alias[0] * 1000 + arr[0]
`,
    "result_not_owned",
  );

  await compileExpectedFailure(
    `
type Store is effect = { get: Unit -> { x: #[U32] } }
io main (): U32 =>
  let arr = #[10, 20]
  handler h_store: Store =>
    get () =>
      arr[1] := 21
      return { x: arr }
  let r = (func () => return use Store.get ()).handle h_store
    .run ()
  let alias = r.x
  arr[0] := 999
  return alias[0] * 1000 + arr[0]
`,
    "result_not_owned",
  );

  await compileExpectedFailure(
    `
type FreezeEff is effect = { go: Unit -> Unit }
io main (): U32 =>
  let arr = #[10, 20]
  handler h_freeze: FreezeEff =>
    go () =>
      arr[1] := 21
      let _ = freeze arr
      return ()
  (func () => use FreezeEff.go ()).handle h_freeze
    .run ()
  arr[0] := 99
  return arr[0]
`,
    "spent_value",
  );

  await compileAndRun(
    `
type Bump is effect = { step: Unit -> Unit }
io main (): U32 =>
  let arr = #[10, 20]
  handler h_bump: Bump =>
    step () =>
      arr[0] := 11
      arr[1] := 22
      return ()
  (func () => use Bump.step ()).handle h_bump
    .run ()
  return arr[0] * 100 + arr[1]
`,
    (guest) => {
      equal(guest.call("main", null), 1122);
    },
  );

  await compileExpectedFailure(
    `
type Mod is effect = { touch: Unit -> Unit }
io main (): U32 =>
  let x = #[1, 2]
  let y = #[10, 20]
  let z: #[U32] = fork x:
    handler h_mod: Mod =>
      touch () => y := y
    (func () => use Mod.touch ()).handle h_mod
      .run ()
    return y
  z[0] := 777
  return y[0] * 1000 + z[0]
`,
    "aliased_update",
  );
});

Deno.test("audit: FBIP and linearAppend preserve immutability across loops, merges, no-op updates, statement case, and carries (C10-C13)", async () => {
  await compileAndRun(
    `
type Big is data = $Big {
  a: U32, b: U32, c: U32, d: U32, e: U32, f: U32, g: U32, h: U32,
  i: U32, j: U32, k: U32, l: U32, m: U32, n: U32, o: U32, p: U32, q: U32, r: U32
}
type Outer is data = | $Wrap Big | $None
type Tree is data = | $Leaf U32 | $Node { left: Tree, value: U32, right: Tree }

func big (a: U32) -> (b: U32): Big =>
  $Big { a, b, c: 0, d: 0, e: 0, f: 0, g: 0, h: 0, i: 0, j: 0, k: 0, l: 0, m: 0, n: 0, o: 0, p: 0, q: 0, r: 0 }

func tree_val (t: Tree): U32 =>
  case t of
    $Leaf n => n
    $Node { left, value, right } => value

func mutate_copy (orig: Big): U32 =>
  let c = orig
  c.a := self
  c.b := 999
  return c.b

io test_c10a (): U32 =>
  let base = big 10 0
  let sum = 0
  for idx in 0..3:
    let next = base
    next.a := self + 100
    sum := sum + next.a
  return sum

io test_c10b (flag: Bool): U32 =>
  let x = big 10 0
  let k = 0
  if flag:
    let x2 = x
    x2.a := 999
    k := x2.a
  else:
    x := big 20 0
  return x.a * 1000 + k

io test_c10c (flag: Bool): U32 =>
  let a = #[10, 20]
  let b: #[U32] = #[]
  if flag:
    b := @array.append a 99
  else:
    a := #[1, 2]
  b[0] := 777
  return a.length * 1000 + a[0]

io test_c11 (): U32 =>
  let orig = big 1 2
  let res = mutate_copy orig
  return orig.b * 1000 + res

io test_c12 (): U32 =>
  let x: Outer = $Wrap (big 11 2)
  let saved = big 0 0
  let out: Outer = $None
  case x of
    $Wrap inner =>
      saved := inner
      out := $Wrap (big 99 99)
    $None =>
      out := $None
  return saved.a

io test_c13 (): U32 =>
  let shared = $Node { left: $Leaf 1, value: 42, right: $Leaf 2 }
  let cur = $Node { left: $Leaf 1, value: 10, right: $Leaf 2 }
  for i in 0..2:
    cur := case cur of
      $Node { left, value, right } => if i == 0 then shared else $Node { left, value: 999, right }
      $Leaf n => $Leaf n
  return tree_val shared * 1000 + tree_val cur
`,
    (guest) => {
      equal(guest.call("test_c10a", null), 330);
      equal(guest.call("test_c10b", true), 10999);
      equal(guest.call("test_c10c", true), 2010);
      equal(guest.call("test_c11", null), 2999);
      equal(guest.call("test_c12", null), 11);
      equal(guest.call("test_c13", null), 42999);
    },
  );
});

Deno.test("audit: @simd.store invalidates element cache (H1) and defer_f32_nan canonicalizes all NaNs", async () => {
  const res = await buildProjectFiles({
    "main.sq": `
import * as simd from "std/simd"

func bits (x: F32): U32 =>
  let (b, _, _, _) = simd.f32_bits (x, 0.0, 0.0, 0.0)
  return b

io test_simd_store (idx: U32): U32 =>
  let a = #[10, 20, 30, 40]
  let before = a[idx]
  let _ = @simd.store a idx (99, 88, 77, 66)
  let after = a[idx]
  return before * 100 + after

io test_defer_nan (zero: F32): #[U32] =>
  let a: #[F32] = #[zero, zero, zero]
  let out: #[F32] = #[0.0, 0.0, 0.0]
  let ctr: #[U32] = #[0]
  for 0..3:
    let k = ctr[0]
    out[k] := a[k] / a[k]
    ctr[0] := k + 1
  return #[bits out[0], bits out[1], bits out[2]]
`,
  });
  equal(res.success, true);
  if (!res.success) return;
  const guest = await instantiateGuest(res.bytes);
  try {
    equal(guest.call("test_simd_store", 0), 1099);
    const nanBits = Array.from(guest.call("test_defer_nan", 0.0) as Uint32Array);
    equal(JSON.stringify(nanBits), JSON.stringify([0x7fc00000, 0x7fc00000, 0x7fc00000]));
  } finally {
    guest.dispose();
  }
});

Deno.test("audit: #run/#if associated eq/ne, generic ops, carries in let-else & #for RHS, generic field.default, spark in #for", async () => {
  await compileAndRun(
    `
type Mod10 is data = $Mod10 { v: U32 }
func Mod10.eq (a: Mod10) -> (b: Mod10): Bool => (a.v % 10) == (b.v % 10)
func same a -> b => a == b

type Pair = { a: U32, b: U32 }
type Wrap a is data = $Wrap { items: #[a] = #[], count: U32 = 9 }
type HasArr is data = $HasArr { xs: #[U32] = #[1, 2, 3], n: U32 = 9 }
type Holder = { a: #[U32], b: #[U32] }

func maybe_even (x: U32): Maybe U32 => if (x & 1) == 0 then $Some x else $Nothing
func maybe_at (at: U32): Maybe U32 => if at == 1 then $Some 10 else $Nothing

func make_has_arr (): HasArr =>
  return #for f in #fields HasArr:
    break f.default

io test_staging_eq (): U32 =>
  let c_negz = if #run (eq 0.0 (-0.0)) then 1 else 0
  let c_nan  = if #run (eq (0.0 / 0.0) (0.0 / 0.0)) then 10 else 0
  let c_mod  = if #run (eq ($Mod10 { v: 12 }) ($Mod10 { v: 22 })) then 100 else 0
  let c_gen  = if #run (same ($Mod10 { v: 12 }) ($Mod10 { v: 22 })) then 1000 else 0
  let if_negz: U32 = 0
  #if eq 0.0 (-0.0):
    if_negz := 10000
  let if_nan: U32 = 0
  #if eq (0.0 / 0.0) (0.0 / 0.0):
    if_nan := 100000
  return c_negz + c_nan + c_mod + c_gen + if_negz + if_nan

io test_carries (): U32 =>
  let misses: U32 = 0
  for i in 0..5:
    let $Some _ = maybe_even i else:
      misses := misses + 1
      continue
  let at1: U32 = 0
  let p1: Pair = #for f in #fields Pair:
    let $Some v = maybe_at at1 else:
      at1 := at1 + 1
      break 7
    break v
  let at2: U32 = 0
  let p2: Pair = { a: 0, b: 0 }
  p2 := #for f in #fields Pair:
    at2 := at2 + 1
    break at2
  let at3: U32 = 0
  let arr: #[Pair] = #[{ a: 0, b: 0 }]
  arr[0] := #for f in #fields Pair:
    at3 := at3 + 1
    break at3
  let at4: U32 = 0
  let p4: Pair = case true of
    true => #for f in #fields Pair:
      at4 := at4 + 1
      break at4
    false => { a: 0, b: 0 }
  return misses * 1000000 + (p1.a * 1000 + p1.b * 10 + at1) + (p2.a * 100 + p2.b * 10 + at2) * 1 + (arr[0].a * 100 + arr[0].b * 10 + at3) * 1 + (p4.a * 100 + p4.b * 10 + at4) * 1

io test_comptime_misc (): U32 =>
  let w: Wrap U32 = #for f in #fields (Wrap U32):
    break f.default
  let ha = make_has_arr ()
  let h: Holder = { a: #[10], b: #[20] }
  #for f in #fields Holder:
    h.(f) := self
  let p: Pair = { a: 3, b: 7 }
  let total: U32 = 0
  #for f in #fields Pair:
    let xs = spark #[p.(f) + i | i <- 0..4]
    total := total + xs[3]
  return (w.items.length + w.count) * 10000 + (ha.xs.length + ha.n) * 1000 + (h.a[0] + h.b[0]) * 100 + total
`,
    (guest) => {
      // c_negz=1, c_nan=0, c_mod=100, c_gen=1000, if_negz=10000, if_nan=0
      equal(guest.call("test_staging_eq", null), 11101);
      // misses=2, p1=7101, p2=122, arr[0]=122, p4=122 => 2000000 + 7101 + 366 = 2007467
      equal(guest.call("test_carries", null), 2007467);
      // 9*10000 + 12*1000 + 30*100 + 16 = 105016
      equal(guest.call("test_comptime_misc", null), 105016);
    },
  );
});

Deno.test("audit: retained SIMD literal edits match cold oracle across all 5 vectorizers", async () => {
  const dir = await Deno.makeTempDir({ prefix: "squid-simd-reloc-" });
  const entry = `${dir}/main.sq`;
  const cases: Array<{ name: string; v1: string; v2: string; arg: number }> = [
    {
      name: "affine_init",
      v1: `io run (n: U32): U32 =>
  let arr = @array.fill n 0
  let s: U32 = 1
  for i in 0..n:
    s := s * 1664525 + 1013904223
    arr[i] := s
  return arr[0] ^ arr[n - 1]
`,
      v2: `io run (n: U32): U32 =>
  let arr = @array.fill n 0
  let s: U32 = 1
  for i in 0..n:
    s := s * 1664527 + 1013904223
    arr[i] := s
  return arr[0] ^ arr[n - 1]
`,
      arg: 17,
    },
    {
      name: "affine_unroll",
      v1: `io run (n: U32): U32 =>
  let s: U32 = 1
  let acc: U32 = 0
  for _ in 0..n:
    s := s * 1664525 + 1013904223
    acc := acc ^ (s & 255)
  return acc
`,
      v2: `io run (n: U32): U32 =>
  let s: U32 = 1
  let acc: U32 = 0
  for _ in 0..n:
    s := s * 1664527 + 1013904223
    acc := acc ^ (s & 255)
  return acc
`,
      arg: 35,
    },
    {
      name: "aos_f32_record",
      v1: `type Vec2 = { x: F32, y: F32 }
io run (n: U32): U32 =>
  let p = @array.fill n { x: 4.0, y: 8.0 }
  for i in 0..n:
    let q = p[i]
    p[i] := { x: q.x * 0.25, y: q.y * 0.25 }
  return @f32.to_u32 (p[0].x + p[n - 1].x)
`,
      v2: `type Vec2 = { x: F32, y: F32 }
io run (n: U32): U32 =>
  let p = @array.fill n { x: 4.0, y: 8.0 }
  for i in 0..n:
    let q = p[i]
    p[i] := { x: q.x * 0.50, y: q.y * 0.25 }
  return @f32.to_u32 (p[0].x + p[n - 1].x)
`,
      arg: 17,
    },
    {
      name: "vector_reduction",
      v1: `io run (n: U32): U32 =>
  let flags = @array.fill n true
  let acc: U32 = 0
  for i in 0..flags.length:
    if flags[i]:
      acc := @type.call "add" acc 1
  return acc
`,
      v2: `io run (n: U32): U32 =>
  let flags = @array.fill n true
  let acc: U32 = 0
  for i in 0..flags.length:
    if flags[i]:
      acc := @type.call "add" acc 5
  return acc
`,
      arg: 17,
    },
  ];
  try {
    for (const c of cases) {
      await Deno.writeTextFile(entry, c.v1);
      const retained = await createZigProjectCompiler({
        executable,
        entry,
        prelude,
        stdRoot,
      });
      try {
        const r1 = await retained.build({ sources: { [entry]: c.v1 } });
        equal(r1.success, true);
        const r2 = await retained.build({ sources: { [entry]: c.v2 } });
        if (!r2.success) throw new Error(`retained failed: ${JSON.stringify(r2.diagnostics)}`);
        const cold = await createZigProjectCompiler({
          executable,
          entry,
          prelude,
          stdRoot,
        });
        try {
          const rc = await cold.build({ sources: { [entry]: c.v2 } });
          if (!rc.success) throw new Error(`cold failed: ${JSON.stringify(rc.diagnostics)}`);
          const gRet = await instantiateGuest(r2.bytes);
          const gCold = await instantiateGuest(rc.bytes);
          try {
            equal(
              gRet.call("run", c.arg),
              gCold.call("run", c.arg),
            );
          } finally {
            gRet.dispose();
            gCold.dispose();
          }
        } finally {
          await cold.dispose();
        }
      } finally {
        await retained.dispose();
      }
    }
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});

Deno.test("audit: frontend validation rejects invalid test return types, #[N; T] #entry params, duplicate with, and comptime closure capture", async () => {
  const badTest = await buildProjectFiles(
    { "main.sq": `test "returns u32" => 42\n` },
    "main.sq",
    { testMode: true },
  );
  equal(badTest.success, false);

  await compileExpectedFailure(
    `io main (xs: #[3; U32]): U32 => xs[0]\n`,
    "entry_type",
  );

  await compileExpectedFailure(
    `
type Ask is effect = { get: Unit -> U32 }
io main (): U32 =>
  let n = 1
  handler h: Ask =>
    get () =>
      n := n + 1
      return n
  let a = (func () => return use Ask.get ()).handle h
    .run ()
  let b = (func () => return use Ask.get ()).handle h
    .run ()
  return a + b
`,
    "borrow_conflict",
  );

  await compileExpectedFailure(
    `
type Pair = { a: U32, b: U32 }
io main (): U32 =>
  #for f in #fields Pair:
    let _g = func () => f.index
  return 0
`,
    "unsupported",
  );
});

Deno.test("audit: multi-parameter nominal types [k, v] preserve ownership facts across own calls and loops", async () => {
  await compileAndRun(
    `
type Entry [k, v] is data = $Entry { key: k, val: v }
type Map [k, v] is data = $Map { rows: #[Entry [k, v]], count: #[U32] }
type Set k = Map [k, Unit]

func push_key (key: k) -> (table: own Set k): Set k =>
  @storage.push table.rows ($Entry { key, val: () })
  table.count[0] := table.rows.length
  return table

func build_set (values: #[k]) -> (table: own Set k): Set k =>
  if values.length == 0:
    return table
  table := push_key values[0] table
  for i in 1..values.length:
    table := push_key values[i] table
  return table

io main (): U32 =>
  let init: Set U32 = $Map { rows: #[], count: #[0] }
  let out = build_set #[10, 20, 30] init
  out.count[0] := out.count[0] + 100
  return out.count[0] * 10 + out.rows.length
`,
    (guest) => {
      equal(guest.call("main", null), 1033);
    },
  );

  await compileExpectedFailure(
    `
func leak (candidate: Result [U32, #[U32]]): Result [U32, #[U32]] =>
  return Result.map (func value => return value + 1) candidate
io main (x: U32): U32 =>
  let child = #[x, x + 1]
  let mapped = leak ($Err child)
  return case mapped of
    $Ok v => v
    $Err a => a[0]
`,
    "result_not_owned",
  );
});

Deno.test("audit: nullableNiche module const $Nothing and const-array loop unrolling emit null pointer 0", async () => {
  await compileAndRun(
    `
type BigEpoch is data = $BigEpoch {
  a: U32, b: U32, c: U32, d: U32, e: U32, f: U32,
  tiles: #[U32],
}
const no_epoch: Maybe BigEpoch = $Nothing
const empty_epochs: #[Maybe BigEpoch] = #[$Nothing, $Nothing]

func inspect_epoch (opt: Maybe BigEpoch): U32 =>
  return case opt of
    $Nothing => 17
    $Some ep => ep.a + ep.f + ep.tiles.length

io main (k: U32): U32 =>
  let sum = inspect_epoch no_epoch
  for item in empty_epochs:
    sum := self + inspect_epoch item
  let live = $Some ($BigEpoch { a: k, b: 1, c: 2, d: 3, e: 4, f: 5, tiles: #[9, 10, 11] })
  sum := self + inspect_epoch live
  return sum
`,
    (guest) => {
      equal(guest.call("main", 100), 17 * 3 + 100 + 5 + 3);
    },
  );
});

Deno.test("audit: boxed unique_boxed deferred/own reuse stays bounded in loops and preserves pure-scalar/pure-subfield immutability", async () => {
  // 1. Bounded stack memory across 25,000 loop updates on a large (> 16 words)
  // boxed record holding owned storage where RHS reads sibling fields and mixes
  // indexed updates with field replacements.
  await compileAndRun(
    `
type BigAccess is data = $BigAccess {
  entities: #[U32],
  a: #[U32], b: #[U32], c: #[U32], d: #[U32],
  e: #[U32], f: #[U32], g: #[U32], h: #[U32],
  m0: U32, m1: U32, m2: U32, m3: U32,
  m4: U32, m5: U32, m6: U32, m7: U32,
}

func push_with (entities: #[U32]) -> (xs: own #[U32]) -> (v: U32): #[U32] =>
  @storage.push xs (v + entities.length)
  return xs

func fill_loop (access: own BigAccess) -> (n: U32): BigAccess =>
  for i in 0 .. n:
    let id = access.entities.length
    @storage.push access.entities id
    access.m0 := self + 1
    access.a := push_with access.entities self i
    access.m1 := self + 1
    access.b := push_with access.entities self (i + 1)
    access.m2 := self + 1
    access.c := push_with access.entities self (i + 2)
    access.m3 := self + 1
    if access.a.length > 0:
      access.a[0] := i
    access.m4 := self + 1
  return access

io main (n: U32): U32 =>
  let acc = $BigAccess {
    entities: #[], a: #[], b: #[], c: #[], d: #[],
    e: #[], f: #[], g: #[], h: #[],
    m0: 0, m1: 0, m2: 0, m3: 0, m4: 0, m5: 0, m6: 0, m7: 0,
  }
  acc := fill_loop self n
  return acc.entities.length + acc.a[0] + acc.m4
`,
    (guest) => {
      equal(guest.call("main", 25000), 25000 + 24999 + 25000);
    },
  );

  // 2. Soundness: pure-scalar own boxed record is NOT uniquely spent by caller,
  // so callee MUST NOT mutate caller's block in place.
  await compileAndRun(
    `
type PureBig is data = $PureBig {
  f0: U32, f1: U32, f2: U32, f3: U32, f4: U32, f5: U32, f6: U32, f7: U32,
  f8: U32, f9: U32, f10: U32, f11: U32, f12: U32, f13: U32, f14: U32, f15: U32,
  f16: U32, f17: U32,
}

func mutate_pure (p: own PureBig): PureBig =>
  p.f0 := 999
  p.f17 := 888
  return p

io main (): U32 =>
  let orig = $PureBig {
    f0: 1, f1: 2, f2: 3, f3: 4, f4: 5, f5: 6, f6: 7, f7: 8,
    f8: 9, f9: 10, f10: 11, f11: 12, f12: 13, f13: 14, f14: 15, f15: 16,
    f16: 17, f17: 18,
  }
  let changed = mutate_pure orig
  return orig.f0 * 10000 + orig.f17 * 100 + changed.f0
`,
    (guest) => {
      equal(guest.call("main", null), 1 * 10000 + 18 * 100 + 999);
    },
  );

  // 3. Soundness: own boxed record holding storage AND a pure-scalar copiedBox
  // subfield MUST NOT mutate the parent block in place because a caller can
  // hold an interior readFlat pointer to the pure subfield without a loan.
  await compileAndRun(
    `
type PureSub is data = $PureSub {
  s0: U32, s1: U32, s2: U32, s3: U32, s4: U32, s5: U32, s6: U32, s7: U32,
  s8: U32, s9: U32, s10: U32, s11: U32, s12: U32, s13: U32, s14: U32, s15: U32,
  s16: U32, s17: U32,
}
type MixedOwner is data = $MixedOwner {
  xs: #[U32],
  sub: PureSub,
}

func overwrite_sub (m: own MixedOwner): MixedOwner =>
  m.sub.s0 := 777
  m.sub.s17 := 666
  return m

io main (): U32 =>
  let rec = $MixedOwner {
    xs: #[1, 2, 3],
    sub: $PureSub {
      s0: 11, s1: 0, s2: 0, s3: 0, s4: 0, s5: 0, s6: 0, s7: 0,
      s8: 0, s9: 0, s10: 0, s11: 0, s12: 0, s13: 0, s14: 0, s15: 0,
      s16: 0, s17: 22,
    },
  }
  let saved_sub = rec.sub
  let updated = overwrite_sub rec
  return saved_sub.s0 * 10000 + saved_sub.s17 * 100 + updated.sub.s0
`,
    (guest) => {
      equal(guest.call("main", null), 11 * 10000 + 22 * 100 + 777);
    },
  );

  // 4. Soundness: in-place boxed record write storing a fresh temporary owner
  // inside a loop (directly or via an own callee) must notify escape tracking
  // so releaseIteration does not free the newly-stored array handle.
  await compileAndRun(
    `
type BoxedCarry = {
  rows: #[U32],
  a: #[U32], b: #[U32], c: #[U32], d: #[U32],
  e: #[U32], f: #[U32], g: #[U32], h: #[U32],
}

func replace_rows (w: own BoxedCarry) -> (k: U32): BoxedCarry =>
  let scratch = @array.fill 64 k
  w.rows := #[k, scratch[0] + 1, scratch[63] + 2]
  return w

io direct_loop (n: U32): U32 =>
  let w: BoxedCarry = {
    rows: #[0, 0, 0],
    a: #[1], b: #[2], c: #[3], d: #[4],
    e: #[5], f: #[6], g: #[7], h: #[8],
  }
  for i in 0 .. n:
    let scratch = @array.fill 64 i
    w.rows := #[i, scratch[0] + 1, scratch[63] + 2]
  return w.rows[0] + w.rows[1] + w.rows[2] + w.h[0]

io callee_loop (n: U32): U32 =>
  let w: BoxedCarry = {
    rows: #[0, 0, 0],
    a: #[1], b: #[2], c: #[3], d: #[4],
    e: #[5], f: #[6], g: #[7], h: #[8],
  }
  for i in 0 .. n:
    w := replace_rows w i
  return w.rows[0] + w.rows[1] + w.rows[2] + w.h[0]
`,
    (guest) => {
      equal(guest.call("direct_loop", 120), 119 + 120 + 121 + 8);
      equal(guest.call("callee_loop", 120), 119 + 120 + 121 + 8);
    },
  );

  // 5. Performance + soundness: updating a boxed record containing nested
  // memory-holding elements (e.g. `#[RowWithSlice]`) and a >16-word copiedBox
  // sub-record in place without changing owner slots MUST still allow loop
  // `releaseIteration` to reclaim per-iteration scratch across 4000 iterations.
  await compileAndRun(
    `
const static_extra: #[U32] = #[10, 20, 30]
type DrawRow = { tag: U32, extra: &[U32] }
type SubFrame is data = $SubFrame {
  draws: #[DrawRow],
  a: #[U32], b: #[U32], c: #[U32], d: #[U32],
  e: #[U32], f: #[U32], g: #[U32], h: #[U32],
  count: U32,
}
type OuterWorld is data = $OuterWorld {
  frame: SubFrame,
  x: #[U32], y: #[U32],
}

func reset_frame (fr: own SubFrame) -> (k: U32): SubFrame =>
  @storage.truncate fr.draws 0
  @storage.push fr.draws { tag: k, extra: &static_extra[0..2] }
  fr.count := k
  return fr

func step_world (w: own OuterWorld) -> (k: U32): OuterWorld =>
  w.frame := reset_frame self k
  return w

io main (n: U32): U32 =>
  let w = $OuterWorld {
    frame: $SubFrame {
      draws: #[],
      a: #[1], b: #[2], c: #[3], d: #[4],
      e: #[5], f: #[6], g: #[7], h: #[8],
      count: 0,
    },
    x: #[9], y: #[10],
  }
  let acc: U32 = 0
  for i in 0 .. n:
    let scratch = @array.fill 16384 i
    w := step_world w i
    acc := acc + (scratch[0] ^ scratch[16383])
  return w.frame.count + w.frame.draws[0].tag + w.frame.draws[0].extra[1] + acc
`,
    (guest) => {
      // 4000 * 64 KiB = 256 MiB > 128 MiB stack budget: passes ONLY if
      // releaseIteration reclaims scratch every iteration.
      equal(guest.call("main", 4000), 3999 + 3999 + 20 + 0);
    },
  );

  // 6. Performance: mutating a freshly-allocated local boxed temporary
  // (containing views `&[U32]`, like `ui.Node` in `editor.declare_toolbar`)
  // in place inside a loop MUST NOT mark `escape_min_slot = 0` or block
  // `releaseIteration` on the enclosing loop.
  await compileAndRun(
    `
const empty_u32: #[U32] = #[]
type TempNode is data = $TempNode {
  id: U32,
  name: &[U32],
  desc: &[U32],
  value_text: &[U32],
  a: U32, b: U32, c: U32, d: U32,
  e: U32, f: U32, g: U32, h: U32,
}

func make_node (id: U32) -> (name: &[U32]): TempNode =>
  $TempNode {
    id, name,
    desc: &empty_u32[0..0],
    value_text: &empty_u32[0..0],
    a: 1, b: 2, c: 3, d: 4, e: 5, f: 6, g: 7, h: 8,
  }

func with_value (text: &[U32]) -> (node: TempNode): TempNode =>
  node.value_text := text
  return node

io main (n: U32): U32 =>
  let total: U32 = 0
  for i in 0 .. n:
    let scratch = @array.fill 16384 i
    let label = #[i, i + 1, i + 2]
    let item = make_node i (&label[0..3])
    item.a := i + 10
    let built = with_value (&scratch[0..4]) item
    total := total + (built.value_text.at 0) + (built.name.at 1) + built.a
  return total
`,
    (guest) => {
      // 4000 * 64 KiB = 256 MiB > 128 MiB stack budget: passes ONLY if
      // mutating the local fresh TempNode leaves `escape_min_slot` intact.
      let expected = 0;
      for (let i = 0; i < 4000; i++) {
        expected = (expected + i + (i + 1) + (i + 10)) >>> 0;
      }
      equal(guest.call("main", 4000), expected);
    },
  );
});
