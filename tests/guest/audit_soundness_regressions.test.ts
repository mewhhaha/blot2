import { instantiateGuest } from "../../host/guest.ts";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

const executable = Deno.args[0] ??
  new URL("../../compiler-goose/build/blotc-goose", import.meta.url).pathname;
const stdRoot = new URL("../../std", import.meta.url).pathname;
const prelude = `${stdRoot}/prelude.blot`;

async function buildProjectFiles(
  files: Record<string, string>,
  entryName = "main.blot",
  extra: { testMode?: boolean } = {},
) {
  const dir = await Deno.makeTempDir({ prefix: "blot-audit-reg-" });
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
#entry func main (): F32 => bad 5
`,
    "type_mismatch",
  );

  await compileExpectedFailure(
    `
type Conv a { out } is trait = { conv: a -> out }
const Array.Conv: Conv #[F32] { out: #[F32] } = { conv: func xs => xs.copy }
func transmute (x: a): b where { Conv a { out: b } } => Conv.conv x
#entry func main (): U32 =>
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
#entry func main (): U32 =>
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
#entry func main (): U32 =>
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
#entry func main (): U32 => dump (sec.make ())
`,
      `import * as sec from "./sec"
#entry func main (): U32 =>
  let vlen: U32 = 0
  #for v in #variants sec.Secret:
    vlen := vlen + v.name.length
  return vlen
`,
      `import * as sec from "./sec"
#entry func main (): U32 =>
  let _forged: sec.Secret = #for f in #fields sec.Secret:
    break f.default
  return 0
`,
    ]
  ) {
    const res = await buildProjectFiles({ "sec.blot": sec, "main.blot": main });
    equal(res.success, false);
  }
});

Deno.test("audit: fork rejects indirect Foreign via enclosing with handler", async () => {
  await compileExpectedFailure(
    `
type Boom is effect = { fire: U32 -> U32 }
#entry func main (cb: U32 -> U32 ! {Foreign}): U32 =>
  let xs = #[1, 2]
  let v = 0
  with Boom = { fire: func x => return use cb x }:
    use r <- fork xs:
      xs[0] := 99
      use res <- Boom.fire 42
      return res + xs[0]
    v := r
  return v * 100 + xs[0]
`,
    "sealed_effect",
  );
});

Deno.test("audit: exiting branch arms do not end live borrows (C1)", async () => {
  await compileExpectedFailure(
    `
#entry func main (cond: Bool): U32 =>
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
#entry func main (): U32 =>
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
#entry func main (): U32 =>
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
#entry func main (): U32 => bump_frozen (own frozen_pool)
`,
    "type_mismatch",
  );
});

Deno.test("audit: generic freeze cannot freeze closures capturing linear arrays (C4)", async () => {
  await compileExpectedFailure(
    `
func generic_freeze (x: a): *a =>
  return freeze x
#entry func main (): U32 =>
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

#entry func run (n: U32): U32 =>
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

Deno.test("audit: with shadowing records, returning cells, and inside fork are sound (C7, C8, C9)", async () => {
  await compileExpectedFailure(
    `
type Ping is effect = { ping: Unit -> *#[U32] }
#entry func main (): U32 =>
  let r = { a: #[10, 20], b: #[30, 40] }
  let leaked: *#[U32] = freeze #[0]
  with Ping = { ping: func () =>
      let f = freeze r.a
      r.b[0] := 31
      return f
  }:
    use f <- Ping.ping ()
    leaked := f
  r.a[0] := 999
  return leaked[0] * 1000 + r.a[0]
`,
    "spent_value",
  );

  await compileExpectedFailure(
    `
type Store is effect = { get: Unit -> #[U32] }
#entry func main (): U32 =>
  let arr = #[10, 20]
  let alias: #[U32] = #[]
  with Store = { get: func () =>
      arr[1] := 21
      return arr
  }:
    use x <- Store.get ()
    alias := x
  arr[0] := 999
  return alias[0] * 1000 + arr[0]
`,
    "result_not_owned",
  );

  await compileExpectedFailure(
    `
type Store is effect = { get: Unit -> { x: #[U32] } }
#entry func main (): U32 =>
  let arr = #[10, 20]
  let alias: #[U32] = #[]
  with Store = { get: func () =>
      arr[1] := 21
      return { x: arr }
  }:
    use r <- Store.get ()
    alias := r.x
  arr[0] := 999
  return alias[0] * 1000 + arr[0]
`,
    "result_not_owned",
  );

  await compileExpectedFailure(
    `
type FreezeEff is effect = { go: Unit -> Unit }
#entry func main (): U32 =>
  let arr = #[10, 20]
  with FreezeEff = { go: func () =>
      arr[1] := 21
      let _ = freeze arr
      return ()
  }:
    use FreezeEff.go ()
  arr[0] := 99
  return arr[0]
`,
    "spent_value",
  );

  await compileAndRun(
    `
type Bump is effect = { step: Unit -> Unit }
#entry func main (): U32 =>
  let arr = #[10, 20]
  with Bump = { step: func () =>
      arr[0] := 11
      arr[1] := 22
      return ()
  }:
    use Bump.step ()
  return arr[0] * 100 + arr[1]
`,
    (guest) => {
      equal(guest.call("main", null), 1122);
    },
  );

  await compileExpectedFailure(
    `
type Mod is effect = { touch: Unit -> Unit }
#entry func main (): U32 =>
  let x = #[1, 2]
  let y = #[10, 20]
  let z: #[U32] = fork x:
    with Mod = { touch: func () => y := y }:
      use Mod.touch ()
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

#entry func test_c10a (): U32 =>
  let base = big 10 0
  let sum = 0
  for idx in 0..3:
    let next = base
    next.a := self + 100
    sum := sum + next.a
  return sum

#entry func test_c10b (flag: Bool): U32 =>
  let x = big 10 0
  let k = 0
  if flag:
    let x2 = x
    x2.a := 999
    k := x2.a
  else:
    x := big 20 0
  return x.a * 1000 + k

#entry func test_c10c (flag: Bool): U32 =>
  let a = #[10, 20]
  let b: #[U32] = #[]
  if flag:
    b := @array.append a 99
  else:
    a := #[1, 2]
  b[0] := 777
  return a.length * 1000 + a[0]

#entry func test_c11 (): U32 =>
  let orig = big 1 2
  let res = mutate_copy orig
  return orig.b * 1000 + res

#entry func test_c12 (): U32 =>
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

#entry func test_c13 (): U32 =>
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
    "main.blot": `
import * as simd from "std/simd"

func bits (x: F32): U32 =>
  let (b, _, _, _) = simd.f32_bits (x, 0.0, 0.0, 0.0)
  return b

#entry func test_simd_store (idx: U32): U32 =>
  let a = #[10, 20, 30, 40]
  let before = a[idx]
  let _ = @simd.store a idx (99, 88, 77, 66)
  let after = a[idx]
  return before * 100 + after

#entry func test_defer_nan (zero: F32): #[U32] =>
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

#entry func test_staging_eq (): U32 =>
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

#entry func test_carries (): U32 =>
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

#entry func test_comptime_misc (): U32 =>
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
  const dir = await Deno.makeTempDir({ prefix: "blot-simd-reloc-" });
  const entry = `${dir}/main.blot`;
  const cases: Array<{ name: string; v1: string; v2: string; arg: number }> = [
    {
      name: "affine_init",
      v1: `#entry func run (n: U32): U32 =>
  let arr = @array.fill n 0
  let s: U32 = 1
  for i in 0..n:
    s := s * 1664525 + 1013904223
    arr[i] := s
  return arr[0] ^ arr[n - 1]
`,
      v2: `#entry func run (n: U32): U32 =>
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
      v1: `#entry func run (n: U32): U32 =>
  let s: U32 = 1
  let acc: U32 = 0
  for _ in 0..n:
    s := s * 1664525 + 1013904223
    acc := acc ^ (s & 255)
  return acc
`,
      v2: `#entry func run (n: U32): U32 =>
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
#entry func run (n: U32): U32 =>
  let p = @array.fill n { x: 4.0, y: 8.0 }
  for i in 0..n:
    let q = p[i]
    p[i] := { x: q.x * 0.25, y: q.y * 0.25 }
  return @f32.to_u32 (p[0].x + p[n - 1].x)
`,
      v2: `type Vec2 = { x: F32, y: F32 }
#entry func run (n: U32): U32 =>
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
      v1: `#entry func run (n: U32): U32 =>
  let flags = @array.fill n true
  let acc: U32 = 0
  for i in 0..flags.length:
    if flags[i]:
      acc := @type.call "add" acc 1
  return acc
`,
      v2: `#entry func run (n: U32): U32 =>
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
    { "main.blot": `test "returns u32" => 42\n` },
    "main.blot",
    { testMode: true },
  );
  equal(badTest.success, false);

  await compileExpectedFailure(
    `#entry func main (xs: #[3; U32]): U32 => xs[0]\n`,
    "entry_type",
  );

  await compileExpectedFailure(
    `
type Ask is effect = { get: Unit -> U32 }
#entry func main (): U32 =>
  let r: U32 = 0
  with Ask = { get: func () => 1 }, Ask = { get: func () => 2 }:
    use v <- Ask.get ()
    r := v
  return r
`,
    "duplicate_request_handler",
  );

  await compileExpectedFailure(
    `
type Pair = { a: U32, b: U32 }
#entry func main (): U32 =>
  #for f in #fields Pair:
    let _g = func () => f.index
  return 0
`,
    "unsupported",
  );
});
