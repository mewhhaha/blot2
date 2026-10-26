/** Paired K1 kernels; runtime samples each use a fresh engine process. */
import { seeds, workloads } from "./runtime_workloads.ts";
const root = new URL("../", import.meta.url).pathname;
const options = new Map(Deno.args.map((arg) => {
  const split = arg.indexOf("=");
  return [arg.slice(0, split), arg.slice(split + 1)];
}));
const candidate = options.get("--candidate") ?? root + "build/blot";
const baseline = options.get("--baseline") ?? candidate;
const opt = options.get("--opt") ?? "release";
const baselineOpt = options.get("--baseline-opt") ?? "off";
const rounds = Number(options.get("--rounds") ?? 5);
const warmup = Number(options.get("--runtime-warmup") ?? 20000);
const engine = options.get("--engine") ?? "default";
const selectedNames =
  (options.get("--workloads") ?? workloads.map((w) => w.name).join(",")).split(
    ",",
  );
const selectedWorkloads = selectedNames.map((name) => {
  const item = workloads.find((w) => w.name === name);
  if (!item) throw new Error(`unknown workload ${name}`);
  return item;
});
const calls = Number(options.get("--runtime-calls") ?? 20000);
if (
  !["default", "optimizing"].includes(engine) ||
  ![opt, baselineOpt].every((s) => ["off", "fast", "release"].includes(s)) ||
  !Number.isInteger(rounds) || rounds < 1 || rounds > 100 ||
  !Number.isInteger(warmup) || warmup < 0 || warmup > 1000000 ||
  !Number.isInteger(calls) || calls < 1 || calls > 1000000
) throw new Error("invalid workload benchmark options");
const out = root + (options.get("--out") ?? "build/bench-workloads");
await Deno.mkdir(out, { recursive: true });
const decoder = new TextDecoder();
const encoder = new TextEncoder();
const digest = async (bytes: Uint8Array) =>
  Array.from(
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", new Uint8Array(bytes)),
    ),
  )
    .map((b) => b.toString(16).padStart(2, "0")).join("");
const sha = async (path: string) => digest(await Deno.readFile(path));
const candidateHash = await sha(candidate);
const qualification = await Deno.readTextFile(
  root + "test-results/qualification.json",
)
  .then(JSON.parse).catch(() => null);
const metadata = {
  format: "K1-KERNEL-WORKLOADS-2",
  timestamp: new Date().toISOString(),
  os: Deno.build,
  deno: Deno.version,
  candidate,
  baseline,
  candidate_sha256: candidateHash,
  baseline_sha256: await sha(baseline),
  candidate_opt: opt,
  baseline_opt: baselineOpt,
  qualification: qualification?.status === "passed" &&
      qualification.compiler_sha256 === candidateHash
    ? qualification.input_manifest_sha256
    : null,
  harness_sha256: await sha(new URL(import.meta.url).pathname),
  rounds,
  seeds,
  engine,
  workloads: selectedNames,
  runtime_worker_sha256: await sha(
    root + "scripts/benchmark_runtime_worker.ts",
  ),
  reference_models_sha256: await sha(root + "scripts/runtime_workloads.ts"),
  warmup_calls: warmup,
  timed_calls: calls,
  method:
    "Sequential counterbalanced pairs and fresh compiler processes. Each artifact runs in a fresh Deno/V8 process; startup/instantiation/warmup/reference checks are outside runtime timing. Default and optimizing-only engine results stay separate. Kernels use varying deterministic seeds, exact integer/F32 references and timed checksums. Includes JS/Wasm boundary; no host array bridge. CPU placement/frequency/cache uncontrolled.",
};
type Sample = {
  workload: string;
  compiler: string;
  round: number;
  command: string[];
  source_sha256: string;
  exit_code: number;
  wall_ms: number;
  cpu_ms: number;
  peak_rss_kib: number;
  wasm_sha256?: string;
  expected?: number[];
  runtime_checksum?: number;
  runtime_ns_per_call?: number;
  runtime_command?: string[];
  runtime_calls?: number;
  runtime_warmup_calls?: number;
  kernel_iterations_per_call: number;
  phase?: unknown;
};
const samples: Sample[] = [];
async function measure(
  workload: typeof workloads[number],
  who: string,
  round: number,
) {
  const prefix = `${out}/${workload.name}-${who}-${
    round < 0 ? "phase" : round
  }`;
  const input = root + `benchmarks/workloads/${workload.name}.blot`;
  const command = [
    who === "candidate" ? candidate : baseline,
    "build",
    input,
    `--package-root=${root}benchmarks/workloads`,
    "-o",
    prefix + ".wasm",
    `--opt=${who === "candidate" ? opt : baselineOpt}`,
    ...(round < 0 ? ["--timings"] : []),
  ];
  const child = new Deno.Command("python3", {
    args: [root + "scripts/bench_process.py"],
    stdin: "piped",
    stdout: "piped",
    stderr: "piped",
  }).spawn();
  const writer = child.stdin.getWriter();
  await writer.write(
    encoder.encode(
      JSON.stringify({
        command,
        cwd: root,
        stdout: prefix + ".stdout",
        stderr: prefix + ".stderr",
      }),
    ),
  );
  await writer.close();
  const process = await child.output();
  if (!process.success) throw new Error(decoder.decode(process.stderr));
  const sample: Sample = {
    workload: workload.name,
    compiler: who,
    round,
    command,
    source_sha256: await sha(input),
    kernel_iterations_per_call: workload.iterations,
    ...JSON.parse(decoder.decode(process.stdout)),
  };
  samples.push(sample);
  if (sample.exit_code === 0) {
    const bytes = await Deno.readFile(prefix + ".wasm");
    sample.wasm_sha256 = await digest(bytes);
    const runtimeArgs = [
      "run",
      ...(engine === "optimizing" ? ["--v8-flags=--no-liftoff"] : []),
      "--allow-read",
      root + "scripts/benchmark_runtime_worker.ts",
      prefix + ".wasm",
      workload.name,
      String(round < 0 ? 0 : warmup),
      String(round < 0 ? 0 : calls),
    ];
    sample.runtime_command = [Deno.execPath(), ...runtimeArgs];
    const runtime = await new Deno.Command(Deno.execPath(), {
      args: runtimeArgs,
      stdout: "piped",
      stderr: "piped",
    }).output();
    await Deno.writeFile(prefix + ".runtime.stdout", runtime.stdout);
    await Deno.writeFile(prefix + ".runtime.stderr", runtime.stderr);
    if (!runtime.success) {
      throw new Error(
        `runtime worker failed: ${decoder.decode(runtime.stderr)}`,
      );
    }
    Object.assign(sample, JSON.parse(decoder.decode(runtime.stdout)));
    if (round < 0) {
      sample.phase = (await Deno.readTextFile(prefix + ".stderr")).split("\n")
        .filter((line) => line.startsWith("{")).map((line) => JSON.parse(line));
    }
  }

  await Deno.writeTextFile(
    out + "/results.json",
    JSON.stringify({ metadata, samples }, null, 2) + "\n",
  );
  if (sample.exit_code !== 0) {
    throw new Error(`failed workload retained in ${prefix}.stderr`);
  }
}
for (const workload of selectedWorkloads) {
  for (let round = 0; round < rounds; round++) {
    for (
      const who of round % 2
        ? ["baseline", "candidate"]
        : ["candidate", "baseline"]
    ) await measure(workload, who, round);
  }
  for (const who of ["candidate", "baseline"]) await measure(workload, who, -1);
  console.log("measured", workload.name);
}
