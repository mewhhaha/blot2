import { rejects } from "node:assert/strict";
import { compileKernelModule } from "../../host/guest.ts";
import { KernelError, KernelPool } from "../../host/kernels.ts";
import { compileAndRun, equal } from "./compile_helpers.ts";

const fixture = `
func prepare_mask (mask: U32): U32 => return mask
func run_with_mask (mask: U32) -> (x: U32): U32 => return @u32.bit_xor mask x
#kernel const with_world: Kernel [U32, U32, U32] = { prepare: prepare_mask, run: run_with_mask }

#kernel func fault (x: U32): U32 => return if x == 1 then @panic "worker trap" else x

#kernel func stalled (x: U32): U32 => return do:
  if x == 1:
    for ever:
      continue
  return x
`;

Deno.test("KernelPool enforces true 1x fixed-output peak, private snapshot isolation and ContextNotPrepared", async () => {
  await compileAndRun(fixture, async (_guest, bytes) => {
    const receipt = compileKernelModule(bytes);
    const pool = await KernelPool.open(receipt, "with_world", {
      workers: 2,
      defaultChunkItems: 1,
      maxTotalOutputBytes: 12,
      maxPhysicalOutputBytes: 12,
      deadlineMs: 2000,
    });
    try {
      // Prepared kernel must reject even empty batch before setContext!
      await rejects(
        () => pool.runFixed(new Uint32Array(0)),
        (err: unknown) =>
          err instanceof KernelError && err.code === "context_not_prepared",
      );

      const ctxBuf = Uint32Array.of(0x0100_0001);
      const setP = pool.setContext(1, ctxBuf);
      ctxBuf[0] = 0; // Mutate caller buffer immediately after call!
      await setP;
      equal(pool.stats.contextSnapshotBytes, 4);

      const input = Uint32Array.of(0, 1, 2);
      const out = await pool.runFixed(input);
      equal(String(out), "16777217,16777216,16777219");
      // True 1x single-buffer peak (3 * 4 == 12 bytes)!
      equal(pool.stats.peakChargedBytes, 12);
      equal(pool.stats.currentChargedBytes, 0);

      // Exceeding maxTotalOutputBytes fails cleanly up front.
      await rejects(
        () => pool.runFixed(Uint32Array.of(0, 1, 2, 3)),
        (err: unknown) =>
          err instanceof KernelError && err.code === "output_budget_exceeded",
      );

      // Empty batch succeeds after setContext and fails again after clearContext.
      equal((await pool.runFixed(new Uint32Array(0))).length, 0);
      await pool.clearContext();
      equal(pool.stats.contextSnapshotBytes, 0);
      await rejects(
        () => pool.runFixed(new Uint32Array(0)),
        (err: unknown) =>
          err instanceof KernelError && err.code === "context_not_prepared",
      );
    } finally {
      await pool.close();
      equal(pool.stats.activeSubprocesses, 0);
      equal(pool.stats.workerMemoryBytes, 0);
    }
  });
});

Deno.test("KernelPool stages replies in exact input order across workers 0, 1, 2, 4", async () => {
  await compileAndRun(fixture, async (_guest, bytes) => {
    const receipt = compileKernelModule(bytes);
    const direct = await KernelPool.open(receipt, "with_world", {
      workers: 0,
      defaultChunkItems: 2,
    });
    await direct.setContext(1, Uint32Array.of(0x0100_0000));
    try {
      const rows = Uint32Array.of(5, 4, 3, 2, 1, 0, 0xffffffff);
      const expected = await direct.runFixed(rows);
      for (const workers of [1, 2, 4]) {
        const pool = await KernelPool.open(receipt, "with_world", {
          workers,
          defaultChunkItems: 2,
          deadlineMs: 2000,
        });
        await pool.setContext(1, Uint32Array.of(0x0100_0000));
        try {
          equal((await pool.runFixed(new Uint32Array())).length, 0);
          equal(String(await pool.runFixed(rows)), String(expected));
        } finally {
          await pool.close();
          equal(pool.stats.activeSubprocesses, 0);
        }
      }
    } finally {
      await direct.close();
    }
  });
});

Deno.test("KernelPool handles real Wasm traps and preempts spinning subprocesses under deadlineMs", async () => {
  await compileAndRun(fixture, async (_guest, bytes) => {
    const receipt = compileKernelModule(bytes);
    const faultPool = await KernelPool.open(receipt, "fault", {
      workers: 2,
      defaultChunkItems: 1,
      deadlineMs: 2000,
    });
    try {
      await rejects(
        () => faultPool.runFixed(Uint32Array.of(7, 1, 9)),
        (err: unknown) =>
          err instanceof KernelError && err.code === "run_trap" &&
          err.startItem === 1,
      );
      // Warm pool survives deterministic trap and continues cleanly.
      equal(String(await faultPool.runFixed(Uint32Array.of(7, 8, 9))), "7,8,9");
    } finally {
      await faultPool.close();
      equal(faultPool.stats.activeSubprocesses, 0);
    }

    const stalledPool = await KernelPool.open(receipt, "stalled", {
      workers: 2,
      defaultChunkItems: 1,
      deadlineMs: 80,
    });
    try {
      const started = performance.now();
      await rejects(
        () => stalledPool.runFixed(Uint32Array.of(0xff00_0000, 1)),
        (err: unknown) =>
          err instanceof KernelError && err.code === "timeout",
      );
      equal(performance.now() - started < 2000, true);
      equal(stalledPool.stats.currentChargedBytes, 0);
    } finally {
      await stalledPool.close();
      equal(stalledPool.stats.activeSubprocesses, 0);
      equal(stalledPool.stats.workerMemoryBytes, 0);
    }
  });
});
