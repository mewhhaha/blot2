// deno run -A benchmarks/tools/bench_gdev_layouts.ts CONTROL CANDIDATE [PAIRS] [WORKERS]
// Optional: --entry FILE --control-compiler FILE --candidate-compiler FILE
import assert from "node:assert/strict";
import { resolve } from "node:path";
import { parseArgs } from "node:util";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { gdevProject } from "../../scripts/integration/gdev_project.ts";

const release = "compiler-goose/build/blotc-goose";
const { values, positionals } = parseArgs({
  args: Deno.args,
  allowPositionals: true,
  options: {
    entry: { type: "string", default: "src/main.blot" },
    "control-compiler": { type: "string", default: release },
    "candidate-compiler": { type: "string", default: release },
  },
});
const [control, candidate, pairArgument = "24", workerArgument = "8"] =
  positionals;
assert(positionals.length <= 4, "Expected at most four positional arguments");
const pairs = Number(pairArgument);
const workers = Number(workerArgument);
assert(control && candidate, "Supply two Gdev project roots");
assert(Number.isInteger(pairs) && pairs > 0, "Supply a positive pair count");
assert(Number.isInteger(workers) && workers >= 1 && workers <= 16);
const layouts = [
  { name: "control", folder: control, compiler: values["control-compiler"] },
  { name: "split", folder: candidate, compiler: values["candidate-compiler"] },
];
const projects = await Promise.all(
  layouts.map(({ folder, compiler }) =>
    gdevProject(
      resolve(folder),
      resolve("std"),
      values.entry,
      resolve(compiler),
    )
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
