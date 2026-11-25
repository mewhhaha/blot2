import { strict as assert } from "node:assert";
import { compileAndRun, equal } from "./compile_helpers.ts";
import { instantiateGuest } from "../../host/guest.ts";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";

const compilerExecutable =
  Deno.args[0] ??
  new URL("../../compiler-goose/build/blotc-goose", import.meta.url).pathname;
const stdRoot = new URL("../../std", import.meta.url).pathname;
const preludePath = new URL("../../std/prelude.blot", import.meta.url).pathname;

async function compileToWasm(
  source: string,
  options: { stdRoot?: string } = {},
): Promise<Uint8Array<ArrayBuffer>> {
  let outBytes!: Uint8Array<ArrayBuffer>;
  await compileAndRun(
    source,
    (_guest, bytes) => {
      outBytes = bytes;
    },
    { stdRoot: options.stdRoot },
  );
  return outBytes;
}

// --- Binary decoder for `blot:kernels` (v1) & `blot:processes` (v1) (§3.2) ---

interface WireSchema {
  kind: number;
  wireTag: number;
  stride: number;
  wordTags: number[];
  schemaHash: bigint;
}

interface KernelSectionEntry {
  name: string;
  flags: number;
  inSchema: WireSchema;
  outSchema: WireSchema;
  ioSchemaHash: bigint;
  implHash: bigint;
  bindingHash: bigint;
  ctxSchema?: WireSchema;
  ctxExport?: string;
  clearExport?: string;
}

interface ProcessSectionEntry {
  name: string;
  initExport: string;
  stepExport: string;
  configSchema: WireSchema;
  cmdSchema: WireSchema;
  replySchema: WireSchema;
}

class Reader {
  pos = 0;
  constructor(readonly bytes: Uint8Array) {}
  u8(): number {
    assert(this.pos < this.bytes.length, "unexpected EOF reading u8");
    return this.bytes[this.pos++];
  }
  uleb(): number {
    let result = 0;
    let shift = 0;
    while (true) {
      const b = this.u8();
      result |= (b & 0x7f) << shift;
      if ((b & 0x80) === 0) return result >>> 0;
      shift += 7;
    }
  }
  u64(): bigint {
    assert(this.pos + 8 <= this.bytes.length, "unexpected EOF reading u64");
    let v = 0n;
    for (let i = 0; i < 8; i++) {
      v |= BigInt(this.bytes[this.pos++]) << BigInt(i * 8);
    }
    return v;
  }
  str(): string {
    const len = this.uleb();
    assert(this.pos + len <= this.bytes.length, "unexpected EOF reading str");
    const s = new TextDecoder().decode(
      this.bytes.subarray(this.pos, this.pos + len),
    );
    this.pos += len;
    return s;
  }
  wireSchema(): WireSchema {
    const kind = this.u8();
    const wireTag = this.u8();
    const stride = this.uleb();
    const wordTags: number[] = [];
    if (kind === 1) {
      for (let i = 0; i < stride; i++) wordTags.push(this.u8());
    }
    const schemaHash = this.u64();
    return { kind, wireTag, stride, wordTags, schemaHash };
  }
}

function parseKernelsSection(bytes: Uint8Array): {
  version: number;
  transportBudget: number;
  kernels: KernelSectionEntry[];
} {
  const r = new Reader(bytes);
  const version = r.uleb();
  const transportBudget = r.uleb();
  const count = r.uleb();
  const kernels: KernelSectionEntry[] = [];
  for (let i = 0; i < count; i++) {
    const name = r.str();
    const flags = r.u8();
    const inSchema = r.wireSchema();
    const outSchema = r.wireSchema();
    const ioSchemaHash = r.u64();
    const implHash = r.u64();
    const bindingHash = r.u64();
    const entry: KernelSectionEntry = {
      name,
      flags,
      inSchema,
      outSchema,
      ioSchemaHash,
      implHash,
      bindingHash,
    };
    if ((flags & 1) !== 0) {
      entry.ctxSchema = r.wireSchema();
      entry.ctxExport = r.str();
      entry.clearExport = r.str();
    }
    kernels.push(entry);
  }
  equal(r.pos, bytes.length);
  return { version, transportBudget, kernels };
}

function parseProcessesSection(bytes: Uint8Array): {
  version: number;
  transportBudget: number;
  processes: ProcessSectionEntry[];
} {
  const r = new Reader(bytes);
  const version = r.uleb();
  const transportBudget = r.uleb();
  const count = r.uleb();
  const processes: ProcessSectionEntry[] = [];
  for (let i = 0; i < count; i++) {
    const name = r.str();
    const initExport = r.str();
    const stepExport = r.str();
    const configSchema = r.wireSchema();
    const cmdSchema = r.wireSchema();
    const replySchema = r.wireSchema();
    processes.push({
      name,
      initExport,
      stepExport,
      configSchema,
      cmdSchema,
      replySchema,
    });
  }
  equal(r.pos, bytes.length);
  return { version, transportBudget, processes };
}

function pairToU64(lo: number, hi: number): bigint {
  return (BigInt(hi >>> 0) << 32n) | BigInt(lo >>> 0);
}

// ============================================================================
// Acceptance Law #1: Recursive nodes, 80-byte wide copiedBox with nested
// owners, projected interior box, nested temp owners (stack CopiedHeap +
// StealHeap), grown-then-truncated length==0 #[U32], and 0 heap_live_bytes
// drift across 100+ repeated proc_step array replies.
// ============================================================================

Deno.test("Phase 3 Law #1: recursive node, 80B wide box, interior projection, nested temp owners, truncated #[U32], and zero heap drift", async () => {
  await compileAndRun(
    `type RecNode is data = $Empty | $Node { a: U32, b: U32, c: U32, d: U32, next: RecNode }

type WideBox is data = $WideBox {
  w0: U32, w1: U32, w2: U32, w3: U32,
  w4: U32, w5: U32, w6: U32, w7: U32,
  w8: U32, w9: U32, w10: U32, w11: U32,
  w12: U32, w13: U32, w14: U32, w15: U32,
  nested_stack: #[#[U32]],
  nested_grow: #[#[U32]]
}

type OuterBox is data = $OuterBox {
  tag_id: U32,
  big: WideBox
}

type FullState is data = $FullState {
  chain: RecNode,
  outer: OuterBox,
  trunc_buf: #[U32],
  turn: U32
}

type ProjState is data = $ProjState { active: WideBox, wrap: OuterBox }

func make_wide (seed: U32): WideBox =>
  let s0 = #[seed, @u32.add seed 1]
  let s1 = #[@u32.add seed 2, @u32.add seed 3]
  let ns: #[#[U32]] = #[s0, s1]
  let g0: #[U32] = #[@u32.add seed 10]
  @storage.push g0 (@u32.add seed 11)
  let g1: #[U32] = #[@u32.add seed 20]
  @storage.push g1 (@u32.add seed 21)
  let ng: #[#[U32]] = #[g0]
  @storage.push ng g1
  return $WideBox {
    w0: seed, w1: 1, w2: 2, w3: 3,
    w4: 4, w5: 5, w6: 6, w7: 7,
    w8: 8, w9: 9, w10: 10, w11: 11,
    w12: 12, w13: 13, w14: 14, w15: 15,
    nested_stack: ns,
    nested_grow: ng
  }

func sum_chain (n: RecNode): U32 =>
  let cur = n
  let acc = 0
  for ever:
    let (done, next_acc, next_cur) = case cur of
      $Empty => (true, acc, $Empty)
      $Node { a, b, c, d, next } => (false, @u32.add acc (@u32.add (@u32.add a b) (@u32.add c d)), next)
    acc := next_acc
    cur := next_cur
    if done:
      break
  return acc

func p_init (seed: U32): FullState =>
  let c0 = $Node { a: seed, b: 1, c: 2, d: 3, next: $Empty }
  let c1 = $Node { a: @u32.add seed 10, b: 4, c: 5, d: 6, next: c0 }
  let wb = make_wide seed
  let outer = $OuterBox { tag_id: 77, big: wb }
  let tb: #[U32] = #[]
  for i in 0..64:
    @storage.push tb i
  @storage.truncate tb 0
  return $FullState { chain: c1, outer: outer, trunc_buf: tb, turn: 0 }

func p_step (st: own FullState) -> (cmd: U32): (FullState, #[U32]) =>
  let $FullState { chain, outer, trunc_buf, turn } = st
  let $OuterBox { tag_id, big } = outer
  let $WideBox { w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11, w12, w13, w14, w15, nested_stack, nested_grow } = big
  // Read & mutate retained child elements across Turn 1, Turn 2, Turn 3!
  let s_val = @u32.add nested_stack[0][0] nested_stack[1][1]
  @storage.push nested_grow[0] (@u32.add cmd 100)
  let g_len = nested_grow[0].length
  let g_last = nested_grow[0][@u32.sub g_len 1]
  // Grow trunc_buf with real @storage.push calls (real heap allocation!) then truncate to 0!
  for i in 0..256:
    @storage.push trunc_buf (@u32.add turn i)
  let peak_len = trunc_buf.length
  @storage.truncate trunc_buf 0
  let chain_sum = sum_chain chain
  let next_chain = $Node { a: cmd, b: turn, c: 1, d: 2, next: chain }
  let next_wb = $WideBox {
    w0: w0, w1: w1, w2: w2, w3: w3,
    w4: w4, w5: w5, w6: w6, w7: w7,
    w8: w8, w9: w9, w10: w10, w11: w11,
    w12: w12, w13: w13, w14: w14, w15: w15,
    nested_stack: nested_stack,
    nested_grow: nested_grow
  }
  let next_outer = $OuterBox { tag_id: tag_id, big: next_wb }
  let reply = #[chain_sum, s_val, g_len, g_last, peak_len, trunc_buf.length, tag_id]
  return ($FullState { chain: next_chain, outer: next_outer, trunc_buf: trunc_buf, turn: @u32.add turn 1 }, reply)

// Projected interior copiedBox witness: Turn 0 stores OuterBox (84B -> 128B heap class in old_blocks),
// Turn 1 projects its interior wrap.big copiedBox (at offset +4 inside old_blocks!) into active,
// discards the old wrap, and Turn 2 & Turn 3 read & mutate active!
func proj_init (seed: U32): ProjState =>
  return $ProjState { active: make_wide 1, wrap: $OuterBox { tag_id: 99, big: make_wide seed } }

func proj_step (st: own ProjState) -> (cmd: U32): (ProjState, #[U32]) =>
  let $ProjState { active, wrap } = st
  let $OuterBox { tag_id: _, big } = wrap
  // On Turn 1: big is the interior copiedBox from old_blocks (wrap + 4) with seed 5!
  // On Turn 2: active holds the promoted interior copiedBox from Turn 1!
  let v_big = big.nested_stack[0][1]
  @storage.push big.nested_grow[0] (@u32.add cmd 50)
  let blen = big.nested_grow[0].length
  let blast = big.nested_grow[0][@u32.sub blen 1]
  let v_act = active.nested_stack[0][1]
  @storage.push active.nested_grow[0] (@u32.add cmd 80)
  let alen = active.nested_grow[0].length
  let alast = active.nested_grow[0][@u32.sub alen 1]
  return ($ProjState { active: big, wrap: $OuterBox { tag_id: cmd, big: active } }, #[v_big, blen, blast, v_act, alen, alast])

#process const full_proc: Process [U32, U32, #[U32]] = { init: p_init, step: p_step }
#process const proj_proc: Process [U32, U32, #[U32]] = { init: proj_init, step: proj_step }
`,
    (guest) => {
      // Turn 0 init
      guest.call("blot:proc_init:full_proc", 5);
      // Turn 1: chain_sum = (5+1+2+3) + (15+4+5+6) = 11 + 30 = 41
      // s_val = nested_stack[0][0] (5) + nested_stack[1][1] (8) = 13
      // nested_grow[0] had [15, 16], pushed 101 -> len 3, last 101
      const r1 = guest.call("blot:proc_step:full_proc", 1) as Uint32Array;
      assert.deepEqual(Array.from(r1), [41, 13, 3, 101, 256, 0, 77]);

      // Turn 2: chain_sum = 41 + (1+0+1+2) = 45; nested_grow[0] len 4, last 102
      const r2 = guest.call("blot:proc_step:full_proc", 2) as Uint32Array;
      assert.deepEqual(Array.from(r2), [45, 13, 4, 102, 256, 0, 77]);

      // Turn 3: chain_sum = 45 + (2+1+1+2) = 51; nested_grow[0] len 5, last 103
      const r3 = guest.call("blot:proc_step:full_proc", 3) as Uint32Array;
      assert.deepEqual(Array.from(r3), [51, 13, 5, 103, 256, 0, 77]);

      // Projected interior copiedBox (wrap.big at old_blocks+4) promoted & swapped across Turns 1, 2, 3!
      guest.call("blot:proc_init:proj_proc", 5);
      // Turn 1: big is seed=5 (v_big=6, len 2->3, last=51), active is seed=1 (v_act=2, len 2->3, last=81)
      const pr1 = guest.call("blot:proc_step:proj_proc", 1) as Uint32Array;
      assert.deepEqual(Array.from(pr1), [6, 3, 51, 2, 3, 81]);
      // Turn 2: swapped! big is old active (seed=1, v_big=2, len 3->4, last=52), active is old big (seed=5, v_act=6, len 3->4, last=82)
      const pr2 = guest.call("blot:proc_step:proj_proc", 2) as Uint32Array;
      assert.deepEqual(Array.from(pr2), [2, 4, 52, 6, 4, 82]);
      // Turn 3: swapped again! big is seed=5 (v_big=6, len 4->5, last=53), active is seed=1 (v_act=2, len 4->5, last=83)
      const pr3 = guest.call("blot:proc_step:proj_proc", 3) as Uint32Array;
      assert.deepEqual(Array.from(pr3), [6, 5, 53, 2, 5, 83]);
    },
  );

  // Dedicated zero-drift witness in a clean Store: 110 repeated turns allocating 256 KiB reply +
  // 256 KiB grown-then-truncated length==0 #[U32], followed by allocating 127.75 MiB of 128 MiB heap_budget!
  // Any single leaked 256 KiB block from either Empty #[U32] or reply_pin_slot would immediately trap!
  await compileAndRun(
    `func alloc_heap_u32 (n: U32) -> (v: U32): #[U32] =>
  let out: #[U32] = #[]
  for _ in 0..n:
    @storage.push out v
  return out

func drift_init (_: U32): #[U32] =>
  let b: #[U32] = #[]
  return b

func drift_step (st: own #[U32]) -> (cmd: U32): (#[U32], #[U32]) =>
  if @u32.eq cmd 999:
    // Allocate 32+32+16+16+8+8+4+4+2+2+1+1 = 126 MiB live in heap_budget (128 MiB)!
    // Peak heap_top = 126 MiB + <1 MiB scratch free-lists < 128 MiB, while any >2 MiB heap_live_bytes leak traps!
    let a1 = alloc_heap_u32 8000000 1
    let a2 = alloc_heap_u32 8000000 2
    let b1 = alloc_heap_u32 4000000 3
    let b2 = alloc_heap_u32 4000000 4
    let c1 = alloc_heap_u32 2000000 5
    let c2 = alloc_heap_u32 2000000 6
    let d1 = alloc_heap_u32 1000000 7
    let d2 = alloc_heap_u32 1000000 8
    let e1 = alloc_heap_u32 500000 9
    let e2 = alloc_heap_u32 500000 10
    let f1 = alloc_heap_u32 250000 11
    let f2 = alloc_heap_u32 250000 12
    let s1 = @u32.add (@u32.add a1[0] a2[0]) (@u32.add b1[0] b2[0])
    let s2 = @u32.add (@u32.add c1[0] c2[0]) (@u32.add d1[0] d2[0])
    let s3 = @u32.add (@u32.add e1[0] e2[0]) (@u32.add f1[0] f2[0])
    return (st, #[@u32.add s1 (@u32.add s2 s3), a1.length])
  // Grow a fresh temporary #[U32] via real @storage.push to 256 KiB (65536 words) then truncate to 0!
  let tmp: #[U32] = #[]
  for i in 0..65536:
    @storage.push tmp i
  @storage.truncate tmp 0
  let rep = @array.fill 65536 cmd
  return (tmp, rep)

#process const drift_proc: Process [U32, U32, #[U32]] = { init: drift_init, step: drift_step }
`,
    (guest) => {
      guest.call("blot:proc_init:drift_proc", 0);
      // 520 turns * 256 KiB = 130 MiB > 128 MiB heap_budget for BOTH tmp AND reply!
      for (let t = 0; t < 520; t++) {
        const rep = guest.call("blot:proc_step:drift_proc", t) as Uint32Array;
        equal(rep.length, 65536);
        equal(rep[0], t);
        equal(rep[65535], t);
      }
      const finalCheck = guest.call(
        "blot:proc_step:drift_proc",
        999,
      ) as Uint32Array;
      assert.deepEqual(Array.from(finalCheck), [78, 8000000]);
    },
  );
});

// ============================================================================
// Page-0 offset 640 (`arena_oom_flag`): logical budget trap leaves offset 640 == 0,
// while physical retained-free-list fragmentation sets offset 640 == 1 and
// `blot:reset` clears it back to 0 (with zero extra Wasm exports!).
// ============================================================================

Deno.test("Phase 3: Page-0 offset 640 arena_oom_flag distinguishes logical OOM (0) vs physical fragmentation OOM (1)", async () => {
  const bytes = await compileToWasm(`
func alloc_heap_u32 (n: U32) -> (v: U32): #[U32] =>
  let out: #[U32] = #[]
  for _ in 0..n:
    @storage.push out v
  return out

#entry func logical_oom (_: #[U32]): #[U32] =>
  // Two 64 MiB blocks during second realloc -> logical heap_live_bytes (64+32+64 = 160 MiB > 128 MiB) -> offset 640 MUST be 0!
  let a = alloc_heap_u32 16000000 1
  let b = alloc_heap_u32 16000000 2
  return #[a[0], b[0]]

#entry func warm_class_a (_: #[U32]): #[U32] =>
  // Carve 4 x 16 MiB blocks (64 MiB total in heap_top, freed to 16 MiB free list on return)
  let a = alloc_heap_u32 4000000 1
  let b = alloc_heap_u32 4000000 2
  let c = alloc_heap_u32 4000000 3
  let d = alloc_heap_u32 4000000 4
  return #[a[0], b[0], c[0], d[0]]

#entry func alloc_64m (_: #[U32]): #[U32] =>
  // Fresh: needs 64M+32M+16M+... = 128M -> succeeds!
  // Warm after warm_class_a: 64M already sitting in 16 MiB free list -> logical heap_live_bytes <= 96 MiB passes,
  // yet physical heap_top + 64M > 128M -> traps with Page-0 offset 640 == 1!
  let a = alloc_heap_u32 16000000 7
  return #[a[0]]
`);

  const mod = new WebAssembly.Module(bytes);
  // 1. Logical OOM leaves Page-0 offset 640 == 0
  {
    const inst = new WebAssembly.Instance(mod);
    const exp = inst.exports as Record<string, unknown>;
    const mem = exp["blot:memory"] as WebAssembly.Memory;
    const alloc = exp["blot:allocate"] as (n: number) => number;
    const reset = exp["blot:reset"] as () => void;
    const fn = exp["logical_oom"] as (p: number) => number;
    reset();
    const p = alloc(4);
    new Uint32Array(mem.buffer, p, 1)[0] = 0;
    assert.throws(() => fn(p));
    equal(new DataView(mem.buffer).getUint32(640, true), 0);
  }

  // 2. Physical retained-free-list fragmentation sets Page-0 offset 640 == 1, cleared by blot:reset!
  {
    // First verify alloc_64m succeeds on a fresh instance!
    const freshInst = new WebAssembly.Instance(mod);
    const fExp = freshInst.exports as Record<string, unknown>;
    const fMem = fExp["blot:memory"] as WebAssembly.Memory;
    (fExp["blot:reset"] as () => void)();
    const fp = (fExp["blot:allocate"] as (n: number) => number)(4);
    new Uint32Array(fMem.buffer, fp, 1)[0] = 0;
    const fOut = (fExp["alloc_64m"] as (p: number) => number)(fp);
    equal(new Uint32Array(fMem.buffer, fOut, 2)[1], 7);
    (fExp["blot:finish_invocation"] as () => void)();

    // Now warm with 4x16 MiB, finish, then call alloc_64m -> traps with offset 640 == 1!
    const warmInst = new WebAssembly.Instance(mod);
    const wExp = warmInst.exports as Record<string, unknown>;
    const wMem = wExp["blot:memory"] as WebAssembly.Memory;
    const wReset = wExp["blot:reset"] as () => void;
    const wAlloc = wExp["blot:allocate"] as (n: number) => number;
    const wFinish = wExp["blot:finish_invocation"] as () => void;
    wReset();
    const p1 = wAlloc(4);
    new Uint32Array(wMem.buffer, p1, 1)[0] = 0;
    (wExp["warm_class_a"] as (p: number) => number)(p1);
    wFinish();
    equal(new DataView(wMem.buffer).getUint32(640, true), 0);

    wReset();
    const p2 = wAlloc(4);
    new Uint32Array(wMem.buffer, p2, 1)[0] = 0;
    assert.throws(() => (wExp["alloc_64m"] as (p: number) => number)(p2));
    equal(new DataView(wMem.buffer).getUint32(640, true), 1);

    // blot:reset clears offset 640 back to 0!
    wFinish();
    wReset();
    equal(new DataView(wMem.buffer).getUint32(640, true), 0);
  }
});

// ============================================================================
// Depth-5000 Iterative Staging (O(1) Wasm call stack!)
// ============================================================================

Deno.test("Phase 3: depth-5000 recursive linked list staged iteratively without Wasm stack overflow", async () => {
  await compileAndRun(
    `type List is data = $Nil | $Cons { head: U32, tail: List }

func build_list (n: U32): List =>
  let cur = $Nil
  for i in 0..n:
    cur := $Cons { head: i, tail: self }
  return cur

func sum_list (xs: List): U32 =>
  let cur = xs
  let acc = 0
  for ever:
    let (done, next_acc, next_cur) = case cur of
      $Nil => (true, acc, $Nil)
      $Cons { head, tail } => (false, @u32.add acc head, tail)
    acc := next_acc
    cur := next_cur
    if done:
      break
  return acc

func l_init (n: U32): List => return build_list n
func l_step (st: own List) -> (add_head: U32): (List, U32) =>
  let next = $Cons { head: add_head, tail: st }
  return (next, sum_list next)

#process const deep_list: Process [U32, U32, U32] = { init: l_init, step: l_step }
`,
    (guest) => {
      guest.call("blot:proc_init:deep_list", 5000);
      const expectedBase = (5000 * 4999) / 2;
      equal(guest.call("blot:proc_step:deep_list", 7), expectedBase + 7);
      equal(guest.call("blot:proc_step:deep_list", 13), expectedBase + 20);
    },
  );
});

// ============================================================================
// Acceptance Law #2: ABI 8 array-to-array callback growth (8B req in 16B bank
// + 12B/20B host reply without blot:reset), heap-at-limit transport packet,
// and unmodified Deno strict export check with zero extra exports + unexported
// memory for scalar-only #process.
// ============================================================================

Deno.test("Phase 3 Law #2: array-to-array callback growth, heap-at-limit packet, and scalar-only process unexported memory", async () => {
  const bytes = await compileToWasm(`
#entry func roundtrip_cb (cb: Array U32 -> Array U32): Array U32 =>
  // 2-word (8B payload + 4B hdr = 12B) fits in 16B bank; host replies with 3 words (16B) and 5 words (24B) without blot:reset!
  let r1 = cb #[11, 22]
  let r2 = cb #[33, 44]
  return #[r1.length, r1[0], r1[2], r2.length, r2[0], r2[4]]

func alloc_heap_u32 (n: U32) -> (v: U32): #[U32] =>
  let out: #[U32] = #[]
  for _ in 0..n:
    @storage.push out v
  return out

#entry func heap_at_limit_packet (xs: #[U32]): #[U32] =>
  // Fill heap_live_bytes to 127.75 MiB (only 256 KiB free in 128 MiB heap_budget!)
  let a = alloc_heap_u32 16000000 1
  let b = alloc_heap_u32 8000000 2
  let c = alloc_heap_u32 4000000 3
  let d = alloc_heap_u32 2000000 4
  let e = alloc_heap_u32 1000000 5
  let f = alloc_heap_u32 500000 6
  let g = alloc_heap_u32 250000 7
  let h = alloc_heap_u32 125000 8
  let k = alloc_heap_u32 62500 9
  // Return a 1 MiB (262144-word) packet (> 256 KiB free heap!) proving transport pool is 100% independent of heap_budget!
  let out = @array.fill 262144 (@u32.add xs[0] (@u32.add a[0] k[0]))
  return out
`);

  for (const asynchronous of [false, true]) {
    const guest = await instantiateGuest(bytes, { asynchronous });
    try {
      let calls = 0;
      const cb = guest.capability({
        parameter: "Array U32",
        result: "Array U32",
        call: (req) => {
          calls++;
          if (calls === 1) {
            assert.deepEqual(Array.from(req), [11, 22]);
            return new Uint32Array([101, 202, 303]); // 12B payload (16B packet)
          }
          assert.deepEqual(Array.from(req), [33, 44]);
          return new Uint32Array([10, 20, 30, 40, 50]); // 20B payload (24B packet -> grows bank with used!=0!)
        },
      });
      const res = (
        asynchronous
          ? await guest.callAsync("roundtrip_cb", cb)
          : guest.call("roundtrip_cb", cb)
      ) as Uint32Array;
      assert.deepEqual(Array.from(res), [3, 101, 303, 5, 10, 50]);

      const pkt = (
        asynchronous
          ? await guest.callAsync("heap_at_limit_packet", new Uint32Array([7]))
          : guest.call("heap_at_limit_packet", new Uint32Array([7]))
      ) as Uint32Array;
      equal(pkt.length, 262144);
      equal(pkt[0], 17);
      equal(pkt[262143], 17);
    } finally {
      guest.dispose();
    }
  }

  // Scalar-only #process MUST NOT export blot:memory / blot:allocate / blot:reset,
  // yet still loads cleanly under unmodified Deno host/guest.ts strict export check!
  const scalarProcBytes = await compileToWasm(`
type WrapU32 is data = $WrapU32 { v: U32 }
func s_init (c: WrapU32): U32 => return c.v
func s_step (st: own U32) -> (cmd: WrapU32): (U32, WrapU32) =>
  let next = @u32.add st cmd.v
  return (next, $WrapU32 { v: next })

#process const scalar_only: Process [WrapU32, WrapU32, WrapU32] = { init: s_init, step: s_step }
`);
  const mod = new WebAssembly.Module(scalarProcBytes);
  const expNames = new Set(WebAssembly.Module.exports(mod).map((e) => e.name));
  assert(!expNames.has("blot:memory"), "scalar-only process must not export blot:memory");
  assert(!expNames.has("blot:allocate"), "scalar-only process must not export blot:allocate");
  assert(!expNames.has("blot:reset"), "scalar-only process must not export blot:reset");
  assert(expNames.has("blot:finish_invocation"));
  assert(expNames.has("blot:proc_init:scalar_only"));
  assert(expNames.has("blot:proc_step:scalar_only"));

  // Verify unmodified Deno host/guest.ts loads & runs scalar-only process cleanly!
  const guest = await instantiateGuest(scalarProcBytes);
  try {
    guest.call("blot:proc_init:scalar_only", 10);
    equal(guest.call("blot:proc_step:scalar_only", 5), 15);
    equal(guest.call("blot:proc_step:scalar_only", 27), 42);
  } finally {
    guest.dispose();
  }
});

// ============================================================================
// Inter-procedural escape_min_slot, box-aware 4-lane @simd.load/@simd.store,
// and trap-safe fork rollback (including @simd.store & heap push realloc).
// ============================================================================

Deno.test("Phase 3: inter-procedural escape_min_slot, box-aware @simd.load/@simd.store, and trap-safe fork", async () => {
  await compileAndRun(
    `type Big5 is data = $Big5 { a: U32, b: U32, c: U32, d: U32, e: U32 }

func helper_store_fresh (dst: own #[#[U32]]) -> (v: U32): #[#[U32]] =>
  let fresh = #[v, @u32.add v 1, @u32.add v 2]
  dst[0] := fresh
  return dst

func helper_simd_store_fresh (dst: own #[#[U32]]) -> (v: U32): #[#[U32]] =>
  let a = #[v]
  let b = #[@u32.add v 1]
  let c = #[@u32.add v 2]
  let d = #[@u32.add v 3]
  return @simd.store dst 0 (a, b, c, d)

#entry func test_escape_helpers (x: U32): #[U32] =>
  let holder: #[#[U32]] = #[#[0], #[0], #[0], #[0]]
  holder := helper_store_fresh holder x
  let a0 = holder[0][0]
  let a2 = holder[0][2]
  holder := helper_simd_store_fresh holder (@u32.add x 10)
  return #[a0, a2, holder[0][0], holder[1][0], holder[2][0], holder[3][0]]

#entry func test_box_simd_and_fork (x: U32): #[U32] =>
  let mk = func (k: U32): Big5 => return $Big5 { a: k, b: @u32.add k 1, c: @u32.add k 2, d: @u32.add k 3, e: @u32.add k 4 }
  let arr: #[Big5] = #[mk x, mk (@u32.add x 10), mk (@u32.add x 20), mk (@u32.add x 30)]
  let (b0, b1, b2, b3) = @simd.load arr 0
  // Roll back a 4-lane @simd.store of 5-word boxed structs inside fork!
  let _ = fork arr:
    let _ = @simd.store arr 0 (mk 90, mk 91, mk 92, mk 93)
    return 1
  // Roll back a growing #[U32] realloc inside nested fork!
  let g: #[U32] = #[1, 2]
  let _ = fork g:
    for i in 0..64:
      @storage.push g i
    let _ = fork g:
      @storage.push g 999
      return 2
    return 3
  return #[b0.e, b1.e, b2.e, b3.e, arr[0].a, arr[3].e, g.length, g[1]]
`,
    (guest) => {
      const esc = guest.call("test_escape_helpers", 5) as Uint32Array;
      assert.deepEqual(Array.from(esc), [5, 7, 15, 16, 17, 18]);
      const bf = guest.call("test_box_simd_and_fork", 1) as Uint32Array;
      // b0..b3.e = 5, 15, 25, 35; arr rolled back -> arr[0].a = 1, arr[3].e = 35; g rolled back -> len 2, g[1] = 2
      assert.deepEqual(Array.from(bf), [5, 15, 25, 35, 1, 35, 2, 2]);
    },
  );
});

// ============================================================================
// Physical-stride FlatNumeric (#[3; Big20Word], #[2; #[3; U32]], Bool),
// std/flat (@flat.encode/@flat.decode/@flat.schema_hash/@flat.kernel_*),
// #kernel (stateless, prepared, clear, count==0 pre-check, variable
// output + [0xffffffff] overflow sentinel), and custom sections blot:kernels
// & blot:processes v1 binary encoding.
// ============================================================================

Deno.test("Phase 3: FlatNumeric codecs, std/flat, kernel wrappers, [0xffffffff] overflow sentinel, and custom sections", async () => {
  const bytes = await compileToWasm(
    `import * as flat from "std/flat"

type Big20 is data = $Big20 {
  f0: U32, f1: U32, f2: U32, f3: U32, f4: U32,
  f5: U32, f6: U32, f7: U32, f8: U32, f9: U32,
  f10: U32, f11: U32, f12: U32, f13: U32, f14: U32,
  f15: U32, f16: U32, f17: U32, f18: U32, f19: U32
}

type Packet is data = $Packet {
  flag: Bool,
  grid: #[2; #[3; U32]],
  bigs: #[3; Big20]
}

type KItem is data = $KItem { a: U32, flag: Bool, c: F32 }
type KOut is data = $KOut { sum: U32, ok: Bool }
type KPrep is data = $KPrep { scale: U32, table: #[U32] }

func mk_big (v: U32): Big20 => return $Big20 {
  f0: v, f1: @u32.add v 1, f2: 2, f3: 3, f4: 4,
  f5: 5, f6: 6, f7: 7, f8: 8, f9: 9,
  f10: 10, f11: 11, f12: 12, f13: 13, f14: 14,
  f15: 15, f16: 16, f17: 17, f18: 18, f19: @u32.add v 19
}

func prep_k (w: #[U32]): KPrep => return $KPrep { scale: w[0], table: @storage.copy w }
func run_k (ctx: KPrep) -> (it: KItem): KOut =>
  let s = @u32.add (@u32.mul ctx.scale it.a) (@f32.to_u32 it.c)
  return $KOut { sum: s, ok: it.flag }

func run_var (n: U32): #[U32] => return @array.fill n 7

#kernel func double_fixed (x: U32): U32 => return @u32.mul x 2
#kernel const prepared_k: Kernel [#[U32], KItem, KOut] = { prepare: prep_k, run: run_k }
#kernel func var_k (n: U32): #[U32] => return run_var n

#entry func test_flat_roundtrip (seed: U32): #[U32] =>
  let r0: #[3; U32] = #[seed, @u32.add seed 1, @u32.add seed 2]
  let r1: #[3; U32] = #[10, 20, 30]
  let grid: #[2; #[3; U32]] = #[r0, r1]
  let bigs: #[3; Big20] = #[mk_big seed, mk_big (@u32.add seed 100), mk_big (@u32.add seed 200)]
  let p = $Packet {
    flag: true,
    grid: grid,
    bigs: bigs
  }
  let enc = flat.encode p
  // Verify decode returns $Some with fresh non-aliasing values (1 + 6 + 60 = 67 words!)
  let dec1: Maybe Packet = flat.decode enc
  let dec_sum = case dec1 of
    $Nothing => 0
    $Some q => @u32.add (@u32.add (if q.flag then 1 else 0) q.grid[1][2]) (@u32.add q.bigs[0].f19 q.bigs[2].f0)
  // Verify wrong length returns $Nothing
  let dec2: Maybe Packet = flat.decode #[1, 2, 3]
  let bad_len = case dec2 of
    $Nothing => 1
    $Some _ => 0
  // Verify non-canonical Bool (> 1) returns $Nothing in @flat.decode!
  // Field order of Packet (UTF-8 sorted!): bigs (60), flag (1 at index 60), grid (6)
  let bad_enc = @storage.copy enc
  bad_enc[60] := 2
  let dec3: Maybe Packet = flat.decode bad_enc
  let bad_bool = case dec3 of
    $Nothing => 1
    $Some _ => 0
  // Verify represented Kernel handle getters match blot:kernels!
  let kid = flat.kernel_id prepared_k
  let (bh_lo, bh_hi) = flat.kernel_binding_hash prepared_k
  let (ch_lo, ch_hi) = flat.kernel_ctx_hash prepared_k
  let (ih_lo, ih_hi) = flat.kernel_io_hash prepared_k
  return #[enc.length, dec_sum, bad_len, bad_bool, kid, bh_lo, bh_hi, ch_lo, ch_hi, ih_lo, ih_hi]
`,
    { stdRoot },
  );

  // Inspect custom sections!
  const mod = new WebAssembly.Module(bytes);
  const kSecs = WebAssembly.Module.customSections(mod, "blot:kernels");
  equal(kSecs.length, 1);
  const parsed = parseKernelsSection(new Uint8Array(kSecs[0]));
  equal(parsed.version, 1);
  equal(parsed.transportBudget, 2097152);
  equal(parsed.kernels.length, 3);
  equal(parsed.kernels[0].name, "double_fixed");
  equal(parsed.kernels[0].flags, 0);
  equal(parsed.kernels[1].name, "prepared_k");
  equal(parsed.kernels[1].flags, 1);
  equal(parsed.kernels[1].inSchema.stride, 3);
  assert.deepEqual(parsed.kernels[1].inSchema.wordTags, [1, 3, 2]); // a:U32, c:F32, flag:Bool (UTF-8 sorted!)
  equal(parsed.kernels[1].outSchema.stride, 2);
  assert.deepEqual(parsed.kernels[1].outSchema.wordTags, [2, 1]); // ok:Bool, sum:U32 (UTF-8 sorted!)
  equal(parsed.kernels[1].ctxExport, "blot:kernel_ctx:prepared_k");
  equal(parsed.kernels[1].clearExport, "blot:kernel_clear:prepared_k");
  equal(parsed.kernels[2].name, "var_k");
  equal(parsed.kernels[2].flags, 2);
  equal(parsed.kernels[2].outSchema.kind, 2); // VarU32
  equal(parsed.kernels[2].outSchema.wireTag, 5); // ArrayU32

  const guest = await instantiateGuest(bytes);
  try {
    // 1. FlatNumeric round-trip + Kernel handle hash verification against blot:kernels
    const fr = guest.call("test_flat_roundtrip", 5) as Uint32Array;
    equal(fr[0], 67); // 60 + 1 + 6
    equal(fr[1], 1 + 30 + 24 + 205); // 260
    equal(fr[2], 1); // bad length -> $Nothing
    equal(fr[3], 1); // bad bool -> $Nothing
    equal(fr[4], 1); // kernel_id(prepared_k) == 1
    equal(pairToU64(fr[5], fr[6]), parsed.kernels[1].bindingHash);
    equal(pairToU64(fr[7], fr[8]), parsed.kernels[1].ctxSchema!.schemaHash);
    equal(pairToU64(fr[9], fr[10]), parsed.kernels[1].ioSchemaHash);

    // 2. Stateless fixed kernel
    const dOut = guest.call("double_fixed", new Uint32Array([3, 10, 42])) as Uint32Array;
    assert.deepEqual(Array.from(dOut), [6, 20, 84]);

    // 3. Prepared kernel: count==0 BEFORE ctx MUST trap (§4.2.3)!
    assert.throws(() => guest.call("prepared_k", new Uint32Array([])));

    // Prepare context, run batch (with F32 3.0 bits = 0x40400000 and canonical Bool 1/0)
    guest.call("blot:kernel_ctx:prepared_k", new Uint32Array([10, 99]));
    const f3Bits = new Uint32Array(new Float32Array([3.0]).buffer)[0];
    const kOut = guest.call(
      "prepared_k",
      new Uint32Array([4, f3Bits, 1, 7, f3Bits, 0]),
    ) as Uint32Array;
    // Output fields sorted UTF-8: [ok, sum] -> [1, 43, 0, 73]
    assert.deepEqual(Array.from(kOut), [1, 43, 0, 73]);

    // Empty count==0 succeeds when prepared!
    const emptyOut = guest.call("prepared_k", new Uint32Array([])) as Uint32Array;
    equal(emptyOut.length, 0);

    // Non-canonical Bool word (2) traps in kernel wrapper!
    assert.throws(() => guest.call("prepared_k", new Uint32Array([4, f3Bits, 2])));

    // Clear context (idempotent!) then count==0 traps again!
    guest.call("blot:kernel_clear:prepared_k", null);
    guest.call("blot:kernel_clear:prepared_k", null);
    assert.throws(() => guest.call("prepared_k", new Uint32Array([])));

    // 4. Variable-output kernel: normal framed rows + [0xffffffff] non-trapping overflow sentinel!
    const vOk = guest.call("var_k", new Uint32Array([2, 0, 3])) as Uint32Array;
    assert.deepEqual(Array.from(vOk), [2, 7, 7, 0, 3, 7, 7, 7]);

    // Exceeds transport_budget (2 MiB -> max_out_words = 524287): pass [300000, 300000] -> non-trapping [0xffffffff] sentinel!
    // Check raw Wasm call since host/guest.ts reads header word as array length!
    const inst = new WebAssembly.Instance(mod);
    const exports = inst.exports as Record<string, unknown>;
    const mem = exports["blot:memory"] as WebAssembly.Memory;
    const alloc = exports["blot:allocate"] as (n: number) => number;
    const reset = exports["blot:reset"] as () => void;
    const runVar = exports["var_k"] as (ptr: number) => number;
    const finishInv = exports["blot:finish_invocation"] as () => void;
    reset();
    const inPtr = alloc(12); // 1 header + 2 items
    const view = new Uint32Array(mem.buffer, inPtr, 3);
    view[0] = 2;
    view[1] = 300000;
    view[2] = 300000;
    const outPtr = runVar(inPtr);
    const sentinel = new Uint32Array(mem.buffer, outPtr, 1)[0];
    equal(sentinel, 0xffffffff);
    finishInv();
  } finally {
    guest.dispose();
  }
});

// ============================================================================
// Retained-build LayoutReceipt oracle tests (§4.1 item 3):
// 1. Editing a kernel helper forces fresh emit updating blot:kernels impl_hash
//    and binding_hash + 7-word Kernel handle consts (matching fresh build!).
// 2. Editing an imported unit read ONLY by a #run inside a kernel invalidates
//    retained reuse (unconditional staged_dep_units collector!).
// 3. Editing an unrelated non-kernel function in a module WITH kernels still
//    safely replays/relocates!
// ============================================================================

Deno.test("Phase 3: LayoutReceipt retained-build soundness for kernel helper, kernel #run dep, and unrelated non-kernel edits", async () => {
  const dir = await Deno.makeTempDir({ prefix: "blot-phase3-receipt-" });
  const entry = `${dir}/main.blot`;
  const dep = `${dir}/dep.blot`;
  const compiler = await createZigProjectCompiler({
    executable: compilerExecutable,
    entry,
    prelude: preludePath,
    stdRoot,
  });
  try {
    const mkMain = (helperMult: number, nonKernelConst: number, useRun: boolean) => `
import * as flat from "std/flat"
import * as dep from "./dep"

func helper (x: U32): U32 => return @u32.mul x ${helperMult}
${useRun ? "func staged_factor (): U32 => return #run dep.factor" : "func staged_factor (): U32 => return 1"}

#kernel func work (x: U32): U32 => return @u32.add (helper x) (staged_factor ())

#entry func get_meta (_: Unit): #[U32] =>
  let (bh_lo, bh_hi) = flat.kernel_binding_hash work
  return #[${nonKernelConst}, bh_lo, bh_hi]
`;

    // Build 1: initial (no #run inside kernel)
    const b1 = await compiler.build({
      sources: {
        [entry]: mkMain(2, 10, false),
        [dep]: `const factor: U32 = 5\n`,
      },
    });
    assert(b1.success, JSON.stringify(b1));
    const k1 = parseKernelsSection(
      new Uint8Array(
        WebAssembly.Module.customSections(
          new WebAssembly.Module(b1.bytes),
          "blot:kernels",
        )[0],
      ),
    ).kernels[0];

    // Build 2: edit ONLY unrelated non-kernel constant (10 -> 11, same LEB width!) -> MUST relocate cleanly!
    const b2 = await compiler.build({
      sources: {
        [entry]: mkMain(2, 11, false),
        [dep]: `const factor: U32 = 5\n`,
      },
    });
    assert(b2.success, JSON.stringify(b2));
    assert(
      Number(b2.stats.relocatedOperands ?? -1) >= 1,
      `Expected unrelated non-kernel constant edit to relocate cleanly, got stats: ${JSON.stringify(b2.stats)}`,
    );
    const g2 = await instantiateGuest(b2.bytes);
    try {
      const m2 = g2.call("get_meta", null) as Uint32Array;
      equal(m2[0], 11);
      equal(pairToU64(m2[1], m2[2]), k1.bindingHash);
    } finally {
      g2.dispose();
    }

    // Build 3: edit kernel helper constant (2 -> 3) -> MUST invalidate retained reuse & update binding_hash!
    const b3 = await compiler.build({
      sources: {
        [entry]: mkMain(3, 11, false),
        [dep]: `const factor: U32 = 5\n`,
      },
    });
    assert(b3.success, JSON.stringify(b3));
    assert(
      Number(b3.stats.relocatedOperands ?? -1) < 0,
      `Kernel helper edit must bypass relocate, got stats: ${JSON.stringify(b3.stats)}`,
    );
    const k3 = parseKernelsSection(
      new Uint8Array(
        WebAssembly.Module.customSections(
          new WebAssembly.Module(b3.bytes),
          "blot:kernels",
        )[0],
      ),
    ).kernels[0];
    assert(k3.implHash !== k1.implHash, "impl_hash must change when kernel helper changes");
    assert(k3.bindingHash !== k1.bindingHash, "binding_hash must change when kernel helper changes");
    const g3 = await instantiateGuest(b3.bytes);
    try {
      const m3 = g3.call("get_meta", null) as Uint32Array;
      equal(pairToU64(m3[1], m3[2]), k3.bindingHash);
      const o3 = g3.call("work", new Uint32Array([4])) as Uint32Array;
      equal(o3[0], 13); // 4*3 + 1
    } finally {
      g3.dispose();
    }

    // Build 4: introduce #run reading dep.factor inside kernel -> fresh emit
    const b4 = await compiler.build({
      sources: {
        [entry]: mkMain(3, 11, true),
        [dep]: `const factor: U32 = 5\n`,
      },
    });
    assert(b4.success, JSON.stringify(b4));
    const g4 = await instantiateGuest(b4.bytes);
    try {
      const o4 = g4.call("work", new Uint32Array([4])) as Uint32Array;
      equal(o4[0], 17); // 4*3 + 5
    } finally {
      g4.dispose();
    }

    // Build 5: edit ONLY dep.blot (factor: 5 -> 9) read ONLY by #run inside kernel!
    // Unconditional staged_dep_units MUST force fresh emit so work(4) == 21!
    const b5 = await compiler.build({
      sources: {
        [entry]: mkMain(3, 11, true),
        [dep]: `const factor: U32 = 9\n`,
      },
    });
    assert(b5.success, JSON.stringify(b5));
    const g5 = await instantiateGuest(b5.bytes);
    try {
      const o5 = g5.call("work", new Uint32Array([4])) as Uint32Array;
      equal(o5[0], 21); // 4*3 + 9
    } finally {
      g5.dispose();
    }
  } finally {
    await compiler.dispose();
    await Deno.remove(dir, { recursive: true });
  }
});

// ============================================================================
// Stack exact-cap free-list monotonicity + offset 640 flag, deeply-immutable
// static_pool_flag pools in kernels/processes, blot:processes v1 section,
// process status=2 trap poisoning, and fork on persistent State + trap rewind.
// ============================================================================

Deno.test("Phase 3: exact-cap stack monotonicity, blot:processes v1, deeply-immutable static pools, status=2 poison, and persistent-state fork", async () => {
  // 1. Stack retained-chunk fragmentation sets offset 640 == 1, and reversed-order inner-rewind succeeds cleanly!
  const stackBytes = await compileToWasm(`
func scope_pair (n1: U32) -> (n2: U32): U32 =>
  let a = @array.fill n1 3
  let b = @array.fill n2 5
  return @u32.add a[@u32.sub n1 1] b[@u32.sub n2 1]

#entry func fill_60m (_: #[U32]): #[U32] =>
  let a = @array.fill 15000000 7
  return #[a[0], a[14999999]]

#entry func fill_80m (_: #[U32]): #[U32] =>
  let a = @array.fill 20000000 9
  return #[a[0], a[19999999]]

#entry func reversed_rewind (_: #[U32]): #[U32] =>
  // Warmup (32K, 10M, 80M) -> Scope 1 (80M, 10M) -> rewind -> Scope 2 (10M, 80M)
  let s1 = scope_pair 20000000 2500000
  let s2 = scope_pair 2500000 20000000
  return #[s1, s2]
`);
  {
    const mod = new WebAssembly.Module(stackBytes);
    const warm = new WebAssembly.Instance(mod);
    const exp = warm.exports as Record<string, unknown>;
    const mem = exp["blot:memory"] as WebAssembly.Memory;
    const reset = exp["blot:reset"] as () => void;
    const alloc = exp["blot:allocate"] as (n: number) => number;
    const finish = exp["blot:finish_invocation"] as () => void;

    // Fresh fill_80m succeeds
    {
      const fresh = new WebAssembly.Instance(mod);
      const fExp = fresh.exports as Record<string, unknown>;
      const fMem = fExp["blot:memory"] as WebAssembly.Memory;
      (fExp["blot:reset"] as () => void)();
      const fp = (fExp["blot:allocate"] as (n: number) => number)(4);
      new Uint32Array(fMem.buffer, fp, 1)[0] = 0;
      const fo = (fExp["fill_80m"] as (p: number) => number)(fp);
      equal(new Uint32Array(fMem.buffer, fo, 3)[1], 9);
      (fExp["blot:finish_invocation"] as () => void)();
    }

    // Warm: fill_60m then fill_80m -> logical stack_live_bytes (80M <= 128M) passes,
    // physical stack_total (60M + 80M = 140M > 128M) traps with offset 640 == 1!
    reset();
    const p1 = alloc(4);
    new Uint32Array(mem.buffer, p1, 1)[0] = 0;
    const o1 = (exp["fill_60m"] as (p: number) => number)(p1);
    equal(new Uint32Array(mem.buffer, o1, 3)[1], 7);
    finish();

    reset();
    const p2 = alloc(4);
    new Uint32Array(mem.buffer, p2, 1)[0] = 0;
    assert.throws(() => (exp["fill_80m"] as (p: number) => number)(p2));
    equal(new DataView(mem.buffer).getUint32(640, true), 1);
    finish();

    // Reversed-order inner-rewind succeeds repeatedly on same warm instance (reusing exact-cap stack_free_large)!
    const g = await instantiateGuest(stackBytes);
    try {
      for (let i = 0; i < 3; i++) {
        const res = g.call("reversed_rewind", new Uint32Array([])) as Uint32Array;
        assert.deepEqual(Array.from(res), [8, 8]);
      }
    } finally {
      g.dispose();
    }
  }

  // 2. Deeply-immutable static pool, blot:processes v1 binary section, status=2 trap poisoning,
  //    and fork rollback on persistent process State array!
  const procBytes = await compileToWasm(`
const STATIC_LUT: #[U32] = #[10, 20, 30, 40]

func fp_init (seed: U32): #[U32] =>
  let d: #[U32] = #[seed, @u32.add seed 1]
  return d

func fp_step (st: own #[U32]) -> (cmd: U32): (#[U32], #[U32]) =>
  if @u32.eq cmd 999:
    @panic "poison turn"
  // Speculatively mutate persistent State array inside fork and roll back!
  let spec = fork st:
    st[0] := 777
    @storage.push st 888
    return @u32.add st[0] st.length
  // Persistent st must be untouched after fork rollback, and STATIC_LUT must stay intact!
  @storage.push st cmd
  let s0 = st[0]
  let slen = st.length
  return (st, #[spec, s0, slen, STATIC_LUT[2]])

#process const fork_proc: Process [U32, U32, #[U32]] = { init: fp_init, step: fp_step }
`);
  const pMod = new WebAssembly.Module(procBytes);
  const pSecs = WebAssembly.Module.customSections(pMod, "blot:processes");
  equal(pSecs.length, 1);
  const parsedP = parseProcessesSection(new Uint8Array(pSecs[0]));
  equal(parsedP.version, 1);
  equal(parsedP.transportBudget, 2097152);
  equal(parsedP.processes.length, 1);
  equal(parsedP.processes[0].name, "fork_proc");
  equal(parsedP.processes[0].initExport, "blot:proc_init:fork_proc");
  equal(parsedP.processes[0].stepExport, "blot:proc_step:fork_proc");
  equal(parsedP.processes[0].configSchema.wireTag, 1); // U32
  equal(parsedP.processes[0].cmdSchema.wireTag, 1); // U32
  equal(parsedP.processes[0].replySchema.kind, 2); // VarU32
  equal(parsedP.processes[0].replySchema.wireTag, 5); // ArrayU32

  const pg = await instantiateGuest(procBytes);
  try {
    // Calling step before init MUST trap (status == 0 != 1)!
    assert.throws(() => pg.call("blot:proc_step:fork_proc", 1));
    pg.call("blot:proc_init:fork_proc", 5);
    // Double init MUST trap (status == 1 != 0)!
    assert.throws(() => pg.call("blot:proc_init:fork_proc", 5));

    // Turn 1: fork saw data[0]=777, len=3 -> 780; after rollback data[0]=5, pushed 11 -> len=3, lut[2]=30
    const s1 = pg.call("blot:proc_step:fork_proc", 11) as Uint32Array;
    assert.deepEqual(Array.from(s1), [780, 5, 3, 30]);
    // Turn 2: fork saw data[0]=777, len=4 -> 781; after rollback data[0]=5, pushed 12 -> len=4, lut[2]=30
    const s2 = pg.call("blot:proc_step:fork_proc", 12) as Uint32Array;
    assert.deepEqual(Array.from(s2), [781, 5, 4, 30]);

    // Turn 3 traps inside step -> status stays 2 (poisoned!), so Turn 4 MUST trap too!
    assert.throws(() => pg.call("blot:proc_step:fork_proc", 999));
    assert.throws(() => pg.call("blot:proc_step:fork_proc", 13));
  } finally {
    pg.dispose();
  }
});

