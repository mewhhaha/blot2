// Comprehensive Phase 4 Deno & Browser Qualification Suite (Laws #4 and #5).
// Covers `host/guest.ts`, `host/kernels.ts`, `host/kernel_worker.ts`,
// `host/processes.ts`, `host/process_subprocess.ts`, AND `../pen/crates/pen-web/kernels.js`.
import { rejects } from "node:assert/strict";
import {
  compileKernelModule,
  copyPrivateBytes,
  readMemoryShape,
} from "../../host/guest.ts";
import { KernelError, KernelPool } from "../../host/kernels.ts";
import {
  ProcessError,
  Processes,
  type ProcessHandle,
  ProcessOverrunError,
} from "../../host/processes.ts";
import {
  BrowserKernelError,
  BrowserKernelPool,
  compileKernelModule as compileBrowserKernelModule,
} from "../../../pen/crates/pen-web/kernels.js";
import { compileAndRun, equal } from "../guest/compile_helpers.ts";

async function compileBlot(source: string): Promise<Uint8Array<ArrayBuffer>> {
  let compiled: Uint8Array<ArrayBuffer> | undefined;
  await compileAndRun(source, (_guest, bytes) => {
    compiled = copyPrivateBytes(bytes);
  });
  return compiled!;
}

// ---------------------------------------------------------------------------
// Test-only Wasm Section ID 5 (`MemorySection`) rewriter for Law #4(a)(4)
// and unbounded/bounded memory admission tests.
// ---------------------------------------------------------------------------
function encodeUleb(value: number): number[] {
  const out: number[] = [];
  let v = value >>> 0;
  do {
    let b = v & 0x7f;
    v >>>= 7;
    if (v !== 0) b |= 0x80;
    out.push(b);
  } while (v !== 0);
  return out;
}

function readUlebAt(bytes: Uint8Array, state: { at: number }): number {
  let result = 0;
  let shift = 0;
  for (;;) {
    const b = bytes[state.at++];
    result += (b & 0x7f) * 2 ** shift;
    if ((b & 0x80) === 0) return result;
    shift += 7;
  }
}

/**
 * Rewrite Wasm Section ID 5 (`MemorySection`) on compiled bytes to set an
 * exact `maximumPages` (or `undefined` for an unbounded linear memory).
 */
function rewriteMemorySectionMax(
  wasm: Uint8Array,
  maximumPages: number | undefined,
): Uint8Array<ArrayBuffer> {
  const parts: Uint8Array[] = [wasm.subarray(0, 8)];
  const st = { at: 8 };
  while (st.at < wasm.length) {
    const id = wasm[st.at++];
    const size = readUlebAt(wasm, st);
    const body = wasm.subarray(st.at, st.at + size);
    st.at += size;
    if (id === 5) {
      const ms = { at: 0 };
      const count = readUlebAt(body, ms);
      if (count !== 1) throw new Error(`Expected 1 memory, got ${count}`);
      const oldFlags = body[ms.at++];
      const initial = readUlebAt(body, ms);
      if ((oldFlags & 1) !== 0) readUlebAt(body, ms);
      const newFlags = maximumPages !== undefined
        ? (oldFlags | 1)
        : (oldFlags & ~1);
      const newBody = new Uint8Array([
        1,
        newFlags,
        ...encodeUleb(initial),
        ...(maximumPages !== undefined ? encodeUleb(maximumPages) : []),
      ]);
      parts.push(new Uint8Array([5, ...encodeUleb(newBody.length)]), newBody);
    } else {
      parts.push(new Uint8Array([id, ...encodeUleb(body.length)]), body);
    }
  }
  const total = parts.reduce((acc, p) => acc + p.byteLength, 0);
  const out = new Uint8Array(new ArrayBuffer(total));
  let offset = 0;
  for (const p of parts) {
    out.set(p, offset);
    offset += p.byteLength;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Law #4 — KernelPool (Deno + Browser pen-web/kernels.js)
// ---------------------------------------------------------------------------

const kernelSuiteSource = `
func prep_ctx (seed: U32): U32 => return seed
func run_ctx (seed: U32) -> (x: U32): U32 => return @u32.add seed x
#kernel const with_ctx: Kernel [U32, U32, U32] = { prepare: prep_ctx, run: run_ctx }

func prep_array_ctx (xs: #[U32]): U32 => return if xs.length > 0 then xs[0] else 0
func run_array_ctx (base: U32) -> (x: U32): U32 => return @u32.add base x
#kernel const array_ctx_k: Kernel [#[U32], U32, U32] = { prepare: prep_array_ctx, run: run_array_ctx }

func prep_spin (x: U32): U32 => return do:
  if x == 1:
    for ever:
      continue
  return x
func run_spin_ctx (s: U32) -> (x: U32): U32 => return @u32.add s x
#kernel const spin_ctx: Kernel [U32, U32, U32] = { prepare: prep_spin, run: run_spin_ctx }

#kernel func add_one (x: U32): U32 => return @u32.add x 1

#kernel func spin_on_one (x: U32): U32 => return do:
  if x == 1:
    for ever:
      continue
  return @u32.add x 10

#kernel func var_emit (n: U32): #[U32] =>
  return @array.generate n (func i => @u32.add i 1)

#kernel func var_overflow (n: U32): #[U32] =>
  return @array.generate n (func i => i)

type W8 = #[8; U32]
type W64 = #[8; W8]
type W512 = #[8; W64]
type W4K = #[8; W512]
type W32K = #[8; W4K]
type W256K = #[8; W32K]

func mk_z8 (): W8 => return #[0, 0, 0, 0, 0, 0, 0, 0]
func mk_z64 (): W64 => return #[mk_z8 (), mk_z8 (), mk_z8 (), mk_z8 (), mk_z8 (), mk_z8 (), mk_z8 (), mk_z8 ()]
func mk_z512 (): W512 => return #[mk_z64 (), mk_z64 (), mk_z64 (), mk_z64 (), mk_z64 (), mk_z64 (), mk_z64 (), mk_z64 ()]
func mk_z4k (): W4K => return #[mk_z512 (), mk_z512 (), mk_z512 (), mk_z512 (), mk_z512 (), mk_z512 (), mk_z512 (), mk_z512 ()]
func mk_z32k (): W32K => return #[mk_z4k (), mk_z4k (), mk_z4k (), mk_z4k (), mk_z4k (), mk_z4k (), mk_z4k (), mk_z4k ()]

#kernel func big_row_1mib (x: U32): W256K =>
  let f8: W8 = #[x, 0, 0, 0, 0, 0, 0, 0]
  let f64: W64 = #[f8, mk_z8 (), mk_z8 (), mk_z8 (), mk_z8 (), mk_z8 (), mk_z8 (), mk_z8 ()]
  let f512: W512 = #[f64, mk_z64 (), mk_z64 (), mk_z64 (), mk_z64 (), mk_z64 (), mk_z64 (), mk_z64 ()]
  let f4k: W4K = #[f512, mk_z512 (), mk_z512 (), mk_z512 (), mk_z512 (), mk_z512 (), mk_z512 (), mk_z512 ()]
  let f32k: W32K = #[f4k, mk_z4k (), mk_z4k (), mk_z4k (), mk_z4k (), mk_z4k (), mk_z4k (), mk_z4k ()]
  return #[f32k, mk_z32k (), mk_z32k (), mk_z32k (), mk_z32k (), mk_z32k (), mk_z32k (), mk_z32k ()]
`;

Deno.test("Law #4: unforgeable CompiledModuleReceipt, primordial copyPrivateBytes, MemoryShape & deadline admission", async () => {
  const bytes = await compileBlot(kernelSuiteSource);

  // 1. Opaque WebAssembly.Module MUST be rejected!
  const opaqueModule = new WebAssembly.Module(bytes);
  await rejects(
    () => KernelPool.open(opaqueModule as unknown as Uint8Array, "add_one"),
    TypeError,
  );
  await rejects(
    () =>
      BrowserKernelPool.open(opaqueModule as unknown as Uint8Array, "add_one"),
    TypeError,
  );

  // 2. Primordial copyPrivateBytes rejects SharedArrayBuffer AND shrunk OOB Resizable ArrayBuffer!
  if (typeof SharedArrayBuffer === "function") {
    const sab = new SharedArrayBuffer(16);
    const sabView = new Uint32Array(sab);
    let threw = false;
    try {
      copyPrivateBytes(sabView);
    } catch (e) {
      threw = e instanceof TypeError;
    }
    equal(threw, true);
  }
  const rab = new ArrayBuffer(16, { maxByteLength: 32 });
  const oobView = new Uint8Array(rab, 0, 12);
  rab.resize(4); // oobView is now shrunk out-of-bounds!
  let threwRab = false;
  try {
    copyPrivateBytes(oobView);
  } catch (e) {
    threwRab = e instanceof TypeError;
  }
  equal(threwRab, true);

  // 3. Mutating raw bytes with overridden .slice() right after compileKernelModule must not corrupt snapshot.
  const mutableWasm = new Uint8Array(bytes);
  Object.defineProperty(mutableWasm, "slice", {
    value: function () {
      return this;
    },
  });
  const receipt = compileKernelModule(mutableWasm);
  mutableWasm.fill(0);
  const p = await KernelPool.open(receipt, "add_one", { workers: 0 });
  try {
    equal(String(await p.runFixed(Uint32Array.of(5, 9))), "6,10");
  } finally {
    await p.close();
  }

  // 4. Unbounded memory & memory < declared max rejected at admission (Deno + Browser).
  const unboundedWasm = rewriteMemorySectionMax(bytes, undefined);
  const shapeUnbounded = readMemoryShape(unboundedWasm);
  equal(shapeUnbounded.maximumPages, undefined);
  await rejects(
    () =>
      KernelPool.open(unboundedWasm, "add_one", { memory: 64 * 1024 * 1024 }),
    (e: unknown) =>
      e instanceof KernelError && e.code === "memory_limit_unbounded",
  );
  await rejects(
    () =>
      BrowserKernelPool.open(unboundedWasm, "add_one", {
        memory: 64 * 1024 * 1024,
      }),
    (e: unknown) =>
      e instanceof BrowserKernelError && e.code === "memory_limit_unbounded",
  );

  const bounded100 = rewriteMemorySectionMax(bytes, 100);
  await rejects(
    () => KernelPool.open(bounded100, "add_one", { memory: 99 * 65536 }),
    (e: unknown) =>
      e instanceof KernelError && e.code === "memory_limit_exceeded",
  );
  await rejects(
    () => BrowserKernelPool.open(bounded100, "add_one", { memory: 99 * 65536 }),
    (e: unknown) =>
      e instanceof BrowserKernelError && e.code === "memory_limit_exceeded",
  );

  // 5. Invalid deadlineMs ranges rejected on BOTH Deno and Browser!
  const browserReceiptDl = compileBrowserKernelModule(bytes);
  for (
    const bad of [0, -1, Number.NaN, Number.POSITIVE_INFINITY, 2_147_483_648]
  ) {
    await rejects(
      () => KernelPool.open(receipt, "add_one", { deadlineMs: bad }),
      (e: unknown) => e instanceof KernelError && e.code === "invalid_config",
    );
    await rejects(
      () =>
        BrowserKernelPool.open(browserReceiptDl, "add_one", {
          deadlineMs: bad,
        }),
      (e: unknown) =>
        e instanceof BrowserKernelError && e.code === "invalid_config",
    );
  }

  // 6. Premature timer callback re-arms instead of timing out!
  let capturedFire: (() => void) | null = null;
  const pTimer = await KernelPool.open(receipt, "add_one", {
    workers: 1,
    deadlineMs: 2000,
    _testHooks: {
      onTimerArmed: ({ fire }) => {
        capturedFire = fire;
      },
      onAfterReady: () => {
        // Fire the timer callback prematurely while performance.now() < deadlineMs!
        capturedFire?.();
      },
    },
  });
  try {
    equal(String(await pTimer.runFixed(Uint32Array.of(41))), "42");
  } finally {
    await pTimer.close();
  }

  // 7. Transport-budget checked integer floor division: two 1 MiB rows under 2 MiB budget -> maxChunkItems === 1!
  const bigPool = await KernelPool.open(receipt, "big_row_1mib", {
    workers: 2,
    defaultChunkItems: 8,
    maxTotalOutputBytes: 4 * 1024 * 1024,
    maxPhysicalOutputBytes: 4 * 1024 * 1024,
    deadlineMs: 5000,
  });
  try {
    equal(bigPool.maxChunkItems, 1);
    const out = await bigPool.runFixed(Uint32Array.of(77, 88));
    equal(out.length, 524_288);
    equal(out[0], 77);
    equal(out[262_144], 88);
  } finally {
    await bigPool.close();
  }
});

Deno.test("Law #4(a)(4): bounded policy.memory warm-vs-fresh transport symmetry via MemorySection rewriter", async () => {
  const bytes = await compileBlot(`
#kernel func var_mem (n: U32): #[U32] =>
  return @array.generate n (func i => i)
`);
  // Chunk 1 emits 128 KiB (32768 words), Chunk 2 has 64 KiB input (16384 items) or emits 128 KiB output.
  // Measure exact freshRequiredPages via binary search with the test-only Section ID 5 rewriter.
  const testRun = async (
    pages: number,
    warmupFirst: boolean,
  ): Promise<boolean> => {
    const rewritten = rewriteMemorySectionMax(bytes, pages);
    const pool = await KernelPool.open(rewritten, "var_mem", {
      workers: 1,
      defaultChunkItems: 64,
      memory: pages * 65_536,
      maxTotalOutputBytes: 4 * 1024 * 1024,
      maxPhysicalOutputBytes: 8 * 1024 * 1024,
      deadlineMs: 3000,
    });
    try {
      if (warmupFirst) {
        await pool.runVariable(Uint32Array.of(32_768));
      }
      // 16384 items (64 KiB input) with first item emitting 128 KiB output!
      const chunk2 = new Uint32Array(16_384);
      chunk2[0] = 32_768;
      await pool.runVariable(chunk2);
      return true;
    } catch (e) {
      if (e instanceof KernelError && e.code === "out_of_memory") return false;
      throw e;
    } finally {
      await pool.close();
    }
  };

  // Find exact freshRequiredPages between 4 and 40 pages.
  let lo = 4;
  let hi = 40;
  while (lo < hi) {
    const mid = (lo + hi) >> 1;
    if (await testRun(mid, false)) hi = mid;
    else lo = mid + 1;
  }
  const freshRequiredPages = lo;
  equal(freshRequiredPages > 4 && freshRequiredPages < 40, true);
  // At freshRequiredPages - 1, BOTH fresh AND warm-after-blot:reset MUST fail with OOM!
  equal(await testRun(freshRequiredPages - 1, false), false);
  equal(await testRun(freshRequiredPages - 1, true), false);
  // At freshRequiredPages, BOTH fresh AND warm-after-blot:reset MUST succeed identically!
  equal(await testRun(freshRequiredPages, false), true);
  equal(await testRun(freshRequiredPages, true), true);
});

Deno.test("Law #4(b)-(f): queued-ready CLEANUP_FAIL->discard, BYOB fault, PendingFrontierGrant 12B race, precedence, [0xffffffff], & post-concat timeout", async () => {
  const bytes = await compileBlot(kernelSuiteSource);
  const receipt = compileKernelModule(bytes);

  // 1. runFixed 1x single-buffer peak (12 B), out-of-order completion, and queued-ready CLEANUP_FAIL -> discard!
  let releaseReady0!: () => void;
  const ready0Gate = new Promise<void>((r) => {
    releaseReady0 = r;
  });
  let sawReady0 = false;
  let sawReady1 = false;
  const fixedFail1 = await KernelPool.open(receipt, "add_one", {
    workers: 2,
    defaultChunkItems: 1,
    maxTotalOutputBytes: 12,
    maxPhysicalOutputBytes: 12,
    deadlineMs: 3000,
    _testHooks: {
      forceCleanupFailAtStart: new Set([1]),
      onAfterReady: async ({ start }) => {
        if (start === 0) {
          sawReady0 = true;
          await ready0Gate; // Hold chunk 0 so chunk 1 grabs outputBuf first and fails cleanup!
        } else if (start === 1) {
          sawReady1 = true;
        }
      },
      onAfterFixedGrantIssued: ({ start }) => {
        if (start === 1) releaseReady0();
      },
    },
  });
  try {
    await rejects(
      () => fixedFail1.runFixed(Uint32Array.of(10, 20)),
      (e: unknown) =>
        e instanceof KernelError && e.code === "cleanup_trap" &&
        e.startItem === 1,
    );
    equal(sawReady0 && sawReady1, true);
    equal(fixedFail1.stats.fixedOutputBytes, 0);
    equal(fixedFail1.stats.currentChargedBytes, 0);
  } finally {
    await fixedFail1.close();
  }

  // Second case: BOTH chunk 0 (queued -> discard) AND chunk 1 fail cleanup -> chunk 0 MUST win (prefix order)!
  let release0Both!: () => void;
  const gate0Both = new Promise<void>((r) => {
    release0Both = r;
  });
  const fixedFailBoth = await KernelPool.open(receipt, "add_one", {
    workers: 2,
    defaultChunkItems: 1,
    maxTotalOutputBytes: 12,
    maxPhysicalOutputBytes: 12,
    deadlineMs: 3000,
    _testHooks: {
      forceCleanupFailAtStart: new Set([0, 1]),
      onAfterReady: async ({ start }) => {
        if (start === 0) await gate0Both;
      },
      onAfterFixedGrantIssued: ({ start }) => {
        if (start === 1) release0Both();
      },
    },
  });
  try {
    await rejects(
      () => fixedFailBoth.runFixed(Uint32Array.of(10, 20)),
      (e: unknown) =>
        e instanceof KernelError && e.code === "cleanup_trap" &&
        e.startItem === 0,
    );
    equal(fixedFailBoth.stats.fixedOutputBytes, 0);
  } finally {
    await fixedFailBoth.close();
  }

  // 2. Backing-store-losing BYOB read error -> immediate transport_fault + full charge release!
  const byobFaultPool = await KernelPool.open(receipt, "add_one", {
    workers: 2,
    defaultChunkItems: 1,
    maxTotalOutputBytes: 16,
    maxPhysicalOutputBytes: 16,
    deadlineMs: 3000,
    _testHooks: { injectByobReadError: true },
  });
  try {
    await rejects(
      () => byobFaultPool.runFixed(Uint32Array.of(1, 2)),
      (e: unknown) => e instanceof KernelError && e.code === "transport_fault",
    );
    equal(byobFaultPool.stats.fixedOutputBytes, 0);
    equal(byobFaultPool.stats.activeSubprocesses, 0);
    equal(byobFaultPool.stats.workerMemoryBytes, 0);
  } finally {
    await byobFaultPool.close();
  }

  // 3. Exact 12 B PendingFrontierGrant race (chunk 1 grabs 8 B copy_grant BEFORE chunk 0 reports 8 B READY)!
  let releaseChunk0Ready!: () => void;
  const chunk0ReadyGate = new Promise<void>((r) => {
    releaseChunk0Ready = r;
  });
  let releaseChunk1Grant!: () => void;
  const chunk1GrantGate = new Promise<void>((r) => {
    releaseChunk1Grant = r;
  });
  const pendingFrontierPool = await KernelPool.open(receipt, "var_emit", {
    workers: 2,
    defaultChunkItems: 1,
    maxTotalOutputBytes: 12, // chunk 0 = [1, 1] (8 B), chunk 1 = [1, 1] (8 B); 8+8 > 12!
    maxPhysicalOutputBytes: 24,
    deadlineMs: 3000,
    _testHooks: {
      onAfterReady: async ({ start }) => {
        if (start === 0) await chunk0ReadyGate;
      },
      onAfterVariableGrantIssued: async ({ start }) => {
        if (start === 1) {
          releaseChunk0Ready();
          await new Promise((r) => setTimeout(r, 15));
          releaseChunk1Grant();
          await chunk1GrantGate;
        }
      },
    },
  });
  try {
    await rejects(
      () => pendingFrontierPool.runVariableChunks(Uint32Array.of(1, 1)),
      (e: unknown) =>
        e instanceof KernelError && e.code === "output_budget_exceeded" &&
        e.startItem === 1,
    );
    equal(pendingFrontierPool.stats.peakChargedBytes <= 12, true);
    equal(pendingFrontierPool.stats.inFlightGrantBytes, 0);
    // Subsequent batch immediately reuses the full 12 B budget!
    const ok = await pendingFrontierPool.runVariableChunks(Uint32Array.of(2));
    equal(String(ok[0]), "2,1,2");
  } finally {
    await pendingFrontierPool.close();
  }

  // 4. Worker-count-invariant same-start_item precedence across workers = 0, 1, 2!
  for (const workers of [0, 1, 2]) {
    // 8 + 8 > 12 with chunk 1 cleanup fail -> output_budget_exceeded MUST win!
    const pBudgetWins = await KernelPool.open(receipt, "var_emit", {
      workers,
      defaultChunkItems: 1,
      maxTotalOutputBytes: 12,
      maxPhysicalOutputBytes: 24,
      _testHooks: { forceCleanupFailAtStart: new Set([1]) },
    });
    try {
      await rejects(
        () => pBudgetWins.runVariableChunks(Uint32Array.of(1, 1)),
        (e: unknown) =>
          e instanceof KernelError && e.code === "output_budget_exceeded" &&
          e.startItem === 1,
      );
    } finally {
      await pBudgetWins.close();
    }

    // 4 + 8 <= 12 with chunk 1 cleanup fail -> cleanup_trap MUST win!
    const pCleanupWins = await KernelPool.open(receipt, "var_emit", {
      workers,
      defaultChunkItems: 1,
      maxTotalOutputBytes: 12,
      maxPhysicalOutputBytes: 24,
      _testHooks: { forceCleanupFailAtStart: new Set([1]) },
    });
    try {
      await rejects(
        () => pCleanupWins.runVariableChunks(Uint32Array.of(0, 1)),
        (e: unknown) =>
          e instanceof KernelError && e.code === "cleanup_trap" &&
          e.startItem === 1,
      );
    } finally {
      await pCleanupWins.close();
    }
  }

  // 5. Unified [0xffffffff] overflow-sentinel transition across workers = 0, 1, 2!
  // transport_budget = 2_097_152 B -> max_out_words = 524_287 -> 2 items of 300_000 words overflow 2-item chunk,
  // bisecting to 2 single-item chunks of 300_000 words each!
  for (const workers of [0, 1, 2]) {
    const pBisect = await KernelPool.open(receipt, "var_overflow", {
      workers,
      defaultChunkItems: 2,
      maxTotalOutputBytes: 4 * 1024 * 1024,
      maxPhysicalOutputBytes: 8 * 1024 * 1024,
    });
    try {
      const chunks = await pBisect.runVariableChunks(
        Uint32Array.of(300_000, 300_000),
      );
      equal(chunks.length, 2);
      equal(chunks[0][0], 300_000);
      equal(chunks[1][0], 300_000);
    } finally {
      await pBisect.close();
    }

    // Multi-item [0xffffffff] + OVERFLOW_CLEANUP_FAIL -> cleanup_trap without bisecting!
    const pMultiClean = await KernelPool.open(receipt, "var_overflow", {
      workers,
      defaultChunkItems: 2,
      maxTotalOutputBytes: 4 * 1024 * 1024,
      maxPhysicalOutputBytes: 8 * 1024 * 1024,
      _testHooks: { forceCleanupFailAtStart: new Set([0]) },
    });
    try {
      await rejects(
        () => pMultiClean.runVariableChunks(Uint32Array.of(300_000, 300_000)),
        (e: unknown) =>
          e instanceof KernelError && e.code === "cleanup_trap" &&
          e.startItem === 0,
      );
    } finally {
      await pMultiClean.close();
    }

    // Single-item [0xffffffff] + OVERFLOW_CLEANUP_FAIL -> single_item_output_overflow ALWAYS wins!
    const pSingleClean = await KernelPool.open(receipt, "var_overflow", {
      workers,
      defaultChunkItems: 1,
      maxTotalOutputBytes: 4 * 1024 * 1024,
      maxPhysicalOutputBytes: 8 * 1024 * 1024,
      _testHooks: { forceCleanupFailAtStart: new Set([0]) },
    });
    try {
      await rejects(
        () => pSingleClean.runVariableChunks(Uint32Array.of(600_000)),
        (e: unknown) =>
          e instanceof KernelError &&
          e.code === "single_item_output_overflow" &&
          e.startItem === 0,
      );
    } finally {
      await pSingleClean.close();
    }
  }

  // 6. Post-concatenation monotonic deadline check rejects late publish with Timeout!
  const pConcatTimeout = await KernelPool.open(receipt, "var_emit", {
    workers: 2,
    defaultChunkItems: 1,
    deadlineMs: 60,
    _testHooks: {
      onBeforeConcatPublish: async () => {
        await new Promise((r) => setTimeout(r, 80));
      },
    },
  });
  try {
    await rejects(
      () => pConcatTimeout.runVariable(Uint32Array.of(1, 2)),
      (e: unknown) => e instanceof KernelError && e.code === "timeout",
    );
    equal(pConcatTimeout.stats.currentChargedBytes, 0);
  } finally {
    await pConcatTimeout.close();
  }
});

Deno.test("Law #4(e): off-thread direct/fallback/context deadlines, pool exclusivity, private input mutation & platform-honest Browser close()", async () => {
  const bytes = await compileBlot(kernelSuiteSource);
  const receipt = compileKernelModule(bytes);

  // 1. workers == 0 direct spinning guest under deadlineMs runs off-thread and preempts cleanly!
  const directSpin = await KernelPool.open(receipt, "spin_on_one", {
    workers: 0,
    deadlineMs: 80,
  });
  try {
    await rejects(
      () => directSpin.runFixed(Uint32Array.of(1)),
      (e: unknown) => e instanceof KernelError && e.code === "timeout",
    );
    equal(directSpin.stats.activeSubprocesses, 0);
    // Subsequent healthy run works cleanly!
    equal(String(await directSpin.runFixed(Uint32Array.of(5))), "15");
  } finally {
    await directSpin.close();
  }

  // 2. Real fallback from configured workers >= 2 pool under deadlineMs runs off-thread and preempts cleanly!
  const fallbackSpin = await KernelPool.open(receipt, "spin_on_one", {
    workers: 2,
    deadlineMs: 80,
    _testHooks: { forceFallback: true },
  });
  try {
    await rejects(
      () => fallbackSpin.runFixed(Uint32Array.of(1)),
      (e: unknown) => e instanceof KernelError && e.code === "timeout",
    );
    equal(fallbackSpin.stats.fallbacks, 1);
    equal(fallbackSpin.stats.activeSubprocesses, 0);
  } finally {
    await fallbackSpin.close();
  }

  // 3. Standalone setContext spinning prepare timeout & late CTX_OK timeout preserve prior snapshot!
  const ctxPool = await KernelPool.open(receipt, "spin_ctx", {
    workers: 1,
    deadlineMs: 80,
  });
  try {
    await ctxPool.setContext(1, Uint32Array.of(100));
    equal(String(await ctxPool.runFixed(Uint32Array.of(5))), "105");
    // Spinning prepare (input 1) times out and preserves revision 1 (100)!
    await rejects(
      () => ctxPool.setContext(2, Uint32Array.of(1)),
      (e: unknown) => e instanceof KernelError && e.code === "timeout",
    );
    equal(String(await ctxPool.runFixed(Uint32Array.of(5))), "105");
  } finally {
    await ctxPool.close();
  }

  // Late CTX_OK / clearContext arriving AFTER ctxDeadlineMs -> Timeout preserving prior ctx!
  let delayPublish = false;
  const lateCtxPool = await KernelPool.open(receipt, "with_ctx", {
    workers: 1,
    deadlineMs: 60,
    _testHooks: {
      onBeforeContextPublish: async () => {
        if (delayPublish) await new Promise((r) => setTimeout(r, 80));
      },
    },
  });
  try {
    await lateCtxPool.setContext(1, Uint32Array.of(40));
    delayPublish = true;
    await rejects(
      () => lateCtxPool.setContext(2, Uint32Array.of(99)),
      (e: unknown) => e instanceof KernelError && e.code === "timeout",
    );
    await rejects(
      () => lateCtxPool.clearContext(),
      (e: unknown) => e instanceof KernelError && e.code === "timeout",
    );
    delayPublish = false;
    // Revision 1 (40) is STILL intact and usable!
    equal(String(await lateCtxPool.runFixed(Uint32Array.of(2))), "42");
  } finally {
    await lateCtxPool.close();
  }

  // 4. Private copyPrivateBytes ignores overridden .slice() on BOTH setContext AND runFixed!
  const arrPool = await KernelPool.open(receipt, "array_ctx_k", {
    workers: 2,
    defaultChunkItems: 1,
    deadlineMs: 2000,
  });
  try {
    const ctxArr = Uint32Array.of(500, 1, 2);
    Object.defineProperty(ctxArr, "slice", {
      value: function () {
        return this;
      },
    });
    const setP = arrPool.setContext(1, ctxArr);
    ctxArr.fill(0); // Mutate immediately after call!
    await setP;

    const items = Uint32Array.of(7, 8, 9);
    Object.defineProperty(items, "slice", {
      value: function () {
        return this;
      },
    });
    const runP = arrPool.runFixed(items);
    items.fill(999);
    equal(String(await runP), "507,508,509");
  } finally {
    await arrPool.close();
  }

  // 5. Pool exclusivity: racing setContext/clearContext during paused READY batch -> BatchInProgress!
  let releaseReady!: () => void;
  const readyGate = new Promise<void>((r) => {
    releaseReady = r;
  });
  let atReadyResolve!: () => void;
  const atReady = new Promise<void>((r) => {
    atReadyResolve = r;
  });
  const exclPool = await KernelPool.open(receipt, "with_ctx", {
    workers: 1,
    deadlineMs: 2000,
    _testHooks: {
      onAfterReady: async () => {
        atReadyResolve();
        await readyGate;
      },
    },
  });
  try {
    await exclPool.setContext(1, Uint32Array.of(10));
    const batchP = exclPool.runFixed(Uint32Array.of(1, 2));
    await atReady;
    await rejects(
      () => exclPool.setContext(2, Uint32Array.of(20)),
      (e: unknown) =>
        e instanceof KernelError && e.code === "batch_in_progress",
    );
    await rejects(
      () => exclPool.clearContext(),
      (e: unknown) =>
        e instanceof KernelError && e.code === "batch_in_progress",
    );
    releaseReady();
    equal(String(await batchP), "11,12");
  } finally {
    await exclPool.close();
  }

  // 6. Deno close() racing mid-fixed-grant -> batch rejects ONCE with PoolClosed & ALL charges release to 0!
  let atFixedGrantResolve!: () => void;
  const atFixedGrant = new Promise<void>((r) => {
    atFixedGrantResolve = r;
  });
  let releaseFixedGrant!: () => void;
  const fixedGrantGate = new Promise<void>((r) => {
    releaseFixedGrant = r;
  });
  const closeDenoPool = await KernelPool.open(receipt, "add_one", {
    workers: 1,
    deadlineMs: 2000,
    _testHooks: {
      onAfterFixedGrantIssued: async () => {
        atFixedGrantResolve();
        await fixedGrantGate;
      },
    },
  });
  const runCloseP = closeDenoPool.runFixed(Uint32Array.of(1, 2, 3));
  await atFixedGrant;
  const closeP = closeDenoPool.close();
  releaseFixedGrant();
  await rejects(
    () => runCloseP,
    (e: unknown) => e instanceof KernelError && e.code === "pool_closed",
  );
  await closeP;
  equal(closeDenoPool.stats.activeSubprocesses, 0);
  equal(closeDenoPool.stats.workerMemoryBytes, 0);
  equal(closeDenoPool.stats.fixedOutputBytes, 0);

  // 7. Browser pen-web/kernels.js platform-honest close() accounting:
  //    (a) close() right after READY (before [outputBuf] transfer) -> releases coordinator-owned outputBuf cleanly (0 permanently retired transfer!)
  //    (b) close() AFTER [outputBuf] transfer (while worker owns outputBuf) -> permanently retires unacknowledged outputBuf + slot charge!
  const makeMockWorkerFactory = (holdGrantReply: boolean) => () => {
    const inst = new WebAssembly.Instance(receipt.module, {});
    const exp = inst.exports as Record<string, unknown>;
    const mem = exp["blot:memory"] as WebAssembly.Memory;
    const alloc = exp["blot:allocate"] as (n: number) => number;
    const reset = exp["blot:reset"] as (n: number) => void;
    const entry = exp["add_one"] as (p: number) => number;
    let heldPtr = 0;
    let heldBytes = 0;
    let terminated = false;
    const mock = {
      onmessage: null as null | ((ev: { data: unknown }) => void),
      onerror: null as null | ((ev: unknown) => void),
      postMessage(msg: Record<string, unknown>) {
        if (terminated) return;
        const seq = msg.seq as number;
        queueMicrotask(() => {
          if (terminated) return;
          if (msg.kind === "init") {
            mock.onmessage?.({
              data: {
                kind: "init_ok",
                seq,
                memoryBytes: mem.buffer.byteLength,
              },
            });
          } else if (msg.kind === "run") {
            reset(0);
            const inBytes = msg.bytes as Uint8Array;
            const words = inBytes.byteLength >>> 2;
            const ptr = alloc((words + 1) * 4) >>> 0;
            new DataView(mem.buffer).setUint32(ptr, words, true);
            new Uint8Array(mem.buffer, ptr + 4, inBytes.byteLength).set(
              inBytes,
            );
            heldPtr = entry(ptr) >>> 0;
            heldBytes = new DataView(mem.buffer).getUint32(heldPtr, true) * 4;
            mock.onmessage?.({
              data: { kind: "ready", seq, resultBytes: heldBytes },
            });
          } else if (msg.kind === "copy_grant_fixed") {
            if (holdGrantReply) return; // Hold transferred outputBuf without replying!
            const buf = msg.outputBuf as ArrayBuffer;
            new Uint8Array(buf, msg.byteOffset as number, heldBytes).set(
              new Uint8Array(mem.buffer, heldPtr + 4, heldBytes),
            );
            mock.onmessage?.({
              data: {
                kind: "payload_fixed",
                seq,
                outputBuf: buf,
                memoryBytes: mem.buffer.byteLength,
              },
            });
          }
        });
      },
      terminate() {
        terminated = true;
      },
    };
    return mock;
  };

  // (a) Browser close() AFTER transfer: permanently retires outputBuf + slot memory!
  const browserReceipt = compileBrowserKernelModule(bytes);
  let atTransferResolve!: () => void;
  const atTransfer = new Promise<void>((r) => {
    atTransferResolve = r;
  });
  const bPoolTransfer = await BrowserKernelPool.open(
    browserReceipt,
    "add_one",
    {
      workers: 1,
      deadlineMs: 2000,
      _testHooks: {
        workerFactory: makeMockWorkerFactory(true),
        onAfterFixedGrantTransfer: () => {
          atTransferResolve();
        },
      },
    },
  );
  const bRunP = bPoolTransfer.runFixed(Uint32Array.of(1, 2, 3));
  await atTransfer;
  const bCloseP = bPoolTransfer.close();
  await rejects(
    () => bRunP,
    (e: unknown) => e instanceof BrowserKernelError && e.code === "pool_closed",
  );
  await bCloseP;
  // Unacknowledged 12 B outputBuf + slot memory MUST be permanently retired (never falsely freed)!
  equal(bPoolTransfer.stats.permanentlyRetiredBytes >= 12, true);
  equal(bPoolTransfer.stats.fixedOutputBytes, 0);

  // (b) Browser close() right after READY (BEFORE [outputBuf] transfer):
  //     coordinator drops coordinator-owned outputBuf and releases ALL charges cleanly (0 permanently retired transfer!)
  let atReadyBeforeTransfer!: () => void;
  const readyBeforeTransferGate = new Promise<void>((r) => {
    atReadyBeforeTransfer = r;
  });
  let releaseReadyBeforeTransfer!: () => void;
  const holdReadyBeforeTransfer = new Promise<void>((r) => {
    releaseReadyBeforeTransfer = r;
  });
  const bPoolBeforeTransfer = await BrowserKernelPool.open(
    browserReceipt,
    "add_one",
    {
      workers: 1,
      deadlineMs: 2000,
      _testHooks: {
        workerFactory: makeMockWorkerFactory(false),
        onAfterReady: async () => {
          atReadyBeforeTransfer();
          await holdReadyBeforeTransfer;
        },
      },
    },
  );
  const bRunBeforeP = bPoolBeforeTransfer.runFixed(Uint32Array.of(1, 2, 3));
  await readyBeforeTransferGate;
  const bCloseBeforeP = bPoolBeforeTransfer.close();
  releaseReadyBeforeTransfer();
  await rejects(
    () => bRunBeforeP,
    (e: unknown) => e instanceof BrowserKernelError && e.code === "pool_closed",
  );
  await bCloseBeforeP;
  equal(bPoolBeforeTransfer.stats.fixedOutputBytes, 0);
  equal(bPoolBeforeTransfer.stats.currentChargedBytes, 0);

  // (c) Deno overlapping setContext -> ContextOperationInProgress, and close() overlapping setContext -> PoolClosed!
  let ctxEntered!: () => void;
  const ctxEnteredGate = new Promise<void>((r) => {
    ctxEntered = r;
  });
  let ctxRelease!: () => void;
  const ctxHoldGate = new Promise<void>((r) => {
    ctxRelease = r;
  });
  const ctxClosePool = await KernelPool.open(receipt, "with_ctx", {
    workers: 1,
    deadlineMs: 2000,
    _testHooks: {
      onBeforeContextPublish: async () => {
        ctxEntered();
        await ctxHoldGate;
      },
    },
  });
  const set1P = ctxClosePool.setContext(1, Uint32Array.of(77));
  await ctxEnteredGate;
  await rejects(
    () => ctxClosePool.setContext(2, Uint32Array.of(88)),
    (e: unknown) =>
      e instanceof KernelError && e.code === "context_operation_in_progress",
  );
  const closeCtxP = ctxClosePool.close();
  ctxRelease();
  await rejects(
    () => set1P,
    (e: unknown) => e instanceof KernelError && e.code === "pool_closed",
  );
  await closeCtxP;
  equal(ctxClosePool.stats.contextSnapshotBytes, 0);
});

// ---------------------------------------------------------------------------
// Law #5 — Processes (Deno + process_subprocess.ts)
// ---------------------------------------------------------------------------

const processSuiteSource = `
// 1. Bare U32 (scalar-only possible when compiled alone)
func u32_init (seed: U32): U32 => return seed
func u32_step (st: own U32) -> (cmd: U32): (U32, U32) =>
  let next = @u32.add st cmd
  return (next, next)
#process const p_u32: Process [U32, U32, U32] = { init: u32_init, step: u32_step }

// 2. Bare Bool
func bool_init (seed: Bool): Bool => return seed
func bool_step (st: own Bool) -> (flip: Bool): (Bool, Bool) =>
  let next = if flip then (not st) else st
  return (next, next)
#process const p_bool: Process [Bool, Bool, Bool] = { init: bool_init, step: bool_step }

// 3. Bare F32
func f32_init (seed: F32): F32 => return seed
func f32_step (st: own F32) -> (add: F32): (F32, F32) =>
  let next = @f32.add st add
  return (next, next)
#process const p_f32: Process [F32, F32, F32] = { init: f32_init, step: f32_step }

// 4. 1-word FlatNumeric record (PlannerReply = $Score { value: U32 }) -> wire_tag == 1 (U32)
type Score is data = $Score { value: U32 }
func score_init (seed: U32): U32 => return seed
func score_step (st: own U32) -> (delta: U32): (U32, Score) =>
  let next = @u32.add st delta
  return (next, $Score { value: next })
#process const p_score: Process [U32, U32, Score] = { init: score_init, step: score_step }

// 5. Unit -> Unit process (0 B logical reply, continuous mailbox slot check!)
func unit_init (u: Unit): U32 => return 0
func unit_step (st: own U32) -> (u: Unit): (U32, Unit) => return (@u32.add st 1, ())
#process const p_unit: Process [Unit, Unit, Unit] = { init: unit_init, step: unit_step }

// 6. Array config & array cmd/reply
func arr_init (cfg: #[U32]): U32 => return if cfg.length > 0 then cfg[0] else 0
func arr_step (st: own U32) -> (cmd: #[U32]): (U32, #[U32]) =>
  let add = if cmd.length > 0 then cmd[0] else 0
  let next = @u32.add st add
  return (next, #[next, @u32.add next 1])
#process const p_arr: Process [#[U32], #[U32], #[U32]] = { init: arr_init, step: arr_step }

// 7. Spinning init (0 = ok, 1 = spin forever, 2 = trap)
func spin_init_fn (mode: U32): U32 => return do:
  if mode == 1:
    for ever:
      continue
  if mode == 2:
    return @panic "init trap"
  return mode
func spin_step_fn (st: own U32) -> (cmd: U32): (U32, U32) => return do:
  if cmd == 999:
    for ever:
      continue
  if cmd == 888:
    return @panic "step trap"
  let next = @u32.add st cmd
  return (next, next)
#process const p_spin: Process [U32, U32, U32] = { init: spin_init_fn, step: spin_step_fn }

// 8. Slow step process for parallel timer-latch and equivalence tests
func work_init (seed: U32): U32 => return seed
func work_step (st: own U32) -> (iters: U32): (U32, U32) => return do:
  let acc = st
  for i in 0..iters:
    acc := @u32.add self 1
  return (acc, acc)
#process const p_work: Process [U32, U32, U32] = { init: work_init, step: work_step }
`;

const scalarOnlyProcessSource = `
func s_init (seed: F32): F32 => return seed
func s_step (st: own F32) -> (x: F32): (F32, F32) =>
  let next = @f32.add st x
  return (next, next)
#process const scalar_f32: Process [F32, F32, F32] = { init: s_init, step: s_step }
`;

Deno.test("Law #5: admission, all 4 ABI wire_tag categories (incl. scalar-only & 1-word Score & Unit mailbox=1), private copies & persistent two-turn accounting", async () => {
  const bytes = await compileBlot(processSuiteSource);
  const scalarBytes = await compileBlot(scalarOnlyProcessSource);
  const receipt = compileKernelModule(bytes);

  // 1. Admission checks: reject rustWasmtimeFuel, bad deadlineMs, maxReplyBytes < 4 for scalar/1-word record, opaque module!
  let threwFuel = false;
  try {
    new Processes(receipt, [{
      name: "p_u32",
      initWork: 1,
      stepWork: 1,
      rustWasmtimeFuel: { initFuel: 1000, stepFuel: 1000, cleanupFuel: 1000 },
      mailbox: 2,
      mailboxBytes: 64,
      maxReplyBytes: 4,
    }]);
  } catch (e) {
    threwFuel = e instanceof ProcessError && e.code === "fuel_unsupported";
  }
  equal(threwFuel, true);

  for (const name of ["p_u32", "p_bool", "p_f32", "p_score"]) {
    let threwWidth = false;
    try {
      new Processes(receipt, [{
        name,
        initWork: 1,
        stepWork: 1,
        mailbox: 2,
        mailboxBytes: 64,
        maxReplyBytes: 3, // MUST reject < 4 for wire_tag in {1, 2, 3}!
      }]);
    } catch (e) {
      threwWidth = e instanceof ProcessError && e.code === "invalid_config";
    }
    equal(threwWidth, true);
  }

  for (const badDl of [0, -5, Number.NaN, 2_147_483_648]) {
    let threwDl = false;
    try {
      new Processes(receipt, [{
        name: "p_u32",
        initWork: 1,
        stepWork: 1,
        deadlineMs: badDl,
        mailbox: 2,
        mailboxBytes: 64,
        maxReplyBytes: 4,
      }]);
    } catch (e) {
      threwDl = e instanceof ProcessError && e.code === "invalid_config";
    }
    equal(threwDl, true);
  }

  // 2. Zero-exported-memory scalar-only F32 process over Deno subprocess (COMMIT_OK_SCALAR)!
  const scalarReceipt = compileKernelModule(scalarBytes);
  equal(
    WebAssembly.Module.exports(scalarReceipt.module).some((e) =>
      e.name === "blot:memory"
    ),
    false,
  );
  const scalarHost = new Processes(scalarReceipt, [{
    name: "scalar_f32",
    initWork: 1,
    stepWork: 1,
    deadlineMs: 2000,
    mailbox: 2,
    mailboxBytes: 64,
    maxReplyBytes: 4,
  }]);
  try {
    const h = scalarHost.admit("scalar_f32", 40.0)!;
    equal(scalarHost.residentMemoryBytes, 0); // Reserved only at advance() before spawn!
    await scalarHost.advance(1);
    equal(scalarHost.status(h), "ready");
    equal(scalarHost.residentMemoryBytes > 0, true);
    const memAfterInit = scalarHost.residentMemoryBytes;

    // Two sequential turns on persistent zero-exported-memory child!
    const t1 = scalarHost.send(h, 2.0) as number;
    await scalarHost.advance(1);
    const e1 = scalarHost.poll(h);
    equal(e1?.status, "done");
    if (e1?.status === "done") {
      equal(e1.ticket, t1);
      equal(e1.value, 42.0);
      equal(e1.logicalReplyBytes, 4);
    }
    equal(scalarHost.residentMemoryBytes, memAfterInit);

    const t2 = scalarHost.send(h, 8.5) as number;
    await scalarHost.advance(1);
    const e2 = scalarHost.poll(h);
    equal(e2?.status, "done");
    if (e2?.status === "done") {
      equal(e2.ticket, t2);
      equal(e2.value, 50.5);
    }
  } finally {
    await scalarHost.restore();
    equal(scalarHost.residentMemoryBytes, 0);
    equal(scalarHost.activeSubprocesses, 0);
  }

  // 3. All 4 ABI wire_tag categories over persistent Deno subprocesses + private slice-overridden copies!
  const procs = new Processes(receipt, [
    {
      name: "p_u32",
      initWork: 1,
      stepWork: 1,
      deadlineMs: 2000,
      mailbox: 2,
      mailboxBytes: 64,
      maxReplyBytes: 4,
    },
    {
      name: "p_bool",
      initWork: 1,
      stepWork: 1,
      deadlineMs: 2000,
      mailbox: 2,
      mailboxBytes: 64,
      maxReplyBytes: 4,
    },
    {
      name: "p_f32",
      initWork: 1,
      stepWork: 1,
      deadlineMs: 2000,
      mailbox: 2,
      mailboxBytes: 64,
      maxReplyBytes: 4,
    },
    {
      name: "p_score",
      initWork: 1,
      stepWork: 1,
      deadlineMs: 2000,
      mailbox: 2,
      mailboxBytes: 64,
      maxReplyBytes: 4,
    },
    {
      name: "p_unit",
      initWork: 1,
      stepWork: 1,
      deadlineMs: 2000,
      mailbox: 1,
      mailboxBytes: 0,
      maxReplyBytes: 0,
    },
    {
      name: "p_arr",
      initWork: 1,
      stepWork: 1,
      deadlineMs: 2000,
      mailbox: 2,
      mailboxBytes: 128,
      maxReplyBytes: 16,
    },
  ], { slots: 8 });
  try {
    const hU32 = procs.admit("p_u32", 40)!;
    const hBool = procs.admit("p_bool", false)!;
    const hF32 = procs.admit("p_f32", 1.5)!;
    const hScore = procs.admit("p_score", 10)!;
    const hUnit = procs.admit("p_unit", null)!;

    // Array Config with overridden slice() mutated BEFORE advance()!
    const cfgArr = Uint32Array.of(100, 200);
    Object.defineProperty(cfgArr, "slice", {
      value() {
        return this;
      },
    });
    const hArr = procs.admit("p_arr", cfgArr)!;
    equal(procs.mailboxBytesReserved, 8); // Charged immediately at admit()!
    cfgArr.fill(0);

    await procs.advanceAllParallel(6);
    equal(procs.mailboxBytesReserved, 0); // Released on INIT_OK!

    // Mutate slice-overridden array cmd right after send()!
    const cmdArr = Uint32Array.of(23);
    Object.defineProperty(cmdArr, "slice", {
      value() {
        return this;
      },
    });
    procs.send(hU32, 2);
    procs.send(hBool, true);
    procs.send(hF32, 40.5);
    procs.send(hScore, 5);
    procs.send(hUnit, null);
    procs.send(hArr, cmdArr);
    cmdArr.fill(999);

    // Continuous mailbox=1 slot enforcement on 0-byte Unit -> Unit process!
    equal(procs.send(hUnit, null), "full");

    await procs.advanceAllParallel(6);

    // Unit -> Unit Done event STILL occupies its 1 mailbox slot until poll()!
    equal(procs.send(hUnit, null), "full");
    const evUnit = procs.poll(hUnit);
    equal(evUnit?.status, "done");
    if (evUnit?.status === "done") {
      equal(evUnit.value, null);
      equal(evUnit.logicalReplyBytes, 0);
    }
    // After poll(), slot is free again!
    equal(typeof procs.send(hUnit, null), "number");

    const evU32 = procs.poll(hU32);
    equal(
      evU32?.status === "done" && evU32.value === 42 &&
        evU32.logicalReplyBytes === 4,
      true,
    );
    const evBool = procs.poll(hBool);
    equal(
      evBool?.status === "done" && evBool.value === true &&
        evBool.logicalReplyBytes === 4,
      true,
    );
    const evF32 = procs.poll(hF32);
    equal(
      evF32?.status === "done" && evF32.value === 42.0 &&
        evF32.logicalReplyBytes === 4,
      true,
    );
    const evScore = procs.poll(hScore);
    equal(
      evScore?.status === "done" && evScore.value === 15 &&
        evScore.logicalReplyBytes === 4,
      true,
    );
    const evArr = procs.poll(hArr);
    equal(evArr?.status, "done");
    if (evArr?.status === "done") {
      equal(String(evArr.value), "123,124");
      equal(evArr.logicalReplyBytes, 8);
    }
    // Verify state persisted across Turn 1 -> Turn 2 on p_arr!
    procs.send(hArr, Uint32Array.of(7));
    await procs.advance(2);
    const evArr2 = procs.poll(hArr);
    equal(
      evArr2?.status === "done" && String(evArr2.value) === "130,131",
      true,
    );
  } finally {
    await procs.restore();
    equal(procs.residentMemoryBytes, 0);
    equal(procs.mailboxBytesReserved, 0);
    equal(procs.activeSubprocesses, 0);
  }

  // 4. Defensive framed-reply validator rejects COMMIT_OK_SCALAR under maxReplyBytes = 3 as DeterministicFail!
  const badWidthHost = new Processes(receipt, [{
    name: "p_score",
    initWork: 1,
    stepWork: 1,
    deadlineMs: 2000,
    mailbox: 2,
    mailboxBytes: 64,
    maxReplyBytes: 4,
  }], { _testHooks: { overrideValidatorMaxReplyBytes: 3 } });
  try {
    const h = badWidthHost.admit("p_score", 1)!;
    await badWidthHost.advance(1);
    badWidthHost.send(h, 2);
    await badWidthHost.advance(1);
    equal(badWidthHost.status(h), "failed");
    equal(badWidthHost.poll(h)?.status, "failed");
    equal(badWidthHost.residentMemoryBytes, 0);
    equal(badWidthHost.activeSubprocesses, 0);
  } finally {
    await badWidthHost.restore();
  }
});

Deno.test("Law #5(f)-(h): spinning init/step preemption, timer-latch honor, never-spawned close, sync spawn fail, close-before-commit & exclusive restore-vs-overrun drain", async () => {
  const bytes = await compileBlot(processSuiteSource);
  const receipt = compileKernelModule(bytes);

  // 1. Spinning proc_init preempted via kill-first retireSubprocess + idle persistent child reaped!
  const spinInitHost = new Processes(receipt, [
    {
      name: "p_u32",
      initWork: 1,
      stepWork: 5,
      deadlineMs: 2000,
      mailbox: 2,
      mailboxBytes: 64,
      maxReplyBytes: 4,
    },
    {
      name: "p_spin",
      initWork: 1,
      stepWork: 1,
      deadlineMs: 80,
      mailbox: 2,
      mailboxBytes: 64,
      maxReplyBytes: 4,
    },
  ]);
  const idleH = spinInitHost.admit("p_u32", 10)!;
  await spinInitHost.advance(1);
  // Give idle child an unpolled Done AND a queued ticket (stepWork=5 won't fit in advance(2))!
  spinInitHost.send(idleH, 5);
  await spinInitHost.advance(5);
  spinInitHost.send(idleH, 6); // Stays queued during advance(2)!
  spinInitHost.admit("p_spin", 1)!; // mode 1 = spin forever inside init (initWork=1 fits advance(2))!
  let overrunErr: ProcessOverrunError | null = null;
  try {
    await spinInitHost.advance(2);
  } catch (e) {
    if (e instanceof ProcessOverrunError) overrunErr = e;
    else throw e;
  }
  equal(overrunErr !== null, true);
  equal(spinInitHost.aborted, true);
  equal(spinInitHost.activeSubprocesses, 0);
  equal(spinInitHost.residentMemoryBytes, 0);
  equal(spinInitHost.mailboxBytesReserved, 0);
  // Idle child's unpolled Done (15) + queued Cancelled ticket MUST be in drainedEvents!
  const drainedIdle = overrunErr!.drainedEvents.get(idleH);
  equal(drainedIdle?.length, 2);
  equal(drainedIdle?.[0].status, "done");
  equal(drainedIdle?.[1].status, "cancelled");
  // Later post-abort restore() returns empty map!
  equal((await spinInitHost.restore()).size, 0);

  // 2. Never-spawned close(), sync spawn failure, & slots=1 release() retirement lifecycle!
  const lifecycleHost = new Processes(receipt, [
    {
      name: "p_arr",
      initWork: 1,
      stepWork: 1,
      deadlineMs: 2000,
      mailbox: 2,
      mailboxBytes: 64,
      maxReplyBytes: 16,
    },
    {
      name: "p_u32",
      initWork: 1,
      stepWork: 1,
      deadlineMs: 2000,
      mailbox: 2,
      mailboxBytes: 64,
      maxReplyBytes: 4,
    },
  ], {
    slots: 1,
    _testHooks: { failSpawnForName: new Set(["p_u32"]) },
  });
  try {
    // Never-spawned admit -> close BEFORE first advance()!
    const hNever = lifecycleHost.admit("p_arr", Uint32Array.of(7, 8))!;
    equal(lifecycleHost.mailboxBytesReserved, 8);
    await lifecycleHost.close(hNever);
    equal(lifecycleHost.mailboxBytesReserved, 0);
    equal(lifecycleHost.release(hNever), true);

    // Synchronous spawn() failure settles via child.settlementDone and releases memory!
    const hBadSpawn = lifecycleHost.admit("p_u32", 1)!;
    await lifecycleHost.advance(1);
    equal(lifecycleHost.status(hBadSpawn), "failed");
    equal(lifecycleHost.residentMemoryBytes, 0);
    equal(lifecycleHost.release(hBadSpawn), true);
  } finally {
    await lifecycleHost.restore();
  }

  // 3. release() returns false while "retiring", cancel() rejected during retirement, close-then-restore joins settlementDone!
  let holdRetireResolve!: () => void;
  const holdRetire = new Promise<void>((r) => {
    holdRetireResolve = r;
  });
  let enteredRetireResolve!: () => void;
  const enteredRetire = new Promise<void>((r) => {
    enteredRetireResolve = r;
  });
  const retireHost = new Processes(receipt, [{
    name: "p_u32",
    initWork: 1,
    stepWork: 1,
    deadlineMs: 2000,
    mailbox: 2,
    mailboxBytes: 64,
    maxReplyBytes: 4,
  }], {
    slots: 1,
    _testHooks: {
      onBeforeRetireFinish: async () => {
        enteredRetireResolve();
        await holdRetire;
      },
    },
  });
  const hRet = retireHost.admit("p_u32", 1)!;
  await retireHost.advance(1);
  const queuedT = retireHost.send(hRet, 9) as number;
  const bytesBeforeClose = retireHost.mailboxBytesReserved;
  const closeP = retireHost.close(hRet);
  await enteredRetire;
  // While retiring: cancel() rejected (no early release!), release() returns false!
  equal(retireHost.cancel(hRet, queuedT), false);
  equal(retireHost.release(hRet), false);
  equal(retireHost.mailboxBytesReserved, bytesBeforeClose);
  // restore() started while close() is paused joins child.settlementDone and drains cancelled event!
  const restoreP = retireHost.restore();
  holdRetireResolve();
  const [_, restoredMap] = await Promise.all([closeP, restoreP]);
  equal(restoredMap.get(hRet)?.[0].status, "cancelled");
  equal(retireHost.mailboxBytesReserved, 0);
  equal(retireHost.residentMemoryBytes, 0);

  // 4. 2-child parallel wave: Child A latches onTimeCaptured (short 60ms deadline),
  //    Child B takes longer (~100ms, 500ms deadline); forcing Child A's timer callback
  //    after Child A commits MUST NOT abort Child B's wave!
  const capturedStepTimers = new Map<number, () => void>();
  let childAResolved = false;
  const latchHost = new Processes(receipt, [
    {
      name: "p_u32",
      initWork: 1,
      stepWork: 1,
      deadlineMs: 60,
      mailbox: 2,
      mailboxBytes: 64,
      maxReplyBytes: 4,
    },
    {
      name: "p_work",
      initWork: 1,
      stepWork: 1,
      deadlineMs: 1000,
      mailbox: 2,
      mailboxBytes: 64,
      maxReplyBytes: 4,
    },
  ], {
    _testHooks: {
      onTimerArmed: ({ kind, endpoint, fire }) => {
        if (kind === "step") capturedStepTimers.set(endpoint, fire);
      },
      onAfterChildWaveResult: async ({ endpoint, kind }) => {
        if (kind === "step" && endpoint === hFast.endpoint) {
          childAResolved = true;
          // Wait past Child A's 60ms deadline AND fire Child A's timer callback!
          await new Promise((r) => setTimeout(r, 80));
          capturedStepTimers.get(hFast.endpoint)?.();
        }
      },
    },
  });
  const hFast = latchHost.admit("p_u32", 10)!;
  const hSlow = latchHost.admit("p_work", 0)!;
  try {
    await latchHost.advanceAllParallel(2);
    latchHost.send(hFast, 5);
    latchHost.send(hSlow, 200);
    equal(await latchHost.advanceAllParallel(2), 2);
    equal(childAResolved, true);
    const evFast = latchHost.poll(hFast);
    const evSlow = latchHost.poll(hSlow);
    equal(evFast?.status === "done" && evFast.value === 15, true);
    equal(evSlow?.status === "done" && evSlow.value === 200, true);
  } finally {
    await latchHost.restore();
  }

  // 5. Close-before-commit timer disarm: close(childA) before commit while childB runs,
  //    fire childA's stale timer callback -> childB's wave is NEVER aborted!
  const staleTimers = new Map<number, () => void>();
  const closeMidHost = new Processes(receipt, [
    {
      name: "p_spin",
      initWork: 1,
      stepWork: 1,
      deadlineMs: 80,
      mailbox: 2,
      mailboxBytes: 64,
      maxReplyBytes: 4,
    },
    {
      name: "p_work",
      initWork: 1,
      stepWork: 1,
      deadlineMs: 2000,
      mailbox: 2,
      mailboxBytes: 64,
      maxReplyBytes: 4,
    },
  ], {
    _testHooks: {
      onTimerArmed: ({ kind, endpoint, fire }) => {
        if (kind === "step") staleTimers.set(endpoint, fire);
      },
    },
  });
  const hSpinA = closeMidHost.admit("p_spin", 0)!;
  const hGoodB = closeMidHost.admit("p_work", 5)!;
  try {
    await closeMidHost.advanceAllParallel(2);
    closeMidHost.send(hSpinA, 999); // Spins!
    closeMidHost.send(hGoodB, 50);
    const waveP = closeMidHost.advanceAllParallel(2);
    // Close hSpinA immediately BEFORE its 80ms deadline!
    await closeMidHost.close(hSpinA);
    // Wait past hSpinA's original 80ms deadline and fire its captured stale timer callback!
    await new Promise((r) => setTimeout(r, 100));
    staleTimers.get(hSpinA.endpoint)?.();
    await waveP;
    const evB = closeMidHost.poll(hGoodB);
    equal(evB?.status === "done" && evB.value === 55, true);
  } finally {
    await closeMidHost.restore();
  }

  // 6. Exclusive drain owner (#exclusiveTransition): restore() claims "restoring" FIRST
  //    while a spinning child's deadline expires mid-teardown -> restore() wins cleanly, wave skips Overrun!
  let restoreEnteredRetire!: () => void;
  const restoreAtRetire = new Promise<void>((r) => {
    restoreEnteredRetire = r;
  });
  let releaseRestoreRetire!: () => void;
  const restoreRetireGate = new Promise<void>((r) => {
    releaseRestoreRetire = r;
  });
  const raceHost = new Processes(receipt, [
    {
      name: "p_u32",
      initWork: 1,
      stepWork: 1,
      deadlineMs: 2000,
      mailbox: 2,
      mailboxBytes: 64,
      maxReplyBytes: 4,
    },
    {
      name: "p_spin",
      initWork: 1,
      stepWork: 1,
      deadlineMs: 60,
      mailbox: 2,
      mailboxBytes: 64,
      maxReplyBytes: 4,
    },
  ], {
    _testHooks: {
      onBeforeRetireFinish: async () => {
        restoreEnteredRetire();
        await restoreRetireGate;
      },
    },
  });
  const hDone = raceHost.admit("p_u32", 10)!;
  const hRaceSpin = raceHost.admit("p_spin", 0)!;
  await raceHost.advanceAllParallel(2);
  raceHost.send(hDone, 7);
  await raceHost.advance(1); // Unpolled Done(17)!
  raceHost.send(hRaceSpin, 999); // Spins with 60ms deadline!
  const waveRaceP = raceHost.advanceAllParallel(1);
  const restoreRaceP = raceHost.restore(); // Claims "restoring" BEFORE 60ms deadline!
  await restoreAtRetire;
  // Let 60ms deadline elapse while restore() owns #exclusiveTransition!
  await new Promise((r) => setTimeout(r, 90));
  releaseRestoreRetire();
  const drainedByRestore = await restoreRaceP;
  await waveRaceP; // Must return cleanly (NO ProcessOverrunError)!
  equal(raceHost.aborted, false);
  equal(drainedByRestore.get(hDone)?.[0].status, "done");
  equal(drainedByRestore.get(hRaceSpin)?.[0].status, "cancelled");

  // 7. Reverse exclusive drain order: Overrun claims "aborting" FIRST while restore() is called mid-teardown ->
  //    restore() is rejected with transition_in_progress, Overrun gets BOTH events, later restore() returns empty!
  let overrunEnteredRetire!: () => void;
  const overrunAtRetire = new Promise<void>((r) => {
    overrunEnteredRetire = r;
  });
  let releaseOverrunRetire!: () => void;
  const overrunRetireGate = new Promise<void>((r) => {
    releaseOverrunRetire = r;
  });
  const abortFirstHost = new Processes(receipt, [
    {
      name: "p_u32",
      initWork: 1,
      stepWork: 5,
      deadlineMs: 2000,
      mailbox: 2,
      mailboxBytes: 64,
      maxReplyBytes: 4,
    },
    {
      name: "p_spin",
      initWork: 1,
      stepWork: 1,
      deadlineMs: 50,
      mailbox: 2,
      mailboxBytes: 64,
      maxReplyBytes: 4,
    },
  ], {
    _testHooks: {
      onBeforeRetireFinish: async () => {
        overrunEnteredRetire();
        await overrunRetireGate;
      },
    },
  });
  const hDone2 = abortFirstHost.admit("p_u32", 20)!;
  const hSpin2 = abortFirstHost.admit("p_spin", 0)!;
  await abortFirstHost.advanceAllParallel(2);
  abortFirstHost.send(hDone2, 3);
  await abortFirstHost.advance(5); // Unpolled Done(23)!
  abortFirstHost.send(hDone2, 9); // Queued (stepWork=5 won't run in advanceAllParallel(1))!
  abortFirstHost.send(hSpin2, 999); // Spins past 50ms!
  const abortWaveP = abortFirstHost.advanceAllParallel(1);
  await overrunAtRetire;
  await rejects(
    () => abortFirstHost.restore(),
    (e: unknown) =>
      e instanceof ProcessError && e.code === "transition_in_progress",
  );
  releaseOverrunRetire();
  let abortErr: ProcessOverrunError | null = null;
  try {
    await abortWaveP;
  } catch (e) {
    if (e instanceof ProcessOverrunError) abortErr = e;
    else throw e;
  }
  equal(abortErr !== null, true);
  equal(abortErr!.drainedEvents.get(hDone2)?.length, 2);
  equal(abortErr!.drainedEvents.get(hDone2)?.[0].status, "done");
  equal(abortErr!.drainedEvents.get(hDone2)?.[1].status, "cancelled");
  equal((await abortFirstHost.restore()).size, 0);

  // 8. #runningGeneration race: fresh-generation advance() starts BEFORE old wave's finally microtask runs!
  let holdOldFinally!: () => void;
  const oldFinallyGate = new Promise<void>((r) => {
    holdOldFinally = r;
  });
  let oldFinallyEntered!: () => void;
  const oldFinallyEnteredGate = new Promise<void>((r) => {
    oldFinallyEntered = r;
  });
  let trapNextFinally = false;
  let trappedGen = -1;
  const genHost = new Processes(receipt, [
    {
      name: "p_spin",
      initWork: 1,
      stepWork: 1,
      deadlineMs: 2000,
      mailbox: 2,
      mailboxBytes: 64,
      maxReplyBytes: 4,
    },
    {
      name: "p_u32",
      initWork: 1,
      stepWork: 1,
      deadlineMs: 2000,
      mailbox: 2,
      mailboxBytes: 64,
      maxReplyBytes: 4,
    },
  ], {
    _testHooks: {
      onBeforeAdvanceFinally: async (gen) => {
        if (trapNextFinally && trappedGen === -1) {
          trappedGen = gen;
          oldFinallyEntered();
          await oldFinallyGate;
        }
      },
    },
  });
  try {
    const hGenSpin = genHost.admit("p_spin", 0)!;
    await genHost.advance(1);
    genHost.send(hGenSpin, 999);
    trapNextFinally = true;
    const oldWaveP = genHost.advanceAllParallel(1);
    await genHost.restore(); // Resets #runningGeneration = null & bumps generation!
    await oldFinallyEnteredGate;
    // Start a fresh-generation advance() BEFORE oldWaveP's finally finishes!
    const hFresh = genHost.admit("p_u32", 5)!;
    const freshAdvP = genHost.advance(1);
    holdOldFinally(); // Now let old wave's finally run — MUST NOT clobber fresh #runningGeneration!
    await Promise.all([oldWaveP, freshAdvP]);
    equal(genHost.status(hFresh), "ready");
  } finally {
    await genHost.restore();
  }
});

Deno.test("Law #5: exhaustive 3-endpoint advanceAllParallel == serial advance non-fatal equivalence", async () => {
  const bytes = await compileBlot(processSuiteSource);
  const receipt = compileKernelModule(bytes);

  const runSeq = async (parallel: boolean, budgets: number[]) => {
    const host = new Processes(receipt, [
      {
        name: "p_u32",
        initWork: 1,
        stepWork: 1,
        mailbox: 4,
        mailboxBytes: 128,
        maxReplyBytes: 4,
      },
      {
        name: "p_work",
        initWork: 2,
        stepWork: 2,
        mailbox: 4,
        mailboxBytes: 128,
        maxReplyBytes: 4,
      },
      {
        name: "p_score",
        initWork: 1,
        stepWork: 3,
        mailbox: 4,
        mailboxBytes: 128,
        maxReplyBytes: 4,
      },
    ], { slots: 4 });
    try {
      const a = host.admit("p_u32", 1)!;
      const b = host.admit("p_work", 10)!;
      const c = host.admit("p_score", 100)!;
      const trace: string[] = [];
      for (let step = 0; step < budgets.length; step++) {
        const bgt = budgets[step];
        const spent = parallel
          ? await host.advanceAllParallel(bgt)
          : await host.advance(bgt);
        trace.push(`spent=${spent}`);
        if (host.status(a) === "ready") host.send(a, step + 1);
        if (host.status(b) === "ready") host.send(b, step + 2);
        if (host.status(c) === "ready") host.send(c, step + 3);
        for (const [label, h] of [["a", a], ["b", b], ["c", c]] as const) {
          let ev;
          while ((ev = host.poll(h)) !== undefined) {
            trace.push(`${label}:${JSON.stringify(ev)}`);
          }
        }
      }
      return trace;
    } finally {
      await host.restore();
    }
  };

  for (
    const budgets of [
      [1, 2, 3, 2, 4, 5, 1, 3, 6],
      [4, 2, 2, 3, 3, 5, 2, 1, 4],
      [2, 2, 2, 2, 5, 5, 3, 3, 3],
    ]
  ) {
    const serial = await runSeq(false, budgets);
    const parallel = await runSeq(true, budgets);
    equal(JSON.stringify(parallel), JSON.stringify(serial));
  }
});
