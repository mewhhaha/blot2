// Deno host multi-core `#kernel` (KernelPool) & persistent `#process` (Processes) showcase.
// Run with:
//   deno run --allow-read --allow-write --allow-run --allow-env=BLOT_CLIENT_TEST_AMBIENT \
//     benchmarks/comparison/bench_multicore_kernel.ts [compiler_path] [--wasm3]

import { fileURLToPath } from "node:url";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { compileKernelModule } from "../../host/guest.ts";
import { KernelPool } from "../../host/kernels.ts";
import { Processes } from "../../host/processes.ts";

const root = fileURLToPath(new URL("../..", import.meta.url));
const posArgs = Deno.args.filter((a) => !a.startsWith("--"));
const executable = posArgs[0] ?? `${root}/compiler-goose/build/blotc-goose`;
const useWasm3 = Deno.args.includes("--wasm3");
const entry = `${root}/benchmarks/comparison/multicore_aos_bench.blot`;
const prelude = `${root}/std/prelude.blot`;
const stdRoot = `${root}/std`;

function median(xs: number[]): number {
  const s = [...xs].sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  return s.length % 2 === 0 ? (s[m - 1] + s[m]) / 2 : s[m];
}

const compiler = await createZigProjectCompiler({
  executable,
  entry,
  prelude,
  stdRoot,
  wasm3: useWasm3,
});
const built = await compiler.build();
await compiler.dispose();
if (!built.success) {
  throw new Error(
    `Compile failed: ${JSON.stringify(built.diagnostics, null, 2)}`,
  );
}

const receipt = compileKernelModule(built.bytes);
const rows = new Uint32Array(512);
for (let i = 0; i < 512; i++) rows[i] = i;

const kernelResults: Array<{
  workers: number;
  median_ms: number;
  speedup: number;
  checksum: number;
}> = [];

let baselineMs = 0;
let expectedChecksum = -1;

for (const workers of [0, 1, 2, 4, 8]) {
  const pool = await KernelPool.open(receipt, "mandelbrot_row", {
    workers,
    defaultChunkItems: 32,
    deadlineMs: workers === 0 ? undefined : 10_000,
  });
  try {
    for (let w = 0; w < 2; w++) {
      await pool.runFixed(rows);
    }
    const samples: number[] = [];
    let checksum = 0;
    for (let s = 0; s < 9; s++) {
      const t0 = performance.now();
      const out = await pool.runFixed(rows);
      samples.push(performance.now() - t0);
      const u32 = new Uint32Array(
        out.buffer,
        out.byteOffset,
        out.byteLength / 4,
      );
      let sum = 0;
      for (let i = 0; i < u32.length; i++) sum = (sum + u32[i]) >>> 0;
      checksum = sum;
    }
    const med = median(samples);
    if (workers === 0) {
      baselineMs = med;
      expectedChecksum = checksum;
    } else if (checksum !== expectedChecksum) {
      throw new Error(
        `Checksum mismatch at workers=${workers}: ${checksum} != ${expectedChecksum}`,
      );
    }
    kernelResults.push({
      workers,
      median_ms: Number(med.toFixed(3)),
      speedup: Number((baselineMs / med).toFixed(2)),
      checksum,
    });
  } finally {
    await pool.close();
  }
}

// Persistent `#process` step throughput via Deno `Processes` host
const host = new Processes(
  built.bytes,
  [{
    name: "particle_sim",
    initWork: 1,
    stepWork: 1,
    mailbox: 1,
    mailboxBytes: 64,
    maxReplyBytes: 4,
  }],
  { slots: 1 },
);
let nopStepUs = 0;
let physStepUs = 0;
try {
  const h = host.admit("particle_sim", 4096);
  if (h === null) throw new Error("Failed to admit particle_sim process");
  await host.advance(1);

  for (let i = 0; i < 100; i++) {
    host.send(h, 0);
    await host.advance(1);
    host.poll(h);
  }
  const nopSamples: number[] = [];
  for (let s = 0; s < 7; s++) {
    const t0 = performance.now();
    for (let i = 0; i < 1000; i++) {
      host.send(h, 0);
      await host.advance(1);
      host.poll(h);
    }
    nopSamples.push(((performance.now() - t0) * 1000) / 1000);
  }
  nopStepUs = Number(median(nopSamples).toFixed(2));

  for (let i = 0; i < 20; i++) {
    host.send(h, 1);
    await host.advance(1);
    host.poll(h);
  }
  const physSamples: number[] = [];
  for (let s = 0; s < 7; s++) {
    const t0 = performance.now();
    for (let i = 0; i < 200; i++) {
      host.send(h, 1);
      await host.advance(1);
      host.poll(h);
    }
    physSamples.push(((performance.now() - t0) * 1000) / 200);
  }
  physStepUs = Number(median(physSamples).toFixed(2));
} finally {
  await host.restore();
}

console.log(
  JSON.stringify(
    {
      wasm_bytes: built.bytes.length,
      wasm3: useWasm3,
      deno_kernel_pool_mandelbrot_512x512: kernelResults,
      deno_entry_process_particle_sim_4096: {
        noop_commit_us_per_step: nopStepUs,
        aos_vec4_physics_us_per_step: physStepUs,
      },
    },
    null,
    2,
  ),
);
