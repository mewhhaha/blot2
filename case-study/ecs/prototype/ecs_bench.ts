// Archived compiler-coupled prototype; not part of the current compiler.
import { createSourceCompiler } from "./source.ts";
import { createEcsRuntime } from "./ecs_runtime.ts";
import { ecsWorkload } from "./ecs_workload.ts";
import { dirname } from "node:path";

const samples = Deno.args.length ? Number(Deno.args[0]) : 7;
const reportPath = Deno.args[1];
if (
  Deno.args.length > 2 || !Number.isInteger(samples) || samples < 3 ||
  samples > 100
) {
  throw new Error(
    "Usage: compiler/ecs_bench.ts [samples: 3..100] [report.json]",
  );
}

const started = performance.now();
const compiler = await createSourceCompiler();
const frontendMs = performance.now() - started;
try {
  const workloads: readonly [string, string][] = [
    [
      "gdev-style scalar port",
      await Deno.readTextFile(
        new URL("../examples/ecs_runtime.blot", import.meta.url),
      ),
    ],
    ["16 independent movement systems", ecsWorkload(16)],
    ["64 independent movement systems", ecsWorkload(64)],
  ];
  const measurements = [];
  const evidence = [];
  console.log(`Deno ${Deno.version.deno}, ${Deno.build.os}/${Deno.build.arch}`);
  console.log(`Frontend initialization: ${frontendMs.toFixed(2)} ms`);
  console.log(
    `Each sample reparses, links/checks the prelude, infers types/effects, plans the world, evaluates consts and emits Wasm. ${samples} samples after 2 warmups per workload.`,
  );
  console.log(
    "Excludes Bend bootstrap, process/module loading, file I/O and Wasm instantiation. No incremental cache.",
  );
  for (const [name, source] of workloads) {
    console.log(`Measuring ${name}...`);
    const firstStart = performance.now();
    const artifact = compiler.compileEcs(source);
    const firstMs = performance.now() - firstStart;
    if (!WebAssembly.validate(artifact.bytes)) {
      throw new Error(`${name}: invalid Wasm`);
    }
    const instantiateStart = performance.now();
    const runtime = await createEcsRuntime(artifact);
    const instantiateMs = performance.now() - instantiateStart;
    // Exercise the emitted code outside the timed region, including all imports.
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
    for (let index = 0; index < 2; index++) compiler.compileEcs(source);
    const durations: number[] = [];
    for (let index = 0; index < samples; index++) {
      const start = performance.now();
      compiler.compileEcs(source);
      durations.push(performance.now() - start);
    }
    durations.sort((left, right) => left - right);
    const round = (duration: number) => Number(duration.toFixed(2));
    const middle = Math.floor(samples / 2);
    const median = samples % 2
      ? durations[middle]
      : (durations[middle - 1] + durations[middle]) / 2;
    const measurement = {
      workload: name,
      lines: source.trimEnd().split("\n").length,
      systems: artifact.analysis.world.systems.length,
      storage: artifact.storage.length,
      bytes: artifact.bytes.length,
      first_ms: round(firstMs),
      median_ms: round(median),
      p95_ms: round(durations[Math.ceil(samples * 0.95) - 1]),
      mean_ms: round(
        durations.reduce((sum, duration) => sum + duration, 0) / samples,
      ),
      instantiate_ms: round(instantiateMs),
    };
    measurements.push(measurement);
    const digest = new Uint8Array(
      await crypto.subtle.digest("SHA-256", artifact.bytes),
    );
    evidence.push({
      ...measurement,
      sha256: Array.from(digest, (byte) => byte.toString(16).padStart(2, "0"))
        .join(""),
      samples_ms: durations,
    });
  }
  console.table(measurements);
  if (reportPath) {
    await Deno.mkdir(dirname(reportPath), { recursive: true });
    await Deno.writeTextFile(
      reportPath,
      JSON.stringify(
        {
          version: 1,
          deno: Deno.version.deno,
          platform: Deno.build,
          samples,
          warmups: 2,
          frontend_ms: frontendMs,
          workloads: evidence,
        },
        null,
        2,
      ) + "\n",
    );
    console.log(`Wrote ${reportPath}`);
  }
} finally {
  compiler.dispose();
}
