// Long retained-session qualification with distinct edits and sampled fresh
// controls. Linux /proc observations describe this process, not allocator-live
// bytes. This is a memory experiment, not an isolated latency benchmark.
import { parseArgs } from "node:util";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { fileDigest } from "../compiler_gate_state.ts";
import { editedSources, gdevWorkloads, sessionOptions } from "./gdev.ts";
import { verifySnapshotFiles } from "./snapshot.ts";

const { values } = parseArgs({
  options: {
    baseline: { type: "string" },
    candidate: { type: "string" },
    snapshot: { type: "string" },
    manifest: { type: "string" },
    out: { type: "string" },
    edits: { type: "string", default: "200" },
    "control-every": { type: "string", default: "20" },
    profile: { type: "boolean", default: false },
  },
});
for (
  const name of [
    "baseline",
    "candidate",
    "snapshot",
    "manifest",
    "out",
  ] as const
) {
  if (!values[name]) throw new Error(`--${name} is required`);
}
const edits = Number(values.edits);
const interval = Number(values["control-every"]);
if (
  !Number.isInteger(edits) || edits < 1 || edits > 1000 ||
  !Number.isInteger(interval) || interval < 1 || interval > edits
) {
  throw new Error("Require 1 <= control-every <= edits <= 1000");
}
const root = fileURLToPath(new URL("../../", import.meta.url));
const out = resolve(values.out!);
try {
  await Deno.stat(out);
  throw new Error(
    "Choose a new output directory; previous evidence is preserved",
  );
} catch (error) {
  if (!(error instanceof Deno.errors.NotFound)) throw error;
}
await Deno.mkdir(out, { recursive: true });
const [workload] = await gdevWorkloads(root, resolve(values.snapshot!));
const manifest = JSON.parse(await Deno.readTextFile(values.manifest!));
await verifySnapshotFiles(workload.root, manifest);
const scenario = workload.scenarios.find((s) => s.name === "literal_in_body")!;
const original = scenario.replacements[0];
const editSources = (revision: number): Promise<Record<string, string>> =>
  revision === 0 ? Promise.resolve({}) : editedSources(workload, {
    ...scenario,
    replacements: [{
      ...original,
      replace: original.replace.replace("0.1876", `0.${1875 + revision}`),
    }],
  });
const open = (binary: string) =>
  createZigProjectCompiler({
    ...sessionOptions(resolve(binary), workload),
    codegenWorkers: 4,
    cacheDirectory: false,
    profileBackend: values.profile,
  });
const digest = async (bytes: Uint8Array<ArrayBuffer>) =>
  Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)),
    (v) => v.toString(16).padStart(2, "0"),
  ).join("");
const controls = new Map<number, string>();
const controlRevisions = new Set([0, 1, edits]);
for (let revision = interval; revision <= edits; revision += interval) {
  controlRevisions.add(revision);
}
const pins = {
  baseline: await fileDigest(resolve(values.baseline!)),
  candidate: await fileDigest(resolve(values.candidate!)),
  manifest: await fileDigest(resolve(values.manifest!)),
  edits,
  control_every: interval,
  profile_backend: values.profile,
  control_revisions: [...controlRevisions].sort((a, b) => a - b),
};
await Deno.writeTextFile(
  `${out}/pins.json`,
  JSON.stringify(pins, null, 2) + "\n",
);
for (const revision of pins.control_revisions) {
  const compiler = await open(values.baseline!);
  try {
    const result = await compiler.build({
      sources: await editSources(revision),
    });
    if (!result.success) throw new Error(JSON.stringify(result.diagnostics));
    controls.set(revision, await digest(result.bytes));
    console.log(`fresh control ${revision}/${edits}`);
  } finally {
    await compiler.dispose();
  }
}
await Deno.writeTextFile(
  `${out}/fresh-controls.json`,
  JSON.stringify([...controls], null, 2) + "\n",
);
const compiler = await open(values.candidate!);
async function memory() {
  const status = await Deno.readTextFile(`/proc/${compiler.pid}/status`);
  const stat = await Deno.readTextFile(`/proc/${compiler.pid}/stat`);
  const fields = stat.slice(stat.lastIndexOf(") ") + 2).trim().split(/\s+/);
  const kib = (name: string) =>
    Number(status.match(new RegExp(`^${name}:\\s+(\\d+)`, "m"))?.[1] ?? 0);
  return {
    virtual_kib: kib("VmSize"),
    data_kib: kib("VmData"),
    rss_kib: kib("VmRSS"),
    peak_rss_kib: kib("VmHWM"),
    swap_kib: kib("VmSwap"),
    threads: kib("Threads"),
    minor_faults: Number(fields[7]),
    major_faults: Number(fields[9]),
    user_ticks: Number(fields[11]),
    system_ticks: Number(fields[12]),
  };
}
await Deno.writeTextFile(`${out}/samples.jsonl`, "");
let builds = 0;
async function build(revision: number, kind: string, expected?: string) {
  const before = await memory();
  const start = performance.now();
  const result = await compiler.build({ sources: await editSources(revision) });
  const wall_ms = performance.now() - start;
  const after = await memory();
  if (!result.success) throw new Error(JSON.stringify(result.diagnostics));
  const hash = await digest(result.bytes);
  const control = expected ?? controls.get(revision);
  if (control !== undefined && hash !== control) {
    throw new Error(`Output mismatch ${kind} ${revision}`);
  }
  await Deno.writeTextFile(
    `${out}/samples.jsonl`,
    JSON.stringify({
      build: builds++,
      revision,
      kind,
      wall_ms,
      wasm_sha256: hash,
      sampled_fresh_control: controls.has(revision),
      before,
      after,
      stats: result.stats,
    }) + "\n",
    { append: true },
  );
  console.log(
    JSON.stringify({ revision, kind, rss_mib: after.rss_kib / 1024, wall_ms }),
  );
  return hash;
}
try {
  await build(0, "population");
  for (let revision = 1; revision <= edits; revision++) {
    const hash = await build(revision, "unseen_literal");
    if (revision % interval === 0) {
      await build(revision, "unchanged", hash);
      const sources = await editSources(revision);
      const path = Object.keys(sources)[0];
      const bad = await compiler.build({
        sources: {
          ...sources,
          [path]: sources[path] +
            "\nentry const memory_probe_error = no_such_memory_probe_binding\n",
        },
      });
      if (bad.success) throw new Error("Invalid source unexpectedly compiled");
      await Deno.writeTextFile(
        `${out}/samples.jsonl`,
        JSON.stringify({
          build: builds++,
          revision,
          kind: "expected_error",
          diagnostics: bad.diagnostics,
          after: await memory(),
        }) + "\n",
        { append: true },
      );
      await build(revision, "recovery", hash);
    }
  }
  await build(0, "restored", controls.get(0));
  await new Promise((resolve_) => setTimeout(resolve_, 1000));
  const idle = await memory();
  await verifySnapshotFiles(workload.root, manifest);
  if (
    await fileDigest(resolve(values.candidate!)) !== pins.candidate ||
    await fileDigest(resolve(values.baseline!)) !== pins.baseline
  ) throw new Error("Compiler changed during measurement");
  await Deno.writeTextFile(
    `${out}/complete.json`,
    JSON.stringify(
      {
        success: true,
        builds,
        distinct_edits: edits,
        sampled_fresh_controls: controls.size,
        unsampled_edits_have_no_fresh_control: true,
        idle,
      },
      null,
      2,
    ) + "\n",
  );
} finally {
  await compiler.dispose();
}
