// A fresh process per invocation. The lighting leaf is overlaid in every mode.
import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { parseArgs } from "node:util";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { gdevProject } from "./gdev_project.ts";

const { values } = parseArgs({
  options: {
    compiler: { type: "string" },
    "gdev-root": { type: "string", default: "../gdev" },
    "frontend-workers": { type: "string", default: "8" },
    mode: { type: "string", default: "ordinary" },
    profile: { type: "boolean", default: false },
    output: { type: "string" },
  },
});
const root = resolve(values["gdev-root"]);
const project = await gdevProject(
  root,
  resolve("std"),
  "src/main.blot",
  values.compiler,
);
const workers = Number(values["frontend-workers"]);
assert(Number.isInteger(workers) && workers >= 1 && workers <= 16);
const leaf = resolve(root, "src/effects/lighting_look.blot");
const original = await Deno.readTextFile(leaf);
const preset = "const proposed = $Look { sun: true,";
assert.equal(original.split(preset).length, 2);
let source = original;
switch (values.mode) {
  case "ordinary":
    break;
  case "unused":
    source += "\nprivate const throughput_probe: Bool = (#run true)\n";
    break;
  case "reachable":
    source = source.replace(
      preset,
      "const proposed = $Look { sun: (#run true),",
    );
    break;
  default:
    throw new Error("Expected ordinary, unused or reachable");
}

const start = performance.now();
const client = await createZigProjectCompiler({
  ...project,
  frontendWorkers: workers,
  profileBackend: values.profile,
});
try {
  const result = await client.build({
    sources: { [leaf]: source },
    signal: AbortSignal.timeout(15_000),
  });
  const ms = performance.now() - start;
  const input = {
    root,
    compiler: project.executable,
    workers,
    mode: values.mode,
    profile: values.profile,
    ms,
  };
  if (result.success) {
    assert(WebAssembly.validate(result.bytes));
    const digest = new Uint8Array(
      await crypto.subtle.digest("SHA-256", result.bytes),
    );
    const sha256 = Array.from(
      digest,
      (byte) => byte.toString(16).padStart(2, "0"),
    ).join("");
    const profile = result.stats.phaseProfile as {
      checking?: Record<string, number>;
    } | undefined;
    console.log(JSON.stringify({
      ...input,
      success: true,
      sha256,
      bytes: result.bytes.length,
      fresh: result.stats.freshModules,
      jobs: profile?.checking?.parallel_worker_jobs,
      retries: profile?.checking?.parallel_retries,
    }));
    if (values.output) await Deno.writeFile(values.output, result.bytes);
  } else {
    console.log(
      JSON.stringify({
        ...input,
        success: false,
        diagnostics: result.diagnostics,
      }),
    );
    Deno.exitCode = 1;
  }
} finally {
  await client.dispose();
}
