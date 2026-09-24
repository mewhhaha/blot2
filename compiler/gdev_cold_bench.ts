// Alternating full gdev compiles, with a fresh native process and project per sample.
// deno run --allow-all compiler/gdev_cold_bench.ts BASELINE CANDIDATE [rounds=5] [threads=1] [candidate-threads=threads]
import { resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { createNativeCompiler } from "./native.ts";
import {
  matchingNativeChild,
  nativeCpuMilliseconds,
  nativeCpuSample,
  ownedNativeChildren,
} from "./native_cpu_bench.ts";
import { loadSourceProject } from "./source_project.ts";

const rounds = Number(Deno.args[2] ?? "5");
const threads = [
  Number(Deno.args[3] ?? "1"),
  Number(Deno.args[4] ?? Deno.args[3] ?? "1"),
];
if (
  Deno.args.length < 2 || Deno.args.length > 5 ||
  !Number.isInteger(rounds) || rounds < 1 || rounds > 20 ||
  threads.some((count) => !Number.isInteger(count) || count < 1 || count > 8)
) {
  throw new Error(
    "Usage: gdev_cold_bench.ts BASELINE CANDIDATE [rounds:1..20] [threads:1..8] [candidate-threads:1..8]",
  );
}
const executables = Deno.args.slice(0, 2).map((path) =>
  pathToFileURL(resolve(path))
);
const entry = fileURLToPath(
  new URL("../../gdev/src/main.blot", import.meta.url),
);
const imports = { "std/": new URL("../std/", import.meta.url) };
let expectedHash: string | undefined;

for (let round = 0; round < rounds; round++) {
  for (const side of round % 2 ? [1, 0] : [0, 1]) {
    const children = await ownedNativeChildren();
    const executable = executables[side];
    const started = performance.now();
    const compiler = await createNativeCompiler({
      executable,
      threads: threads[side],
    });
    const initialized = performance.now();
    try {
      const pid = await matchingNativeChild(executable, children);
      const loadStarted = performance.now();
      const project = await loadSourceProject(entry, { imports });
      const loaded = performance.now();
      const cpuBefore = await nativeCpuSample(pid);
      const compileStarted = performance.now();
      const artifact = await compiler.compile(project, {
        const_steps: 100_000n,
      });
      const compiled = performance.now();
      const cpuAfter = await nativeCpuSample(pid);
      if (!WebAssembly.validate(artifact.bytes)) {
        throw new Error("Invalid Wasm");
      }
      const digest = new Uint8Array(
        await crypto.subtle.digest("SHA-256", artifact.bytes.slice().buffer),
      );
      const hash = Array.from(
        digest,
        (byte) => byte.toString(16).padStart(2, "0"),
      ).join("");
      if (expectedHash !== undefined && hash !== expectedHash) {
        throw new Error(
          `Artifact changed between samples: ${expectedHash} != ${hash}`,
        );
      }
      expectedHash = hash;
      const status = pid === undefined
        ? undefined
        : await Deno.readTextFile(`/proc/${pid}/status`);
      const peakRss = status && /^VmHWM:\s+(\d+) kB$/m.exec(status)?.[1];
      console.log(JSON.stringify({
        round,
        side,
        threads: threads[side],
        executable: executable.href,
        startup_ms: initialized - started,
        load_ms: loaded - loadStarted,
        compile_ms: compiled - compileStarted,
        cpu_ms: nativeCpuMilliseconds(cpuBefore, cpuAfter),
        peak_rss_kib: peakRss ? Number(peakRss) : null,
        bytes: artifact.bytes.length,
        hash,
      }));
    } finally {
      await compiler.dispose();
    }
  }
}
