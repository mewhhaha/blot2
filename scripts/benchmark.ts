/** Reproducible compiler scaling corpus; timings do not substitute for gates. */
const root = new URL("../", import.meta.url).pathname;
const args = new Map(Deno.args.map((x) => {
  const at = x.indexOf("=");
  return [x.slice(0, at), x.slice(at + 1)];
}));
const rounds = Number(args.get("--rounds") ?? 5);
const scales = (args.get("--scales") ?? "8,32,128").split(",").map(Number);
const baseline = args.get("--baseline");
const candidate = args.get("--candidate") ?? root + "build/blot";
const baselineKind = args.get("--baseline-kind") ?? "legacy";
const opt = args.get("--opt") ?? "off";
const baselineOpt = args.get("--baseline-opt") ?? opt;
const runtimeCalls = Number(args.get("--runtime-calls") ?? 20000);
const warmupCalls = Number(args.get("--runtime-warmup") ?? 0);
const families = (args.get("--families") ??
  "independent,calls,chains,diamonds,generics,closures,modules,proofs,domains")
  .split(",");
if (
  !Number.isInteger(rounds) || rounds < 1 || rounds > 100 ||
  scales.some((x) => !Number.isInteger(x) || x < 1 || x > 2048) ||
  !["legacy", "k1"].includes(baselineKind) ||
  !["off", "fast", "release"].includes(opt) ||
  !["off", "fast", "release"].includes(baselineOpt) ||
  !Number.isSafeInteger(runtimeCalls) || runtimeCalls < 1 ||
  runtimeCalls > 10000000 ||
  !Number.isSafeInteger(warmupCalls) || warmupCalls < 0 ||
  warmupCalls > 10000000
) throw new Error("invalid benchmark limits");
const out = root + (args.get("--out") ?? "build/bench-k1");
await Deno.mkdir(out, { recursive: true });
const decoder = new TextDecoder();
const hash = async (bytes: Uint8Array) =>
  Array.from(
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", new Uint8Array(bytes).buffer),
    ),
  ).map(
    (x) => x.toString(16).padStart(2, "0"),
  ).join("");
async function command(exe: string, argv: string[]) {
  const r = await new Deno.Command(exe, {
    args: argv,
    cwd: root,
    stdout: "piped",
    stderr: "piped",
  }).output();
  return {
    ok: r.success,
    text: decoder.decode(r.stdout),
    error: decoder.decode(r.stderr),
  };
}
const cpu = await Deno.readTextFile("/proc/cpuinfo").catch(() => "unavailable");
const candidateHash = await hash(await Deno.readFile(candidate));
const baselineHash = baseline
  ? await hash(await Deno.readFile(baseline))
  : null;
const qualification = await Deno.readTextFile(
  root + "test-results/qualification.json",
).then(JSON.parse).catch(() => null);
const metadata = {
  timestamp: new Date().toISOString(),
  os: Deno.build,
  deno: Deno.version,
  cpu: cpu.split("\n").find((x) => x.startsWith("model name")) ?? "unavailable",
  commit: (await command("git", ["rev-parse", "HEAD"])).text.trim(),
  candidate_sha256: candidateHash,
  candidate_path: candidate,
  qualification: qualification?.status === "passed" &&
      qualification.compiler_sha256 === candidateHash
    ? {
      input_manifest_sha256: qualification.input_manifest_sha256,
      finished: qualification.finished,
      mode: qualification.compiler_mode,
    }
    : null,
  baseline_sha256: baselineHash,
  baseline_kind: baselineKind,
  candidate_opt: opt,
  baseline_opt: baselineKind === "k1" ? baselineOpt : "legacy-default",
  baseline_revision: baselineHash ===
      "fd2119f5528cb164131e1156d35ba97c434393647f1b326ae5aa154db137d923"
    ? "1e39b5d8a4268b9edf769c2813d5231abe1c963b"
    : baselineHash ===
        "7b61cff1941de683e99269dc2a3c30cc137201d9bca8f98e90a8d0bbc02366b2"
    ? "102963640f603cdcaf197c977357860b57f03c57"
    : null,
  harness_sha256: await hash(await Deno.readFile(new URL(import.meta.url))),
  goose_revision: "a108677d300cb0e8bbb842c35a353abe67a20c6c",
  policy: "K1-SEM-POLICY-1 / K1-OPT-POLICY-1 / K1-WASM32-ABI1",
  candidate_build: args.get("--build-label") ??
    "UNSPECIFIED (not release evidence)",
  threads: 1,
  cache: "fresh process; filesystem cache uncontrolled",
  instrumentation:
    "separate phase-attribution build; timing samples omit --timings",
  rounds,
  scales,
  runtime_calls_requested: runtimeCalls,
  runtime_warmup_requested: warmupCalls,
  runtime_method:
    "pre-resolved exports; checksum-checked warmup and timed loops; includes JS/Wasm boundary",
};
type Sample = {
  family: string;
  scale: number;
  compiler: string;
  round: number;
  command: string[];
  exit_code: number;
  wall_ms: number;
  cpu_ms: number;
  peak_rss_kib: number;
  checksum?: number;
  source_sha256: string;
  wasm_sha256?: string;
  phase?: unknown;
  runtime_ns_per_call?: number;
  runtime_calls?: number;
  runtime_checksum?: number;
  runtime_warmup_calls?: number;
};
const samples: Sample[] = [];
function sources(family: string, n: number) {
  let k1 = "", legacy = "";
  if (family === "modules") {
    for (let i = 0; i < n; i++) {
      k1 += `import "./module-${n}-candidate-${i}.blot" as m${i}\n`;
      legacy += `import * as m${i} from "./module-${n}-baseline-${i}.blot"\n`;
    }
  }
  if (family === "calls") {
    k1 =
      "pub let leaf: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return U32.wrapping_add(x,1)\n";
    legacy = "entry const leaf = fn (x: U32) -> U32 => @u32.add x 1\n";
  }
  if (family === "generics") {
    k1 =
      "let identity: forall [T: Type] => T -> T ! {} resources {depth: 1, frame: 1024} = fn x => return x\n";
    legacy = "const identity = fn x => x\n";
  }
  for (let i = 0; i < n; i++) {
    if (family === "chains") {
      const previous = i % 128 === 0 ? "x" : `run_${i - 1}(x)`;
      const oldPrevious = i % 128 === 0 ? "x" : `(run_${i - 1} x)`;
      k1 += `pub let run_${i}: U32 -> U32 ! {} resources {depth:${
        i % 128 + 1
      },frame:0} = fn x => return U32.wrapping_add(${previous},1)\n`;
      legacy +=
        `entry const run_${i} = fn (x: U32) -> U32 => @u32.add ${oldPrevious} 1\n`;
    } else if (family === "diamonds") {
      k1 +=
        `let leaf_${i}: U32 -> U32 ! {} resources {depth:1,frame:0} = fn x => return U32.wrapping_add(x,1)\nlet left_${i}: U32 -> U32 ! {} resources {depth:2,frame:0} = fn x => return leaf_${i}(x)\nlet right_${i}: U32 -> U32 ! {} resources {depth:2,frame:0} = fn x => return leaf_${i}(x)\npub let run_${i}: U32 -> U32 ! {} resources {depth:3,frame:0} = fn x => return U32.wrapping_add(left_${i}(x),right_${i}(x))\n`;
      legacy +=
        `const leaf_${i} = fn (x: U32) -> U32 => @u32.add x 1\nconst left_${i} = fn (x: U32) -> U32 => leaf_${i} x\nconst right_${i} = fn (x: U32) -> U32 => leaf_${i} x\nentry const run_${i} = fn (x: U32) -> U32 => @u32.add (left_${i} x) (right_${i} x)\n`;
    } else if (family === "modules") {
      k1 +=
        `pub let run_${i}: U32 -> U32 ! {} resources {depth:2,frame:0} = fn x => return m${i}.leaf(x)\n`;
      legacy += `entry const run_${i} = fn (x: U32) -> U32 => m${i}.leaf x\n`;
    } else if (family === "proofs") {
      k1 +=
        `pub let run_${i}: U32 -> U32 ! {} resources {depth:1,frame:0} = fn x => do:\n  let v0 = x\n`;
      legacy +=
        `entry const run_${i} = fn (x: U32) -> U32 => do:\n  let v0 = x\n`;
      for (let j = 0; j < 8; j++) {
        const pad = "  ".repeat(j + 1);
        k1 += `${pad}if v${j} < 4294967295:\n${pad}  let v${
          j + 1
        } = v${j} + 1\n`;
        legacy += `${pad}if @u32.lt v${j} 4294967295:\n${pad}  let v${
          j + 1
        } = @u32.add v${j} 1\n`;
      }
      k1 += `${"  ".repeat(9)}return v8\n`;
      legacy += `${"  ".repeat(9)}break v8\n`;
      for (let j = 7; j >= 0; j--) {
        const pad = "  ".repeat(j + 1);
        k1 += `${pad}else:\n${pad}  return v${j}\n`;
        legacy += `${pad}else:\n${pad}  break v${j}\n`;
      }
    } else if (family === "domains") {
      k1 += `static let values_${i} = #[${i},${
        i + 1
      }]\npub let run_${i}: U32 -> U32 ! {read static} resources {depth:1,frame:256} = fn x => do:\n  if 0 < view.length(values_${i}):\n    return U32.wrapping_add(x,values_${i}[0])\n  else:\n    return x\n`;
      legacy += `const values_${i}: Array U32 = #[${i},${
        i + 1
      }]\nentry const run_${i} = fn (x: U32) -> U32 => @u32.add x values_${i}[0]\n`;
    } else if (family === "closures") {
      k1 +=
        `pub let run_${i}: F32 -> F32 ! {} resources {depth: 2, frame: 1024} = fn bias => do:\n  let add = fn (x: F32) => return x + bias\n  return add(3.0)\n`;
      legacy +=
        `entry const run_${i} = fn (bias: F32) -> F32 => do:\n  let add = fn (x: F32) -> F32 => @f32.add x bias\n  break add 3.0\n`;
    } else {
      const body = family === "calls"
        ? "leaf(x)"
        : family === "generics"
        ? "identity@[U32](x)"
        : `U32.wrapping_add(x,${i})`;
      const old = family === "calls"
        ? "leaf x"
        : family === "generics"
        ? "identity x"
        : `@u32.add x ${i}`;
      k1 += `pub let run_${i}: U32 -> U32 ! {} resources {depth: ${
        family === "independent" ? 1 : 2
      }, frame: ${
        family === "generics" ? 2048 : 0
      }} = fn x => return ${body}\n`;
      legacy += `entry const run_${i} = fn (x: U32) -> U32 => ${old}\n`;
    }
  }
  return {
    candidate: k1,
    baseline: baselineKind === "k1"
      ? k1.replaceAll("-candidate-", "-baseline-")
      : legacy,
  };
}
async function measure(
  family: string,
  scale: number,
  compiler: string,
  round: number,
  source: string,
  exe: string,
  phase = false,
) {
  const isK1 = compiler === "candidate" || baselineKind === "k1";
  const prefix = `${out}/${family}-${scale}-${compiler}-${
    phase ? "phase" : round
  }`;
  const input = prefix + ".blot", output = prefix + ".wasm";
  await Deno.writeTextFile(input, source);
  if (family === "modules") {
    for (let i = 0; i < scale; i++) {
      await Deno.writeTextFile(
        `${out}/module-${scale}-${compiler}-${i}.blot`,
        isK1
          ? `pub let leaf: U32 -> U32 ! {} resources {depth:1,frame:0} = fn x => return U32.wrapping_add(x,${i})\n`
          : `const leaf = fn (x: U32) -> U32 => @u32.add x ${i}\n`,
      );
    }
  }
  const argv = isK1
    ? [
      "build",
      input,
      "-o",
      output,
      `--package-root=${out}`,
      `--opt=${compiler === "candidate" ? opt : baselineOpt}`,
      ...(phase ? ["--timings"] : []),
    ]
    : [
      "build",
      input,
      output,
      "--prelude",
      "none",
      "--frontend-workers",
      "1",
      "--semantic-workers",
      "1",
    ];
  const child = new Deno.Command("python3", {
    args: [root + "scripts/bench_process.py"],
    stdin: "piped",
    stdout: "piped",
    stderr: "piped",
  }).spawn();
  const writer = child.stdin.getWriter();
  await writer.write(
    new TextEncoder().encode(
      JSON.stringify({
        command: [exe, ...argv],
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
    family,
    scale,
    compiler,
    round,
    command: [exe, ...argv],
    source_sha256: await hash(new TextEncoder().encode(source)),
    ...JSON.parse(decoder.decode(process.stdout)),
  };
  if (sample.exit_code === 0) {
    const bytes = await Deno.readFile(output);
    sample.wasm_sha256 = await hash(bytes);
    const { instance } = await WebAssembly.instantiate(bytes);
    let checksum = 0;
    const enter = instance.exports["blot:ownership_enter"] as
      | (() => void)
      | undefined;
    const leave = instance.exports["blot:ownership_leave"] as
      | ((n: number) => void)
      | undefined;
    for (let i = 0; i < scale; i++) {
      enter?.();
      const value = (instance.exports[`run_${i}`] as (x: number) => number)(40);
      leave?.(0);
      const expected = family === "calls"
        ? 41
        : family === "proofs"
        ? 48
        : family === "chains"
        ? 41 + i % 128
        : family === "diamonds"
        ? 82
        : family === "closures"
        ? 43
        : family === "generics"
        ? 40
        : 40 + i;
      if (value !== expected) {
        throw new Error(
          `semantic mismatch ${family}/${scale}/${compiler}/${i}: ${value}`,
        );
      }
      checksum = (checksum + value) >>> 0;
    }
    sample.checksum = checksum;
    if (!phase) {
      const entries = Array.from(
        { length: scale },
        (_, i) => instance.exports[`run_${i}`] as (x: number) => number,
      );
      function run(iterations: number) {
        let sum = 0;
        for (let j = 0; j < iterations; j++) {
          for (const entry of entries) {
            enter?.();
            sum = (sum + entry(40)) >>> 0;
            leave?.(0);
          }
        }
        if (sum !== Math.imul(checksum, iterations) >>> 0) {
          throw new Error("runtime checksum changed");
        }
        return sum;
      }
      const warmupIterations = Math.floor(warmupCalls / scale);
      run(warmupIterations);
      sample.runtime_warmup_calls = warmupIterations * scale;
      const iterations = Math.max(1, Math.floor(runtimeCalls / scale));
      const begin = performance.now();
      const runtimeChecksum = run(iterations);
      sample.runtime_calls = iterations * scale;
      sample.runtime_ns_per_call = (performance.now() - begin) * 1e6 /
        sample.runtime_calls;
      sample.runtime_checksum = runtimeChecksum;
      if (runtimeChecksum !== Math.imul(checksum, iterations) >>> 0) {
        throw new Error("runtime checksum changed");
      }
    }
    if (phase) {
      const stderr = await Deno.readTextFile(prefix + ".stderr");
      sample.phase = stderr.split("\n").filter((x) => x.startsWith("{")).map(
        (x) => JSON.parse(x),
      );
    }
  }
  samples.push(sample);
  await Deno.writeTextFile(
    out + "/results.json",
    JSON.stringify({ metadata, samples }, null, 2),
  );
}
for (const family of families) {
  for (const scale of scales) {
    const source = sources(family, scale);
    for (let round = 0; round < rounds; round++) {
      for (
        const compiler
          of (round % 2 ? ["baseline", "candidate"] : ["candidate", "baseline"])
      ) {
        if (compiler === "baseline" && !baseline) {
          continue;
        }
        await measure(
          family,
          scale,
          compiler,
          round,
          source[compiler as keyof typeof source],
          compiler === "candidate" ? candidate : baseline!,
        );
      }
    }
    await measure(
      family,
      scale,
      "candidate",
      -1,
      source.candidate,
      candidate,
      true,
    );
    if (baseline && baselineKind === "k1") {
      await measure(
        family,
        scale,
        "baseline",
        -1,
        source.baseline,
        baseline,
        true,
      );
    }
    console.log("measured", family, scale);
  }
}
const summary: unknown[] = [];
for (const family of families) {
  for (const scale of scales) {
    for (const compiler of ["candidate", "baseline"]) {
      const group = samples.filter((x) =>
        x.family === family && x.scale === scale && x.compiler === compiler &&
        x.round >= 0
      );
      if (!group.length) {
        continue;
      }
      const times = group.filter((x) => x.exit_code === 0).map((x) => x.wall_ms)
        .sort((a, b) => a - b);
      const median = times.length ? times[Math.floor(times.length / 2)] : null;
      summary.push({
        family,
        scale,
        compiler,
        samples: group.length,
        failures: group.length - times.length,
        median_ms: median,
        min_ms: times[0] ?? null,
        max_ms: times.at(-1) ?? null,
      });
    }
  }
}
await Deno.writeTextFile(
  out + "/summary.json",
  JSON.stringify({ metadata, summary }, null, 2),
);
console.log(JSON.stringify(summary, null, 2));
