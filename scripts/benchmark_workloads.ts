/** Paired K1 kernel workloads; phase attribution is separate from timing. */
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
const warmup = Number(options.get("--runtime-warmup") ?? 2000);
const calls = Number(options.get("--runtime-calls") ?? 20000);
if (
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
const bits = new DataView(new ArrayBuffer(4));
function f32bits(value: number) {
  bits.setFloat32(0, value, true);
  return bits.getUint32(0, true);
}
const seeds = [0, 1, 7, 40, 255, 65535, 0xffffffff];
const workloads = [
  {
    name: "recurrence",
    iterations: 1024,
    encode: (value: number) => value >>> 0,
    reference(seed: number) {
      let state = seed >>> 0, total = 0;
      for (let i = 0; i < 1024; i++) {
        state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
        total = (total + state) >>> 0;
      }
      return total;
    },
  },
  {
    name: "affine_loop",
    iterations: 128,
    encode: f32bits,
    reference(seed: number) {
      let state = Math.fround(seed);
      for (let i = 0; i < 128; i++) {
        state = Math.fround(Math.fround(state * Math.fround(1.0001)) + 0.5);
      }
      return state;
    },
  },
];
const candidateHash = await sha(candidate);
const qualification = await Deno.readTextFile(
  root + "test-results/qualification.json",
)
  .then(JSON.parse).catch(() => null);
const metadata = {
  format: "K1-KERNEL-WORKLOADS-1",
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
  warmup_calls: warmup,
  timed_calls: calls,
  method:
    "Sequential counterbalanced pairs, fresh process compilation, same default Deno/V8 engine. Warmed kernels use varying deterministic seeds, exact integer/F32 references and timed checksums. Includes JS/Wasm boundary; no host array bridge. CPU placement/frequency/cache uncontrolled.",
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
    const { instance } = await WebAssembly.instantiate(bytes);
    const run = instance.exports.run as (seed: number) => number;
    const expected = seeds.map((seed) =>
      workload.encode(workload.reference(seed))
    );
    sample.expected = expected;
    seeds.forEach((seed, index) => {
      const actual = workload.encode(run(seed));
      if (actual !== expected[index]) {
        throw new Error(
          `${workload.name}/${who}/${seed}: ${actual} != ${expected[index]}`,
        );
      }
    });
    if (round >= 0) {
      const sweep = (count: number) => {
        let checksum = 0;
        for (let i = 0; i < count; i++) {
          checksum =
            (checksum + workload.encode(run(seeds[i % seeds.length]))) >>> 0;
        }
        const cycle = expected.reduce((sum, n) => (sum + n) >>> 0, 0);
        let wanted = Math.imul(cycle, Math.floor(count / seeds.length)) >>> 0;
        for (let i = 0; i < count % seeds.length; i++) {
          wanted = (wanted + expected[i]) >>> 0;
        }
        if (checksum !== wanted) throw new Error("kernel checksum changed");
        return checksum;
      };
      sweep(warmup);
      const start = performance.now();
      sample.runtime_checksum = sweep(calls);
      sample.runtime_ns_per_call = (performance.now() - start) * 1e6 / calls;
    } else {
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
for (const workload of workloads) {
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
