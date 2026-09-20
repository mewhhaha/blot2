import { deepStrictEqual as equal } from "node:assert/strict";
import { dirname } from "node:path";
import { createNativeCompiler } from "../../compiler/native.ts";
import { createNativeIncrementalCompiler } from "../../compiler/native_incremental.ts";
import { createGame, renderGame, stepGame } from "./game.ts";
import { validateFrame } from "./renderer.ts";

const samples = Number(Deno.args[0] ?? 7);
if (!Number.isSafeInteger(samples) || samples < 3 || samples > 100) {
  throw new Error("samples must be 3..100");
}
const output = Deno.args[1] ?? "build/ecs-case-bench.json";
const sourceUrl = new URL("./game.blot", import.meta.url);
const source = await Deno.readTextFile(sourceUrl);
const preludeUrl = new URL("../../std/prelude.blot", import.meta.url);
async function hash(bytes: Uint8Array<ArrayBuffer>) {
  return Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}
const sourceHash = await hash(new TextEncoder().encode(source));
const preludeHash = await hash(await Deno.readFile(preludeUrl));
function edit(before: string, after: string): string {
  if (source.split(before).length !== 2) {
    throw new Error(`Benchmark edit needs exactly one occurrence of ${before}`);
  }
  return source.replace(before, after);
}
const edits = [
  {
    name: "animation body",
    source: edit(
      "(F32.mul (F32.mul spin spin_speed) dt)",
      "(F32.mul (F32.mul spin spin_speed) (F32.mul dt 1.1))",
    ),
  },
  {
    name: "camera constant",
    source: edit("const camera_speed = 1.4", "const camera_speed = 1.8"),
  },
  {
    name: "comment only",
    source: `// Editor iteration measurement.\n${source}`,
  },
];
const percentile = (values: readonly number[], quantile: number) =>
  values.toSorted((a, b) => a - b)[Math.ceil(values.length * quantile) - 1];
const reference = await createNativeCompiler({ threads: 1 });
const results = [];
try {
  const oracle = await reference.compileApp(source);
  for (const revision of edits) {
    const expected = await reference.compileApp(revision.source);
    const started = performance.now();
    const compiler = await createNativeIncrementalCompiler({ threads: 1 });
    const startup_ms = performance.now() - started;
    try {
      const first = await compiler.compileApp(source);
      equal(first.artifact.bytes, oracle.bytes);
      let game = await createGame(first.artifact);
      const measurements = [];
      for (let iteration = 0; iteration < samples + 2; iteration++) {
        const text = iteration % 2 === 0 ? revision.source : source;
        const begin = performance.now();
        const compiled = await compiler.compileApp(text);
        const compiledAt = performance.now();
        const prepared = await game.runtime.prepareReload(compiled.artifact);
        const next = {
          ...prepared.apply(game.world),
          artifact: compiled.artifact,
        };
        game = stepGame(next, {
          dt: 1 / 60,
          viewport: { width: 1100, height: 720 },
          events: [],
          pick: () => undefined,
        });
        validateFrame(renderGame(game, { width: 1100, height: 720 }));
        const finish = performance.now();
        // Oracle comparison is outside the measured interval.
        equal(
          compiled.artifact.bytes,
          iteration % 2 === 0 ? expected.bytes : oracle.bytes,
        );
        if (iteration >= 2) {
          measurements.push({
            compile_ms: compiledAt - begin,
            reload_validate_ms: finish - compiledAt,
            total_ms: finish - begin,
            cache: compiled.stats,
          });
        }
      }
      const summary = {
        name: revision.name,
        startup_ms,
        cold_compile_ms: first.stats.total_ms,
        compile_median_ms: percentile(
          measurements.map((sample) => sample.compile_ms),
          0.5,
        ),
        total_median_ms: percentile(
          measurements.map((sample) => sample.total_ms),
          0.5,
        ),
        total_p95_ms: percentile(
          measurements.map((sample) => sample.total_ms),
          0.95,
        ),
        measurements,
      };
      results.push(summary);
      console.log(
        `${summary.name}: compile ${
          summary.compile_median_ms.toFixed(2)
        } ms, transfer + validated frame total ${
          summary.total_median_ms.toFixed(2)
        } ms (p95 ${summary.total_p95_ms.toFixed(2)} ms)`,
      );
    } finally {
      await compiler.dispose();
    }
  }
} finally {
  await reference.dispose();
}
equal(
  await hash(await Deno.readFile(sourceUrl)),
  sourceHash,
  "source changed during benchmark",
);
equal(
  await hash(await Deno.readFile(preludeUrl)),
  preludeHash,
  "prelude changed during benchmark",
);
await Deno.mkdir(dirname(output), { recursive: true });
await Deno.writeTextFile(
  output,
  JSON.stringify(
    {
      generated_at: new Date().toISOString(),
      deno: Deno.version,
      platform: Deno.build,
      threads: 1,
      samples,
      discarded_warmups: 2,
      source_sha256: sourceHash,
      prelude_sha256: preludeHash,
      compiler_sha256: await hash(
        await Deno.readFile(
          new URL("../../generated/compiler/blotc", import.meta.url),
        ),
      ),
      parser_sha256: await hash(
        await Deno.readFile(
          new URL("../../generated/wasm/parser.plan", import.meta.url),
        ),
      ),
      boundaries:
        "Includes parse/delta/native/IPC/decode, then Wasm prepare + current-world transfer + one simulated/validated frame. Excludes process startup, file-watch debounce, GPU presentation, and oracle checking. Not edit-to-photon latency.",
      results,
    },
    null,
    2,
  ) + "\n",
);
console.log(`Wrote ${output}`);
