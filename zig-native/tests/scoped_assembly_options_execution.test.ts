import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
import { codeFunctionCount } from "../../scripts/bench/storage_calls.ts";

function workload(): string {
  const lines: string[] = [];
  for (let index = 0; index < 24; index++) {
    lines.push(
      `const f${index} = func (input: U32): U32 => return do:`,
      "  let value = input",
    );
    for (let step = 0; step < 64; step++) {
      lines.push(`  value := @u32.add value ${index + 1}`);
    }
    lines.push("  return value");
  }
  lines.push(
    "entry const answer = func (input: U32): U32 => return do:",
    "  let marker: GrowArray U32 = #[input]",
    "  let value = marker[0]",
  );
  for (let index = 0; index < 24; index++) {
    lines.push(`  value := f${index} value`);
  }
  lines.push("  return value");
  return lines.join("\n") + "\n";
}

interface Optimization {
  tier: string;
  functions: number;
  shared: number;
  workers: number;
  parallel_jobs: number;
  worker_timings:
    | null
    | Array<{
      jobs: number;
      instructions: number;
      started_us: number;
      finished_us: number;
    }>;
}

Deno.test("owned compilation forwards physical machine code sharing", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-owned-sharing-" });
  const entry = `${directory}/main.blot`;
  const source = `const left = func (input: U32): U32 => return @u32.add input 7
const right = func (input: U32): U32 => return @u32.add input 7
entry const answer = func (input: U32): U32 => return do:
  let marker: GrowArray U32 = #[input]
  return @u32.add (left marker[0]) (right marker[0])
`;
  let separateBytes = 0;
  try {
    for (const shareMachineCode of [false, true]) {
      const compiler = await createZigProjectCompiler({
        executable: Deno.args[0],
        entry,
        prelude: null,
        shareMachineCode,
        cacheDirectory: false,
        startupTimeoutMs: 5_000,
      });
      try {
        const result = await compiler.build({
          sources: { [entry]: source },
          signal: AbortSignal.timeout(5_000),
        });
        assert(result.success, JSON.stringify(result));
        const stats = result.stats
          .runtimeOptimization as unknown as Optimization;
        assert.equal(
          codeFunctionCount(result.bytes),
          stats.functions - stats.shared,
        );
        if (shareMachineCode) {
          assert(stats.shared > 0, JSON.stringify(stats));
          assert(result.bytes.length < separateBytes);
        } else {
          assert.equal(stats.shared, 0);
          separateBytes = result.bytes.length;
        }
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(result.bytes, { asynchronous });
          try {
            for (const input of [0, 1, 41, 0xfffffff0, 3, 0]) {
              let actual;
              if (asynchronous) actual = await guest.callAsync("answer", input);
              else actual = guest.call("answer", input);
              assert.equal(actual, ((input + 7) * 2) >>> 0);
            }
          } finally {
            guest.dispose();
          }
        }
      } finally {
        await compiler.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`owned compilation forwards assembly execution options (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-owned-options-" });
    const entry = `${directory}/main.blot`;
    const source = workload();
    let serial: Uint8Array | undefined;
    try {
      for (
        const [codegenWorkers, profileBackend] of [[1, false], [4, false], [
          4,
          true,
        ]] as const
      ) {
        const compiler = await createZigProjectCompiler({
          executable: Deno.args[0],
          entry,
          prelude: null,
          codegenTier,
          codegenWorkers,
          profileBackend,
          cacheDirectory: false,
          startupTimeoutMs: 5_000,
        });
        try {
          const result = await compiler.build({
            sources: { [entry]: source },
            signal: AbortSignal.timeout(5_000),
          });
          assert(result.success, JSON.stringify(result));
          const stats = result.stats
            .runtimeOptimization as unknown as Optimization;
          assert.equal(stats.tier, codegenTier);
          assert(stats.functions > 0, JSON.stringify(stats));
          if (codegenWorkers === 1) {
            serial = result.bytes;
            assert.equal(stats.workers, 1);
            assert.equal(stats.parallel_jobs, 0);
          } else {
            assert(
              stats.workers > 1 && stats.workers <= codegenWorkers,
              JSON.stringify(stats),
            );
            assert(stats.parallel_jobs >= 4, JSON.stringify(stats));
            assert.deepEqual(result.bytes, serial);
          }
          if (profileBackend) {
            assert(stats.worker_timings, JSON.stringify(stats));
            assert.equal(
              stats.worker_timings.reduce(
                (sum, worker) => sum + worker.jobs,
                0,
              ),
              stats.parallel_jobs,
            );
            assert(
              stats.worker_timings.reduce(
                (sum, worker) => sum + worker.instructions,
                0,
              ) >= 4096,
            );
            assert(
              stats.worker_timings.some((worker) =>
                worker.finished_us > worker.started_us
              ),
            );
          } else assert.equal(stats.worker_timings, null);
          for (const asynchronous of [false, true]) {
            const guest = await instantiateGuest(result.bytes, {
              asynchronous,
            });
            try {
              for (const input of [0, 1, 41, 0xfffffff0, 3, 0]) {
                let actual;
                if (asynchronous) {
                  actual = await guest.callAsync("answer", input);
                } else actual = guest.call("answer", input);
                // Each helper adds its ordinal 64 times; all 24 are called.
                let expected = input;
                for (let ordinal = 1; ordinal <= 24; ordinal++) {
                  expected += ordinal * 64;
                }
                assert.equal(actual, expected >>> 0);
              }
            } finally {
              guest.dispose();
            }
          }
        } finally {
          await compiler.dispose();
        }
      }
      const tiny = await createZigProjectCompiler({
        executable: Deno.args[0],
        entry,
        prelude: null,
        codegenTier,
        codegenWorkers: 4,
        profileBackend: true,
        cacheDirectory: false,
        startupTimeoutMs: 5_000,
      });
      try {
        const result = await tiny.build({
          sources: {
            [entry]:
              "entry const answer = func (input: U32): U32 => return do:\n  let rows: GrowArray U32 = #[input]\n  return rows[0]\n",
          },
          signal: AbortSignal.timeout(5_000),
        });
        assert(result.success, JSON.stringify(result));
        const stats = result.stats
          .runtimeOptimization as unknown as Optimization;
        assert.equal(stats.tier, codegenTier);
        assert(stats.functions > 0);
        assert.equal(stats.workers, 1);
        assert.equal(stats.parallel_jobs, 0);
        assert.equal(stats.worker_timings, null);
      } finally {
        await tiny.dispose();
      }
    } finally {
      await Deno.remove(directory, { recursive: true });
    }
  });
}
