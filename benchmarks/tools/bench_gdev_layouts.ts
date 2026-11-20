// deno run -A benchmarks/tools/bench_gdev_layouts.ts CONTROL CANDIDATE [PAIRS] [WORKERS]
import assert from "node:assert/strict";
import { resolve } from "node:path";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { gdevProject } from "../../scripts/integration/gdev_project.ts";

const [control, candidate, pairArgument = "24", workerArgument = "8"] =
  Deno.args;
const pairs = Number(pairArgument);
const workers = Number(workerArgument);
assert(control && candidate, "Supply two Gdev project roots");
assert(Number.isInteger(pairs) && pairs > 0, "Supply a positive pair count");
assert(Number.isInteger(workers) && workers >= 1 && workers <= 16);
const layouts = [
  { name: "control", folder: control },
  { name: "split", folder: candidate },
];
const compiler = resolve("compiler-goose/build/blotc-goose");
const projects = await Promise.all(
  layouts.map(({ folder }) =>
    gdevProject(resolve(folder), resolve("std"), "src/main.blot", compiler)
  ),
);
const hashes = new Map<number, string>();
for (let round = 0; round < pairs; round++) {
  const order = [0, 1];
  if (round % 2) order.reverse();
  for (const i of order) {
    const start = performance.now();
    const client = await createZigProjectCompiler({
      ...projects[i],
      frontendWorkers: workers,
    });
    try {
      const result = await client.build({ signal: AbortSignal.timeout(8000) });
      const ms = performance.now() - start;
      if (!result.success) throw Error(JSON.stringify(result.diagnostics));
      assert(WebAssembly.validate(result.bytes));
      const hash = new Uint8Array(
        await crypto.subtle.digest("SHA-256", result.bytes),
      ).toHex();
      if (hashes.has(i)) assert.equal(hash, hashes.get(i));
      hashes.set(i, hash);
      console.log(JSON.stringify({
        round,
        layout: layouts[i].name,
        ms,
        hash,
        bytes: result.bytes.length,
        modules: result.stats.freshModules,
      }));
    } finally {
      await client.dispose();
    }
  }
}
