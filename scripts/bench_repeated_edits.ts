/** Repeated literal edits in one retained session, with independent fresh controls. */
import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createZigProjectCompiler } from "../compiler/zig_project_client.ts";
import { editedSources, gdevWorkloads, sessionOptions } from "./bench/gdev.ts";

const [
  baseArg,
  candidateArg,
  snapshotArg,
  outputArg,
  roundsArg = "7",
  editsArg = "4",
  mode = "plain",
] = Deno.args;
assert(baseArg && candidateArg && snapshotArg && outputArg);
assert(["plain", "profile", "both"].includes(mode));
const root = resolve(fileURLToPath(new URL("..", import.meta.url)));
const executables = {
  baseline: resolve(baseArg),
  candidate: resolve(candidateArg),
};
const snapshot = resolve(snapshotArg), output = resolve(outputArg);
const rounds = Number(roundsArg), edits = Number(editsArg);
assert(Number.isInteger(rounds) && rounds >= 7);
assert(Number.isInteger(edits) && edits >= 3);
await Deno.mkdir(output);
const sha = async (bytes: Uint8Array<ArrayBuffer>) =>
  Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)),
    (b) => b.toString(16).padStart(2, "0"),
  ).join("");
const manifestPath = `${root}/scripts/bench/gdev-manifest.json`;
const manifest = JSON.parse(await Deno.readTextFile(manifestPath)) as Record<
  string,
  string
>;
async function verifyInputs() {
  for (const [path, expected] of Object.entries(manifest)) {
    assert.equal(
      await sha(await Deno.readFile(`${snapshot}/${path}`)),
      expected,
      path,
    );
  }
}
await verifyInputs();
const pins: Record<string, string> = {};
for (
  const path of [
    manifestPath,
    ...Object.values(executables),
    new URL(import.meta.url).pathname,
  ]
) {
  pins[path] = await sha(await Deno.readFile(path));
}
async function pinLibrary(directory: string): Promise<void> {
  for await (const file of Deno.readDir(directory)) {
    const path = `${directory}/${file.name}`;
    if (file.isDirectory) await pinLibrary(path);
    else if (file.isFile && file.name.endsWith(".blot")) {
      pins[path] = await sha(await Deno.readFile(path));
    }
  }
}
await pinLibrary(`${root}/std`);
const [workload] = await gdevWorkloads(root, snapshot);
const scenario = workload.scenarios.find((s) => s.name === "literal_constant");
assert(scenario);
const one = await editedSources(workload, scenario);
const two = Object.fromEntries(
  Object.entries(one).map(([path, source]) => {
    assert(source.includes("const floor_half_extent = 61.0"));
    return [
      path,
      source.replace(
        "const floor_half_extent = 61.0",
        "const floor_half_extent = 62.0",
      ),
    ];
  }),
);
const variants = [one, two];
async function usage(pid: number) {
  let cpu_ns = 0;
  for await (const task of Deno.readDir(`/proc/${pid}/task`)) {
    try {
      cpu_ns += Number(
        (await Deno.readTextFile(`/proc/${pid}/task/${task.name}/schedstat`))
          .split(" ")[0],
      );
    } catch (e) {
      if (!(e instanceof Deno.errors.NotFound)) throw e;
    }
  }
  const status = await Deno.readTextFile(`/proc/${pid}/status`);
  const stat = await Deno.readTextFile(`/proc/${pid}/stat`);
  const fields = stat.slice(stat.lastIndexOf(") ") + 2).trim().split(/\s+/);
  return {
    cpu_ns,
    ticks: Number(fields[11]) + Number(fields[12]),
    rss_kib: Number(status.match(/^VmRSS:\s+(\d+)/m)?.[1] ?? 0),
    peak_rss_kib: Number(status.match(/^VmHWM:\s+(\d+)/m)?.[1] ?? 0),
  };
}
const records: unknown[] = [];
const freshWitnesses = new Map<string, string[]>();
const metadata = {
  pins,
  snapshot,
  rounds,
  edits,
  mode,
  started: new Date().toISOString(),
  deno: Deno.version,
  command: Deno.args,
  load_start: await Deno.readTextFile("/proc/loadavg"),
  cpus: await Deno.readTextFile("/proc/cpuinfo"),
  accounting:
    "CPU is child live-thread schedstat, cross-checked against process user+system ticks. Opening excluded. Edits alternate 61 and 62 in one session; statistics exclude edit 1. Independent fresh controls are compiled once per pinned executable, then their hashes validate every retained edit. Profile clocks are wall clocks, not CPU or Quantity C.",
  cache_directory: false,
  codegen_workers: 1,
  semantic_workers: 1,
};
await Deno.writeTextFile(
  `${output}/metadata.json`,
  JSON.stringify(metadata, null, 2) + "\n",
);
async function record(value: unknown) {
  records.push(value);
  await Deno.writeTextFile(
    `${output}/samples.jsonl`,
    JSON.stringify(value) + "\n",
    { append: true },
  );
}
for (let round = 0; round < rounds; round++) {
  const order = round % 2
    ? ["candidate", "baseline"] as const
    : ["baseline", "candidate"] as const;
  const modes = mode === "both"
    ? (round % 2 ? ["profile", "plain"] : ["plain", "profile"])
    : [mode];
  const schedule = order.flatMap((variant) =>
    modes.map((measurementMode) => ({ variant, measurementMode }))
  );
  for (const { variant, measurementMode } of schedule) {
    const options = {
      ...sessionOptions(executables[variant], workload),
      cacheDirectory: false as const,
      codegenWorkers: 1,
      semanticWorkers: 1,
      profileBackend: measurementMode === "profile",
    };
    const compiler = await createZigProjectCompiler(options);
    try {
      const build = async (
        phase: string,
        input: Record<string, string>,
        edit?: number,
      ) => {
        const before = await usage(compiler.pid), started = performance.now();
        const result = await compiler.build({
          sources: { ...workload.overlay, ...input },
        });
        const elapsed_ms = performance.now() - started,
          after = await usage(compiler.pid);
        assert(result.success, JSON.stringify(result));
        const digest = await sha(result.bytes);
        await record({
          round,
          variant,
          mode: measurementMode,
          phase,
          edit,
          cpu_ms: (after.cpu_ns - before.cpu_ns) / 1e6,
          tick_cpu_ms: (after.ticks - before.ticks) * 10,
          elapsed_ms,
          rss_kib: after.rss_kib,
          peak_rss_kib: after.peak_rss_kib,
          wasm_bytes: result.bytes.length,
          wasm_sha256: digest,
          stats: result.stats,
        });
        return digest;
      };
      const original = await build("population", {});
      assert.equal(await build("noop", {}), original);
      let fresh = freshWitnesses.get(variant);
      if (!fresh) {
        fresh = [];
        for (let i = 0; i < variants.length; i++) {
          const control = await createZigProjectCompiler(options);
          try {
            const result = await control.build({
              sources: { ...workload.overlay, ...variants[i] },
            });
            assert(result.success, JSON.stringify(result));
            fresh.push(await sha(result.bytes));
          } finally {
            await control.dispose();
          }
        }
        freshWitnesses.set(variant, fresh);
        await record({ variant, phase: "fresh_control_hashes", hashes: fresh });
      }
      for (let edit = 1; edit <= edits; edit++) {
        const index = (edit - 1) % variants.length;
        assert.equal(
          await build("edit", variants[index], edit),
          fresh[index],
          "fresh/retained mismatch",
        );
      }
      assert.equal(await build("revert", {}), original, "revert mismatch");
      console.log(
        `${measurementMode} round ${
          round + 1
        }/${rounds}: ${variant} verified ${edits} repeated edits`,
      );
    } finally {
      await compiler.dispose();
    }
  }
}
await verifyInputs();
for (const [path, expected] of Object.entries(pins)) {
  assert.equal(await sha(await Deno.readFile(path)), expected, path);
}
await Deno.writeTextFile(
  `${output}/report.json`,
  JSON.stringify(
    { ...metadata, finished: new Date().toISOString(), records },
    null,
    2,
  ) + "\n",
);
