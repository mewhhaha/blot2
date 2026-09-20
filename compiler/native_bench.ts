import { deepStrictEqual as equal } from "node:assert/strict";
import { dirname } from "node:path";
import type { EcsArtifact } from "./host.ts";
import { createNativeCompiler } from "./native.ts";
import { createSourceCompiler } from "./source.ts";
import { createEcsRuntime } from "./ecs_runtime.ts";
import { ecsWorkload } from "./ecs_workload.ts";

const samples = Number(Deno.args[0] ?? 7);
const destination = Deno.args[1] ?? "build/native-bench.json";
const threads = (Deno.args[2] ?? "1,2,4,8").split(",").map(Number);
if (
  Deno.args.length > 3 || !Number.isInteger(samples) || samples < 3 ||
  samples > 100 ||
  !threads.length || new Set(threads).size !== threads.length ||
  threads.some((count) => !Number.isInteger(count) || count < 1 || count > 64)
) {
  throw new Error(
    "Usage: compiler/native_bench.ts [samples: 3..100] [report.json] [threads: 1,2,4,8]",
  );
}

const workloads = [
  {
    systems: 7,
    source: await Deno.readTextFile(
      new URL("../examples/ecs_runtime.blot", import.meta.url),
    ),
  },
  { systems: 16, source: ecsWorkload(16) },
  { systems: 64, source: ecsWorkload(64) },
];
const evidence: Record<string, unknown>[] = [];
const reference = new Map<number, EcsArtifact>();
const warmups = 2;

async function digest(bytes: Uint8Array<ArrayBuffer>) {
  return Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}

async function measure(
  backend: string,
  startup_ms: number,
  compile: (source: string) => EcsArtifact | Promise<EcsArtifact>,
) {
  for (const workload of workloads) {
    console.log(`Measuring ${backend}: ${workload.systems} systems...`);
    const firstStart = performance.now();
    const artifact = await compile(workload.source);
    const first_ms = performance.now() - firstStart;
    if (backend === "javascript") reference.set(workload.systems, artifact);
    else {equal(
        artifact,
        reference.get(workload.systems),
        `${backend}: native output differs`,
      );}
    if (!WebAssembly.validate(artifact.bytes)) {
      throw new Error("Invalid compiler Wasm output");
    }
    const runtime = await createEcsRuntime(artifact);
    runtime.run(runtime.createWorld({
      entityCount: 1,
      components: artifact.storage.filter((binding) =>
        binding.storage.$ === "Component"
      )
        .map((binding) => ({ identity: binding.identity, values: [1] })),
      resources: artifact.storage.filter((binding) =>
        binding.storage.$ === "Resource"
      )
        .map((binding) => ({ identity: binding.identity, value: 1 })),
    }));
    for (let index = 0; index < warmups; index++) {
      await compile(workload.source);
    }
    const samples_ms: number[] = [];
    for (let index = 0; index < samples; index++) {
      const start = performance.now();
      await compile(workload.source);
      samples_ms.push(performance.now() - start);
    }
    const sorted = samples_ms.toSorted((a, b) => a - b);
    const median_ms = (sorted[Math.floor((samples - 1) / 2)] +
      sorted[Math.floor(samples / 2)]) / 2;
    evidence.push({
      backend,
      systems: workload.systems,
      startup_ms,
      first_ms,
      median_ms,
      p95_ms: sorted[Math.ceil(samples * 0.95) - 1],
      samples_ms,
      bytes: artifact.bytes.length,
      wasm_sha256: await digest(artifact.bytes),
      source_sha256: await digest(new TextEncoder().encode(workload.source)),
    });
  }
}

console.log(
  "Full source-to-Wasm compilation; no semantic cache. Native timings include encoding, pipe transport, native lowering/checking/codegen, and decoding.",
);
console.log(
  "Build time, session startup, source file I/O, artifact comparisons, and Wasm instantiation/execution are outside timed samples.",
);
const jsStart = performance.now();
const javascript = await createSourceCompiler();
try {
  await measure(
    "javascript",
    performance.now() - jsStart,
    (source) => javascript.compileEcs(source),
  );
} finally {
  javascript.dispose();
}
for (const count of threads) {
  const started = performance.now();
  const native = await createNativeCompiler({ threads: count });
  try {
    await measure(
      `native-${count}`,
      performance.now() - started,
      (source) => native.compileEcs(source),
    );
  } finally {
    await native.dispose();
  }
}
console.table(
  evidence.map((
    { backend, systems, median_ms, p95_ms, startup_ms, bytes },
  ) => ({
    backend,
    systems,
    median_ms: Number(Number(median_ms).toFixed(2)),
    p95_ms: Number(Number(p95_ms).toFixed(2)),
    startup_ms: Number(Number(startup_ms).toFixed(2)),
    bytes,
  })),
);
await Deno.mkdir(dirname(destination), { recursive: true });
await Deno.writeTextFile(
  destination,
  JSON.stringify(
    {
      version: 1,
      deno: Deno.version.deno,
      platform: Deno.build,
      measured_at: new Date().toISOString(),
      samples,
      warmups,
      native_sha256: await digest(
        await Deno.readFile(
          new URL("../generated/compiler/blotc", import.meta.url),
        ),
      ),
      javascript_sha256: await digest(
        await Deno.readFile(
          new URL("../generated/compiler/compiler.js", import.meta.url),
        ),
      ),
      workloads: evidence,
    },
    null,
    2,
  ) + "\n",
);
console.log(`Wrote ${destination}`);
