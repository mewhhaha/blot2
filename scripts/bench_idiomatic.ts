// Fresh-process compilation and same-engine execution of public paired sources.
import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { cpus } from "node:os";
import { instantiateGuest, readGuestAbi } from "../compiler/guest.ts";
import { workloads } from "./bench/idiomatic_reference.ts";

const options = new Map<string, string>();
for (let i = 0; i < Deno.args.length; i++) {
  const key = Deno.args[i];
  if (key === "--verify-only") options.set(key, "true");
  else {
    assert(
      ["--compiler", "--out", "--rounds", "--samples", "--cases"].includes(key),
      key,
    );
    assert(Deno.args[i + 1], `Missing value for ${key}`);
    options.set(key, Deno.args[++i]);
  }
}
const root = resolve(new URL("..", import.meta.url).pathname);
const compiler = resolve(
  options.get("--compiler") ?? "zig-native/zig-out/bin/blotc",
);
const output = resolve(
  options.get("--out") ?? `build/bench/idiomatic-${Date.now()}`,
);
const verifyOnly = options.has("--verify-only");
const rounds = verifyOnly ? 1 : Number(options.get("--rounds") ?? 5);
const samples = Number(options.get("--samples") ?? 31);
assert(Number.isInteger(rounds) && rounds > 0);
assert(Number.isInteger(samples) && samples >= 3);
const names = options.get("--cases")?.split(",") ?? Object.keys(workloads);
assert(names.every((name) => Object.hasOwn(workloads, name)));
await Deno.mkdir(output); // Do not combine evidence from separate campaigns.
await Deno.mkdir(`${output}/logs`);
const decoder = new TextDecoder();
const hash = async (path: string) =>
  [
    ...new Uint8Array(
      await crypto.subtle.digest("SHA-256", await Deno.readFile(path)),
    ),
  ].map((b) => b.toString(16).padStart(2, "0")).join("");
const median = (xs: number[]) =>
  xs.toSorted((a, b) => a - b)[Math.floor(xs.length / 2)];
async function command(executable: string, args: string[]) {
  const result = await new Deno.Command(executable, {
    args,
    stdout: "piped",
    stderr: "piped",
  }).output();
  assert(result.success, decoder.decode(result.stderr));
  return decoder.decode(result.stdout).trim();
}
const rustc = await command("rustup", ["which", "rustc"]);
const pins: Record<string, string> = {};
async function pinTree(directory: string) {
  for await (const entry of Deno.readDir(directory)) {
    const path = `${directory}/${entry.name}`;
    if (entry.isDirectory) await pinTree(path);
    else if (entry.isFile) pins[path] = await hash(path);
  }
}
await pinTree(`${root}/benchmarks/idiomatic`);
await pinTree(`${root}/std`);
const rustSysroot = await command(rustc, ["--print", "sysroot"]);
const rustTargetLibdir = await command(rustc, [
  "--print",
  "target-libdir",
  "--target",
  "wasm32-unknown-unknown",
]);
await pinTree(rustTargetLibdir);
// The rustc launcher uses shared compiler/LLVM libraries, and Wasm linking
// invokes the bundled linker. Pin those implementation inputs as well.
for await (const entry of Deno.readDir(`${rustSysroot}/lib`)) {
  if (entry.isFile) {
    pins[`${rustSysroot}/lib/${entry.name}`] = await hash(
      `${rustSysroot}/lib/${entry.name}`,
    );
  }
}
const rustHost = (await command(rustc, ["-vV"])).split("\n").find((line) =>
  line.startsWith("host: ")
)!.slice(6);
await pinTree(`${rustSysroot}/lib/rustlib/${rustHost}/bin`);

for (
  const path of [
    compiler,
    rustc,
    `${root}/scripts/bench_idiomatic.ts`,
    `${root}/scripts/bench/compiler_process.py`,
    `${root}/scripts/bench/idiomatic_reference.ts`,
    `${root}/compiler/guest.ts`,
  ]
) pins[path] = await hash(path);
const seeds = [0, 1, 17, 65535, 0x7fffffff, 0xffffffff, 0x12345678];
type Compilation = {
  name: string;
  language: string;
  round: number;
  command: string[];
  wall_ms: number;
  cpu_ms: number;
  peak_rss_kib: number;
  wasm_bytes: number;
  wasm_sha256: string;
};
type Runtime = {
  name: string;
  language: string;
  batch: number;
  samples_ms: number[];
  median_ms: number;
  committed_wasm_bytes: number | null;
};
const report = {
  schema: 1,
  complete: false,
  started_at: new Date().toISOString(),
  completed_at: "",
  platform: Deno.build,
  versions: {
    deno: Deno.version,
    rust: await command(rustc, ["-vV"]),
    zig: await command("zig", ["version"]),
  },
  rust_sysroot: rustSysroot,
  rust_target_libdir: rustTargetLibdir,
  cpu: cpus()[0]?.model,
  logical_cpus: cpus().length,
  affinity: (await Deno.readTextFile("/proc/self/status")).split("\n").find((
    line,
  ) => line.startsWith("Cpus_allowed_list:")),
  pins,
  seeds,
  rounds,
  samples,
  verify_only: verifyOnly,
  selected_workloads: names,
  boundary:
    "Small self-contained workload pairs, not whole applications. Same Deno/V8 Wasm engine. Native Rust is not measured. Fresh compiler processes with warm filesystem caches; Rust links its prebuilt standard library, Blot checks imported source. Compile times include codegen/linking, exclude wrapper startup. Runtime includes generated input/allocation/computation/destruction, scalar Wasm calls and required Blot ownership hooks, excludes module compile/instantiate and correctness witnesses. Rust iterators may fuse intermediate collections. ASCII text uses each language's native representation. No third-party libraries or I/O.",
  compilation: [] as Compilation[],
  runtime: [] as Runtime[],
  witnesses: [] as { name: string; outputs: number[] }[],
};
const save = () =>
  Deno.writeTextFile(
    `${output}/results.json`,
    JSON.stringify(report, null, 2) + "\n",
  );
await save();
async function compile(name: string, language: "blot" | "rust", round: number) {
  const wasm = `${output}/${name}-${language}.wasm`;
  const args = language === "blot"
    ? [
      compiler,
      "build",
      `${root}/benchmarks/idiomatic/${name}.blot`,
      wasm,
      "--prelude",
      `${root}/std/prelude.blot`,
      "--std-root",
      `${root}/std`,
    ]
    : [
      rustc,
      `${root}/benchmarks/idiomatic/${name}.rs`,
      "--edition=2024",
      "--crate-type=cdylib",
      "--target=wasm32-unknown-unknown",
      "-C",
      "opt-level=3",
      "-C",
      "panic=abort",
      "-o",
      wasm,
    ];
  const prefix = `${output}/logs/${name}-${language}-${round}`;
  const process = new Deno.Command("python3", {
    args: [`${root}/scripts/bench/compiler_process.py`],
    stdin: "piped",
    stdout: "piped",
    stderr: "piped",
  }).spawn();
  const writer = process.stdin.getWriter();
  await writer.write(
    new TextEncoder().encode(
      JSON.stringify({
        command: args,
        cwd: root,
        stdout: `${prefix}.stdout`,
        stderr: `${prefix}.stderr`,
      }),
    ),
  );
  await writer.close();
  const result = await process.output();
  assert(result.success, decoder.decode(result.stderr));
  const metrics = JSON.parse(decoder.decode(result.stdout));
  assert.equal(
    metrics.exit_code,
    0,
    `${name}/${language}: ${await Deno.readTextFile(
      `${prefix}.stdout`,
    )}\n${await Deno.readTextFile(`${prefix}.stderr`)}`,
  );
  const row = {
    name,
    language,
    round,
    command: args,
    ...metrics,
    wasm_bytes: (await Deno.stat(wasm)).size,
    wasm_sha256: await hash(wasm),
  };
  const prior = report.compilation.find((r) =>
    r.name === name && r.language === language
  );
  if (prior) {
    assert.equal(
      row.wasm_sha256,
      prior.wasm_sha256,
      "Fresh builds must reproduce identical bytes",
    );
  }
  report.compilation.push(row);
  await save();
}
// Alternate both language order and workload order across fresh-process rounds.
for (let round = 0; round < rounds; round++) {
  for (const name of round % 2 ? names.toReversed() : names) {
    for (
      const language of round % 2
        ? ["rust", "blot"] as const
        : ["blot", "rust"] as const
    ) await compile(name, language, round);
    console.log("compiled", round, name);
  }
}
function rawBlot(module: WebAssembly.Module) {
  const abi = readGuestAbi(module);
  assert.equal(abi.functions.length, 1);
  assert.deepEqual(abi.functions[0], {
    name: "run",
    parameter: "U32",
    result: "U32",
  });
  assert.equal(abi.taskDescriptorCount ?? 0, 0);
  assert.equal(WebAssembly.Module.imports(module).length, 0);
  const { exports } = new WebAssembly.Instance(module);
  const run = exports.run as (seed: number) => number;
  const enter = exports["blot:ownership_enter"] as (() => void) | undefined;
  const leave = exports["blot:ownership_leave"] as
    | ((outcome: number) => void)
    | undefined;
  const reset = exports["blot:reset"] as ((mark: number) => void) | undefined;
  return {
    call(seed: number) {
      enter?.();
      reset?.(0);
      let outcome = 1;
      try {
        const value = run(seed) >>> 0;
        outcome = 0;
        return value;
      } finally {
        leave?.(outcome);
        reset?.(0);
      }
    },
    memory: () =>
      (exports["blot:memory"] as WebAssembly.Memory | undefined)?.buffer
        .byteLength ?? null,
  };
}
for (const name of names) {
  const blotBytes = await Deno.readFile(`${output}/${name}-blot.wasm`);
  const blotModule = new WebAssembly.Module(blotBytes);
  const rustModule = new WebAssembly.Module(
    await Deno.readFile(`${output}/${name}-rust.wasm`),
  );
  assert.equal(WebAssembly.Module.imports(rustModule).length, 0);
  const blot = rawBlot(blotModule);
  const rustExports = new WebAssembly.Instance(rustModule).exports;
  const rust = {
    call: (seed: number) =>
      (rustExports.run as (seed: number) => number)(seed) >>> 0,
    memory: () =>
      (rustExports.memory as WebAssembly.Memory | undefined)?.buffer
        .byteLength ?? null,
  };
  const guest = await instantiateGuest(blotBytes);
  const expected = seeds.map(workloads[name]);
  try {
    seeds.forEach((seed, i) => {
      assert.equal(
        guest.call("run", seed),
        expected[i],
        `${name}: public Blot API, seed ${seed}`,
      );
      assert.equal(
        blot.call(seed),
        expected[i],
        `${name}: raw Blot adapter, seed ${seed}`,
      );
      assert.equal(rust.call(seed), expected[i], `${name}: Rust, seed ${seed}`);
    });
  } finally {
    guest.dispose();
  }
  report.witnesses.push({ name, outputs: expected });
  const variants = [{ language: "blot", ...blot }, {
    language: "rust",
    ...rust,
  }];
  if (!verifyOnly) {
    const rows = variants.map((variant) => {
      const warmStart = performance.now();
      let calls = 0;
      do {
        variant.call(seeds[calls++ % seeds.length]);
      } while (calls < 100 || performance.now() - warmStart < 100);
      const estimate = (performance.now() - warmStart) / calls;
      const batch = Math.max(
        7,
        Math.min(7168, Math.ceil(5 / estimate / 7) * 7),
      );
      const row: Runtime = {
        name,
        language: variant.language,
        batch,
        samples_ms: [],
        median_ms: 0,
        committed_wasm_bytes: null,
      };
      report.runtime.push(row);
      return { variant, row };
    });
    for (let sample = 0; sample < samples; sample++) {
      for (const { variant, row } of sample % 2 ? rows.toReversed() : rows) {
        let checksum = 0;
        const start = performance.now();
        for (let i = 0; i < row.batch; i++) {
          checksum = (checksum + variant.call(seeds[i % seeds.length])) >>> 0;
        }
        row.samples_ms.push((performance.now() - start) / row.batch);
        const wanted = expected.reduce((sum, x) => (sum + x) >>> 0, 0);
        assert.equal(
          checksum,
          Math.imul(wanted, row.batch / seeds.length) >>> 0,
          `${name}: timed witness`,
        );
      }
    }
    for (const { variant, row } of rows) {
      row.median_ms = median(row.samples_ms);
      row.committed_wasm_bytes = variant.memory();
    }
  }
  await save();
  console.log("verified", name);
}
for (const [path, pin] of Object.entries(pins)) {
  assert.equal(await hash(path), pin, `${path} changed during the campaign`);
}
report.complete = true;
report.completed_at = new Date().toISOString();
await save();
console.log(output);
