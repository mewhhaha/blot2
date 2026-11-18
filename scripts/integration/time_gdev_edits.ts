import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { parseArgs } from "node:util";
import {
  createZigProjectCompiler,
  type ZigProjectCompiler,
} from "../../host/zig_project_client.ts";
import { gdevProject } from "./gdev_project.ts";

const { values } = parseArgs({
  options: {
    compiler: { type: "string" },
    "gdev-root": { type: "string", default: "../gdev" },
    "frontend-workers": { type: "string" },
    repetitions: { type: "string", default: "3" },
  },
});
const root = resolve(values["gdev-root"]);
const options = await gdevProject(
  root,
  resolve("std"),
  "src/main.blot",
  values.compiler,
);
const repetitions = Number(values.repetitions);
assert(Number.isSafeInteger(repetitions) && repetitions > 0);
if (values["frontend-workers"]) {
  options.frontendWorkers = Number(values["frontend-workers"]);
}
const leaf = resolve(root, "src/effects/lighting_look.blot");
const source = await Deno.readTextFile(leaf);
const needle = "const proposed = $Look { sun: true,";
assert.equal(
  source.split(needle).length,
  2,
  "Expected one proposed lighting preset",
);
const edit = source.replace(needle, "const proposed = $Look { sun: false,");
const invalid = source.replace(
  needle,
  "const proposed = $Look { sun: missing_light,",
);
type Step = "open" | "edit" | "reject" | "recover" | "revert";

async function digest(bytes: Uint8Array<ArrayBuffer>) {
  return Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)),
    (v) => v.toString(16).padStart(2, "0"),
  ).join("");
}
const references = new Map<string, string>();
async function build(
  compiler: ZigProjectCompiler,
  step: Step,
  openMs: number,
  fresh: boolean,
) {
  const sources: Record<string, string> = {};
  if (step === "edit" || step === "recover") sources[leaf] = edit;
  if (step === "reject") sources[leaf] = invalid;
  const start = performance.now();
  const result = await compiler.build({
    sources,
    signal: AbortSignal.timeout(20_000),
  });
  const buildMs = performance.now() - start;
  let residentKiB: number | undefined;
  if (Deno.build.os === "linux") {
    const status = await Deno.readTextFile(`/proc/${compiler.pid}/status`);
    const rss = /^VmRSS:\s+(\d+) kB$/m.exec(status);
    if (rss) residentKiB = Number(rss[1]);
  }
  const measure = {
    step,
    fresh,
    openMs,
    buildMs,
    revision: result.revision,
    residentKiB,
  };
  let key: string = step;
  if (step === "recover") key = "edit";
  if (step === "revert") key = "open";
  let observed: string;
  if (result.success) {
    assert.notEqual(step, "reject");
    observed = await digest(result.bytes);
    console.log(
      JSON.stringify({
        ...measure,
        sha256: observed,
        wasmBytes: result.bytes.length,
        freshModules: result.stats.freshModules,
        cachedModules: result.stats.cachedModules,
        bodyElaborations: result.stats.frontend.body_elaborations,
        bodyLowerings: result.stats.frontend.body_lowerings,
      }),
    );
  } else {
    assert.equal(step, "reject", JSON.stringify(result.diagnostics));
    observed = JSON.stringify(result.diagnostics);
    console.log(
      JSON.stringify({ ...measure, diagnostics: result.diagnostics }),
    );
  }
  if (references.has(key)) assert.equal(observed, references.get(key));
  else references.set(key, observed);
  return result.revision;
}
async function session(steps: Step[], fresh: boolean) {
  const start = performance.now();
  const compiler = await createZigProjectCompiler(options);
  try {
    let openMs = performance.now() - start;
    let revision = 0;
    for (const step of steps) {
      const reported = await build(compiler, step, openMs, fresh);
      if (step !== "reject") ++revision;
      assert.equal(reported, revision);
      openMs = 0;
    }
  } finally {
    await compiler.dispose();
  }
}
for (let run = 0; run < repetitions; ++run) {
  // Alternate order to share CPU and filesystem warmup between the two paths.
  const controls = async () => {
    for (const step of ["open", "edit", "reject"] as const) {
      await session([step], true);
    }
  };
  if (run % 2 === 0) await controls();
  await session(["open", "edit", "reject", "recover", "revert"], false);
  if (run % 2 !== 0) await controls();
}
assert.notEqual(
  references.get("edit"),
  references.get("open"),
  "Lighting edit must change Wasm",
);
