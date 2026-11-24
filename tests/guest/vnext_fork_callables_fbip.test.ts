import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

Deno.test("vNext Checkpoint 2: speculative fork with arrays, grow/resize, seal, nested fork, own helpers, and fresh/copy escapes", async () => {
  await compileAndRun(
    `
func bump_first (xs: own #[U32]) -> (delta: U32): #[U32] =>
  xs[0] := xs[0] + delta
  return xs

func test_basic_fork (): U32 =>
  let xs = #[10, 20, 30]
  let spec = fork xs:
    xs[0] := 99
    xs[0] := 100
    xs[2] := 300
    return xs[0] + xs[1] + xs[2]
  // Original xs must be bit-for-bit untouched
  return spec * 1000 + xs[0] + xs[1] + xs[2]

func test_grow_fork (): U32 =>
  let buf: #[U32] = #[1, 2]
  let spec = fork buf:
    for i in 0..20:
      @storage.push buf (i + 10)
    buf[0] := 999
    return buf.length * 10000 + buf[0] + buf[21]
  // After rollback, buf still has length 2 and values [1, 2], and can still grow!
  @storage.push buf 3
  return spec + buf.length * 100 + buf[0] + buf[1] + buf[2]

func test_resize_and_seal_fork (): U32 =>
  let buf: #[U32] = #[5, 10, 15, 20]
  let spec = fork buf:
    let p = @storage.pop buf
    @storage.truncate buf 2
    @storage.push buf 77
    return p + buf.length * 100 + buf[0] + buf[2]
  // After rollback, buf is still #[5, 10, 15, 20] and push still works!
  @storage.push buf 25
  return spec * 1000 + buf.length * 100 + buf[0] + buf[1] + buf[2] + buf[3] + buf[4]

func test_nested_and_own_fork (): U32 =>
  let a = #[1, 2]
  let b = #[10, 20]
  let outer_res = fork a, b:
    a := bump_first a 100
    b[1] := 50
    let inner_res = fork a:
      a[0] := 999
      return a[0] + b[1]
    // After inner fork, a[0] is back to 101 (outer fork's mutation), NOT 999!
    return inner_res * 1000 + a[0] + b[1]
  // After outer fork, a is [1, 2] and b is [10, 20]
  return outer_res + a[0] + b[1]

func test_fork_returns_fresh_and_copy (): U32 =>
  let xs = #[3, 4, 5]
  let fresh: #[U32] = fork xs:
    xs[0] := 50
    let out = #[xs[0], xs[1], 0]
    out[2] := 77
    return out
  let snap: #[U32] = fork xs:
    xs[1] := 88
    return copy xs
  // xs is still [3, 4, 5]; fresh is [50, 4, 77]; snap is [3, 88, 5]
  return fresh[0] + fresh[1] + fresh[2] + snap[0] + snap[1] + snap[2] + xs[0] + xs[1] + xs[2]

entry func run_basic (): U32 => test_basic_fork ()
entry func run_grow (): U32 => test_grow_fork ()
entry func run_resize (): U32 => test_resize_and_seal_fork ()
entry func run_nested (): U32 => test_nested_and_own_fork ()
entry func run_fresh (): U32 => test_fork_returns_fresh_and_copy ()
`,
    (guest) => {
      // spec = 100 + 20 + 300 = 420; xs = 10 + 20 + 30 = 60 => 420060
      equal(guest.call("run_basic", null), 420060);
      // spec = 22*10000 + 999 + 29 = 221028; after: buf=[1,2,3], 3*100 + 6 = 306 => 221334
      equal(guest.call("run_grow", null), 221334);
      // spec = 20 + 3*100 + 5 + 77 = 402; after: buf=[5,10,15,20,25], 5*100 + 75 = 575 => 402575
      equal(guest.call("run_resize", null), 402575);
      // inner_res = 999 + 50 = 1049; outer_res = 1049*1000 + 101 + 50 = 1049151; after: 1 + 20 = 21 => 1049172
      equal(guest.call("run_nested", null), 1049172);
      // fresh: 50+4+77=131; snap: 3+88+5=96; xs: 3+4+5=12 => 239
      equal(guest.call("run_fresh", null), 239);
    },
  );
});

Deno.test("vNext Checkpoint 2: fork rejections (aliased outer, escaping forked storage/freeze, Foreign effect)", async () => {
  await compileExpectedFailure(
    `
func bad (xs: #[U32]): U32 =>
  return fork xs:
    xs[0] := 1
    return xs[0]
entry func main (): U32 => bad #[1, 2]
`,
    "aliased_update",
  );

  await compileExpectedFailure(
    `
entry func main (): #[U32] =>
  let xs = #[1, 2, 3]
  return fork xs:
    xs[0] := 9
    return xs
`,
    "result_not_owned",
  );

  await compileExpectedFailure(
    `
func bump (xs: own #[U32]): #[U32] =>
  xs[0] := 9
  return xs
entry func main (): #[U32] =>
  let xs = #[1, 2, 3]
  return fork xs:
    let ys = bump xs
    return ys
`,
    "result_not_owned",
  );

  await compileExpectedFailure(
    `
entry func main (): U32 =>
  let xs = #[1, 2, 3]
  let leaked: *#[U32] = fork xs:
    xs[0] := 9
    return freeze xs
  return leaked[0]
`,
    "result_not_owned",
  );

  await compileExpectedFailure(
    `
entry func main (host: U32 -> U32 ! {Foreign}): U32 ! {Foreign} =>
  let xs = #[1, 2]
  return fork xs:
    return use host xs[0]
`,
    "sealed_effect",
  );

  await compileExpectedFailure(
    `
entry func main (): U32 =>
  let xs = #[1, 2]
  let ys = #[3, 4]
  return fork xs:
    ys[0] := 99
    return xs[0] + ys[0]
`,
    "aliased_update",
  );
});

Deno.test("vNext Checkpoint 2: 2B frozen closures *(A -> B) and capture rejections", async () => {
  await compileAndRun(
    `
type Pipeline is data = $Pipeline {
  step: *(U32 -> U32)
}

func add (a: U32) -> (b: U32): U32 => a + b

func make_adder (scale: U32): *(U32 -> U32) =>
  return freeze (func x => x + scale)

func make_lookup (): *(U32 -> U32) =>
  let table: *#[U32] = freeze #[10, 20, 30, 40]
  return freeze (func i => table[i])

func make_pipeline (offset: U32): Pipeline =>
  return $Pipeline { step: freeze (add offset) }

func apply_all (fs: #[*(U32 -> U32)]) -> (x: U32): U32 =>
  let v = x
  for f in fs:
    v := f v
  return v

entry func run_closures (x: U32): U32 =>
  let f1 = make_adder 5
  let f2 = make_lookup ()
  let p = make_pipeline 7
  let fs: #[*(U32 -> U32)] = #[f1, p.step]
  return apply_all fs x + f2 2
`,
    (guest) => {
      // apply_all [x+5, x+7] 10 => 22; f2 2 => 30; total = 52
      equal(guest.call("run_closures", 10), 52);
    },
  );

  await compileExpectedFailure(
    `
entry func bad (): U32 =>
  let arr = #[10, 20, 30]
  let f: *(U32 -> U32) = freeze (func i => arr[i])
  return f 0
`,
    "own_function_value",
  );

  await compileExpectedFailure(
    `
func pick (arr: #[U32]) -> (i: U32): U32 => arr[i]
entry func bad (): U32 =>
  let arr = #[10, 20, 30]
  let f: *(U32 -> U32) = freeze (pick arr)
  return f 0
`,
    "own_function_value",
  );

  await compileExpectedFailure(
    `
func bad_wrap (cb: U32 -> U32): *(U32 -> U32) => freeze cb
entry func main (): U32 =>
  let f = bad_wrap (func x => x + 1)
  return f 5
`,
    "own_function_value",
  );
});

Deno.test("vNext Checkpoint 2: #[n; T] linked-length loops and FBIP boxed sum/record reuse & aliasing safety", async () => {
  await compileAndRun(
    `
type Tree is data =
  | $Leaf U32
  | $Node { left: Tree, value: U32, right: Tree }

type BigRec is data = $BigRec {
  f0: U32, f1: U32, f2: U32, f3: U32,
  f4: U32, f5: U32, f6: U32, f7: U32,
  f8: U32, f9: U32, f10: U32, f11: U32,
  f12: U32, f13: U32, f14: U32, f15: U32,
  f16: U32, f17: U32
}

func dot_linked (a: #[n; U32]) -> (b: #[n; U32]): U32 =>
  let acc = 0
  for i in 0..a.length:
    acc := self + a[i] * b[i]
  return acc

func dot_shared_linked (a: *#[n; U32]) -> (b: *#[n; U32]): U32 =>
  let acc = 0
  for i in 0..a.length:
    acc := self + a[i] * b[i]
  return acc

func tree_value (t: Tree): U32 =>
  case t of
    $Leaf n => n
    $Node { left, value, right } => value + tree_value left + tree_value right

func test_fbip_tree (iters: U32): U32 =>
  let cur = $Node { left: $Leaf 1, value: 0, right: $Leaf 2 }
  for i in 0..iters:
    cur := case cur of
      $Node { left, value, right } => $Node { left: right, value: value + i, right: left }
      $Leaf n => $Leaf n
  return tree_value cur

func test_fbip_alias_safety (): U32 =>
  let a = $Node { left: $Leaf 1, value: 10, right: $Leaf 2 }
  let b = a
  b := case b of
    $Node { left, value, right } => $Node { left: left, value: 99, right: right }
    $Leaf n => $Leaf n
  // a must NOT be clobbered by updating b!
  return tree_value a * 1000 + tree_value b

func test_fbip_big_record (iters: U32): U32 =>
  let r = $BigRec {
    f0: 0, f1: 1, f2: 2, f3: 3,
    f4: 4, f5: 5, f6: 6, f7: 7,
    f8: 8, f9: 9, f10: 10, f11: 11,
    f12: 12, f13: 13, f14: 14, f15: 15,
    f16: 16, f17: 17
  }
  for i in 0..iters:
    r.f0 := self + i
  return r.f0 + r.f17

func test_linked_dot (): U32 =>
  let a: #[4; U32] = #[1, 2, 3, 4]
  let b: #[4; U32] = #[10, 20, 30, 40]
  let sa: *#[4; U32] = freeze a
  let sb: *#[4; U32] = freeze b
  let c: #[4; U32] = #[1, 2, 3, 4]
  let d: #[4; U32] = #[10, 20, 30, 40]
  return dot_linked c d + dot_shared_linked sa sb

entry func run_dot (): U32 => test_linked_dot ()
entry func run_tree (iters: U32): U32 => test_fbip_tree iters
entry func run_alias (): U32 => test_fbip_alias_safety ()
entry func run_big (iters: U32): U32 => test_fbip_big_record iters
`,
    (guest) => {
      // 300 + 300 = 600
      equal(guest.call("run_dot", null), 600);
      // sum(0..20000) + 1 + 2 = 199990003 (reuses single $Node block in place)
      equal(guest.call("run_tree", 20000), 199990003);
      // tree_value a = 13, tree_value b = 102 => 13102
      equal(guest.call("run_alias", null), 13102);
      // sum(0..20000) + 17 = 199990017 (reuses single $BigRec block in place)
      equal(guest.call("run_big", 20000), 199990017);
    },
  );

  // Verify linked #[n; U32] eliminates runtime.address bounds checks inside dot's loop body.
  // Inspect the Wasm `name` section + code section to verify `named.dot` calls
  // ONLY `runtime.check` (no `runtime.address` calls) and elides the inline
  // bounds-check trap on `b[i]` when linked (`0` unreachable opcodes vs `> 0`).
  function parseWasmFunctions(wasm: Uint8Array): {
    bodies: Uint8Array[];
    names: Map<number, string>;
  } {
    let p = 8;
    const readU = () => {
      let v = 0, s = 0;
      while (true) {
        const b = wasm[p++];
        v |= (b & 127) << s;
        if (!(b & 128)) return v;
        s += 7;
      }
    };
    const bodies: Uint8Array[] = [];
    while (p < wasm.length) {
      const id = wasm[p++];
      const size = readU();
      const end = p + size;
      if (id === 10) {
        const count = readU();
        for (let i = 0; i < count; i++) {
          const bsize = readU();
          bodies.push(wasm.slice(p, p + bsize));
          p += bsize;
        }
      }
      p = end;
    }
    const names = new Map<number, string>();
    const mod = new WebAssembly.Module(wasm as Uint8Array<ArrayBuffer>);
    const nameSecs = WebAssembly.Module.customSections(mod, "name");
    if (nameSecs.length > 0) {
      const b = new Uint8Array(nameSecs[0]);
      let q = 0;
      const ru = () => {
        let v = 0, s = 0;
        while (true) {
          const x = b[q++];
          v |= (x & 127) << s;
          if (!(x & 128)) return v;
          s += 7;
        }
      };
      while (q < b.length) {
        const subId = b[q++];
        const sz = ru();
        const subEnd = q + sz;
        if (subId === 1) {
          const cnt = ru();
          for (let i = 0; i < cnt; i++) {
            const idx = ru();
            const nl = ru();
            names.set(idx, new TextDecoder().decode(b.slice(q, q + nl)));
            q += nl;
          }
        }
        q = subEnd;
      }
    }
    return { bodies, names };
  }
  function findDotBody(wasm: Uint8Array): {
    body: Uint8Array;
    names: Map<number, string>;
  } {
    const { bodies, names } = parseWasmFunctions(wasm);
    for (const [idx, nm] of names) {
      if (nm.startsWith("named.dot#") && idx < bodies.length) {
        return { body: bodies[idx], names };
      }
    }
    throw new Error("Could not find named.dot in Wasm name section");
  }
  const callsInDot = (wasm: Uint8Array): string[] => {
    const { body: dotBody, names } = findDotBody(wasm);
    let q = 0;
    const readBU = () => {
      let v = 0, s = 0;
      while (true) {
        const b = dotBody[q++];
        v |= (b & 127) << s;
        if (!(b & 128)) return v;
        s += 7;
      }
    };
    const decls = readBU();
    for (let i = 0; i < decls; i++) {
      readBU();
      q++;
    }
    const calls: string[] = [];
    while (q < dotBody.length) {
      const op = dotBody[q++];
      if (op === 0x10) {
        const callee = readBU();
        calls.push(names.get(callee) ?? `#${callee}`);
      } else if (op === 0x02 || op === 0x03 || op === 0x04) q++;
      else if (op === 0x0c || op === 0x0d || op === 0x20 || op === 0x21 || op === 0x22 || op === 0x23 || op === 0x24 || op === 0x41) {
        while ((dotBody[q++] & 0x80) !== 0) {}
      } else if (op === 0x28 || op === 0x36) {
        while ((dotBody[q++] & 0x80) !== 0) {}
        while ((dotBody[q++] & 0x80) !== 0) {}
      } else if (op === 0x43) q += 4;
    }
    return calls;
  };
  let linkedCalls: string[] = [];
  let unlinkedCalls: string[] = [];
  await compileAndRun(
    `
func dot (a: #[n; U32]) -> (b: #[n; U32]): U32 =>
  let acc = 0
  for i in 0..a.length:
    acc := self + a[i] * b[i]
  return acc
entry func main (): U32 =>
  let a: #[4; U32] = #[1, 2, 3, 4]
  let b: #[4; U32] = #[10, 20, 30, 40]
  return dot a b
`,
    (guest, bytes) => {
      equal(guest.call("main", null), 300);
      linkedCalls = callsInDot(bytes);
    },
  );
  await compileAndRun(
    `
func dot (a: #[U32]) -> (b: #[U32]): U32 =>
  let acc = 0
  for i in 0..a.length:
    acc := self + a[i] * b[i]
  return acc
entry func main (): U32 =>
  let a = #[1, 2, 3, 4]
  let b = #[10, 20, 30, 40]
  return dot a b
`,
    (guest, bytes) => {
      equal(guest.call("main", null), 300);
      unlinkedCalls = callsInDot(bytes);
    },
  );
  function trapsInDot(wasm: Uint8Array): number {
    const { body: dotBody } = findDotBody(wasm);
    let q = 0;
    const readBU = () => {
      let v = 0, s = 0;
      while (true) {
        const b = dotBody[q++];
        v |= (b & 127) << s;
        if (!(b & 128)) return v;
        s += 7;
      }
    };
    const decls = readBU();
    for (let i = 0; i < decls; i++) {
      readBU();
      q++;
    }
    let traps = 0;
    while (q < dotBody.length) {
      const op = dotBody[q++];
      if (op === 0x00) traps++;
      else if (op === 0x02 || op === 0x03 || op === 0x04) q++;
      else if (op === 0x0c || op === 0x0d || op === 0x10 || op === 0x20 || op === 0x21 || op === 0x22 || op === 0x23 || op === 0x24 || op === 0x41) {
        while ((dotBody[q++] & 0x80) !== 0) {}
      } else if (op === 0x28 || op === 0x36) {
        while ((dotBody[q++] & 0x80) !== 0) {}
        while ((dotBody[q++] & 0x80) !== 0) {}
      } else if (op === 0x43) q += 4;
    }
    return traps;
  }
  let linkedTraps = -1;
  let unlinkedTraps = -1;
  await compileAndRun(
    `
func dot (a: #[n; U32]) -> (b: #[n; U32]): U32 =>
  let acc = 0
  for i in 0..a.length:
    acc := self + a[i] * b[i]
  return acc
entry func main (): U32 =>
  let a: #[4; U32] = #[1, 2, 3, 4]
  let b: #[4; U32] = #[10, 20, 30, 40]
  return dot a b
`,
    (_guest, bytes) => { linkedTraps = trapsInDot(bytes); },
  );
  await compileAndRun(
    `
func dot (a: #[U32]) -> (b: #[U32]): U32 =>
  let acc = 0
  for i in 0..a.length:
    acc := self + a[i] * b[i]
  return acc
entry func main (): U32 =>
  let a = #[1, 2, 3, 4]
  let b = #[10, 20, 30, 40]
  return dot a b
`,
    (_guest, bytes) => { unlinkedTraps = trapsInDot(bytes); },
  );
  if (
    linkedCalls.some((c) => c !== "runtime.check") ||
    unlinkedCalls.some((c) => c !== "runtime.check") ||
    linkedTraps !== 0 ||
    unlinkedTraps <= 0
  ) {
    throw new Error(`Expected linked #[n; U32] dot to call only runtime.check and elide b[i] bounds trap (0 traps vs >0 unlinked), got linkedTraps=${linkedTraps} unlinkedTraps=${unlinkedTraps} linkedCalls=${JSON.stringify(linkedCalls)} unlinkedCalls=${JSON.stringify(unlinkedCalls)}`);
  }
});
