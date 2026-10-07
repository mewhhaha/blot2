// deno run --allow-read --allow-write --allow-run scripts/bench_iterators.ts \
//   COMPILER STD_ROOT OUTPUT_DIR BASELINE_COMPILER BASELINE_STD_ROOT GDEV_SNAPSHOT
// GDEV_SNAPSHOT must be an immutable copy containing src/ and packages/.
import { strict as assert } from "node:assert";
import { dirname, resolve } from "node:path";
import { instantiateGuest } from "../compiler/guest.ts";
import { createZigProjectCompiler } from "../compiler/zig_project_client.ts";
assert(
  Deno.args.length === 6,
  "Expected compiler, std, output, baseline compiler, baseline std and frozen gdev root",
);
const [
  compilerPath,
  stdPath,
  outputPath,
  baselinePath,
  baselineStdPath,
  gamePath,
] = Deno.args.map((path) => resolve(path));
const directory = outputPath;
await Deno.mkdir(directory, { recursive: true });
const hash = async (bytes: Uint8Array<ArrayBuffer>) =>
  [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map((x) =>
    x.toString(16).padStart(2, "0")
  ).join("");
const variants = [
  { name: "baseline", compiler: baselinePath, std: baselineStdPath },
  { name: "current", compiler: compilerPath, std: stdPath },
];
const report = {
  versions: Deno.version,
  variants: [] as Record<string, unknown>[],
  runtime: [] as {
    name: string;
    arg: number;
    variant: string;
    samples_ms: number[];
    memory_bytes: number;
  }[],
  cold: [] as {
    variant: string;
    run: number;
    wall_ms: number;
    process_cpu_rss: unknown;
    metrics: unknown;
    wasm_sha256: string;
  }[],
  retained: [] as {
    variant: string;
    run: number;
    name: string;
    wall_ms: number;
    stats: unknown;
    wasm_sha256: string;
  }[],
  source: {} as Record<string, unknown>,
  storage: {} as Record<string, number>,
  notes:
    "Fresh CLI processes with warm filesystem caches; retained samples include API round trip. Runtime samples alternate variants after warmup and include guest ABI copying.",
};
const save = async () =>
  await Deno.writeTextFile(
    `${directory}/report.json`,
    JSON.stringify(report, null, 2) + "\n",
  );
for (const variant of variants) {
  const sources: Record<string, string> = {};
  for await (const file of Deno.readDir(variant.std)) {
    if (file.isFile && file.name.endsWith(".blot")) {
      sources[file.name] = await hash(
        await Deno.readFile(`${variant.std}/${file.name}`),
      );
    }
  }
  report.variants.push({
    ...variant,
    sha256: await hash(await Deno.readFile(variant.compiler)),
    sources,
  });
}
async function compile(
  variant: typeof variants[number],
  source: string,
  name: string,
) {
  const input = `${directory}/${name}.blot`,
    output = `${directory}/${variant.name}-${name}.wasm`;
  await Deno.writeTextFile(input, source);
  const command = await new Deno.Command(variant.compiler, {
    args: [
      "build",
      input,
      output,
      "--std-root",
      variant.std,
      "--prelude",
      `${variant.std}/prelude.blot`,
    ],
    stdout: "piped",
    stderr: "piped",
  }).output();
  assert(
    command.success,
    new TextDecoder().decode(command.stdout) +
      new TextDecoder().decode(command.stderr),
  );
  await Deno.writeFile(
    `${directory}/${variant.name}-${name}.jsonl`,
    command.stdout,
  );
  return instantiateGuest(await Deno.readFile(output));
}
const common = `let retained = @list.generate 1000000 (fn index => index)
entry const fold = fn count => do:
  let sum = 0
  for value in retained:
    if value == count:
      break
    sum := self + value
  return sum
entry const generate = fn count => @array.generate count (fn index => index * 3 + 1)
`;
const guests: Awaited<ReturnType<typeof instantiateGuest>>[] = [];
for (const variant of variants) {
  guests.push(await compile(variant, common, "common"));
}
try {
  for (
    const [name, arg] of [["fold", 1000000], ["generate", 1000000]] as const
  ) {
    const expected = name === "fold"
      ? (arg * (arg - 1) / 2) >>> 0
      : Uint32Array.from({ length: arg }, (_, i) => i * 3 + 1);
    for (const guest of guests) {
      assert.deepEqual(guest.call(name, arg), expected);
    }
    for (let warm = 0; warm < 20; warm++) {
      for (const guest of guests) {
        guest.call(name, arg);
      }
    }
    const samples = [[], []] as number[][];
    for (let i = 0; i < 21; i++) {
      for (const v of i % 2 ? [1, 0] : [0, 1]) {
        const begin = performance.now();
        guests[v].call(name, arg);
        samples[v].push(performance.now() - begin);
      }
    }
    variants.forEach((variant, v) =>
      report.runtime.push({
        name,
        arg,
        variant: variant.name,
        samples_ms: samples[v],
        memory_bytes: guests[v].memoryBytes(),
      })
    );
  }
} finally {
  guests.forEach((guest) => guest.dispose());
}
const current = variants[1];
const protocols = await compile(
  current,
  `import * as iter from "std/iter"
import * as list from "std/list"
let retained = @list.generate 1000000 (fn index => index)
entry const cursor = fn count => iter.fold_left add 0 (iter.take count retained.iter)
entry const range = fn count => iter.fold_left add 0 (iter.range 0 count)
entry const slice = fn start => @array.from_list (list.slice start 100000 retained)
entry const concat = fn count => @array.from_list (list.concat (list.take count retained) (list.take 1000 retained))
`,
  "protocols",
);
try {
  for (
    const [name, arg] of [["cursor", 100000], ["range", 100000], [
      "slice",
      123456,
    ], ["concat", 200000]] as const
  ) {
    const expected = name === "cursor" || name === "range"
      ? (arg * (arg - 1) / 2) >>> 0
      : name === "slice"
      ? Uint32Array.from({ length: 100000 }, (_, i) => i + arg)
      : Uint32Array.from(
        { length: arg + 1000 },
        (_, i) => i < arg ? i : i - arg,
      );
    assert.deepEqual(protocols.call(name, arg), expected);
    for (let i = 0; i < 8; i++) protocols.call(name, arg);
    const samples = [];
    for (let i = 0; i < 15; i++) {
      const begin = performance.now();
      protocols.call(name, arg);
      samples.push(performance.now() - begin);
    }
    report.runtime.push({
      name,
      arg,
      variant: "current",
      samples_ms: samples,
      memory_bytes: protocols.memoryBytes(),
    });
  }
} finally {
  protocols.dispose();
}
// Isolate tree allocation from host conversion and total committed Wasm pages.
const fixture = await WebAssembly.instantiate(
  await Deno.readFile(
    resolve(dirname(compilerPath), "../list-runtime-fixture.wasm"),
  ),
);
const runtime = fixture.instance.exports;
const call = (name: string, ...args: number[]) =>
  Number((runtime[name] as CallableFunction)(...args)) >>> 0;
call("blot:allocate", 4); // Reserve the first dynamic page; empty lists do not allocate.
let heap = call("heap");
const large = call("new", 1_000_000);
report.storage.million_element_list_bytes = call("heap") - heap;
heap = call("heap");
call("slice", large, 123456, 100000);
report.storage.hundred_thousand_element_slice_bytes = call("heap") - heap;
heap = call("heap");
call("slice", large, 123456, 1);
report.storage.single_element_slice_bytes = call("heap") - heap;
const small = call("new", 1000);
heap = call("heap");
call("concat", large, small);
report.storage.concat_million_plus_thousand_bytes = call("heap") - heap;
await save();
const entry = `${gamePath}/src/main.blot`,
  dependency = `${gamePath}/src/robots.blot`,
  packages = `${gamePath}/packages`;
const manifest: Record<string, string> = {};
async function scan(path: string) {
  for await (const file of Deno.readDir(path)) {
    const child = `${path}/${file.name}`;
    if (file.isDirectory) await scan(child);
    else if (file.name.endsWith(".blot")) {
      manifest[child.slice(gamePath.length + 1)] = await hash(
        await Deno.readFile(child),
      );
    }
  }
}
await scan(`${gamePath}/src`);
await scan(packages);
const monitor = `${directory}/monitor.py`;
await Deno.writeTextFile(
  monitor,
  `import json, resource, subprocess, sys, time
start = time.perf_counter()
p = subprocess.run(sys.argv[1:])
wall = (time.perf_counter() - start) * 1000
usage = resource.getrusage(resource.RUSAGE_CHILDREN)
print(json.dumps(dict(wall_ms=wall, user_seconds=usage.ru_utime, system_seconds=usage.ru_stime, peak_rss_kib=usage.ru_maxrss)), file=sys.stderr)
sys.exit(p.returncode)
`,
);
const original = await Deno.readTextFile(dependency);
assert(original.includes("const floor_half_extent = 60.0"));
const edited = original.replace(
  "const floor_half_extent = 60.0",
  "const floor_half_extent = 61.0",
);
report.source = {
  entry,
  dependency,
  manifest,
  sha256: await hash(new TextEncoder().encode(original)),
};
for (let run = 0; run < 5; run++) {
  for (
    const variant of run % 2 ? [...variants].reverse() : variants
  ) {
    const output = `${directory}/gdev-${variant.name}-${run}.wasm`;
    const begin = performance.now();
    const result = await new Deno.Command("python3", {
      args: [
        monitor,
        variant.compiler,
        "build",
        entry,
        output,
        "--alias",
        `gdev/=${packages}`,
        "--std-root",
        variant.std,
        "--prelude",
        `${variant.std}/prelude.blot`,
      ],
      stdout: "piped",
      stderr: "piped",
    }).output();
    const wall_ms = performance.now() - begin;
    const stdout = new TextDecoder().decode(result.stdout),
      stderr = new TextDecoder().decode(result.stderr);
    assert(result.success, stdout + stderr);
    const metrics = stdout.trim().split("\n").map((line) => JSON.parse(line))
      .find((row) => row.kind === "compilation");
    const bytes = await Deno.readFile(output);
    assert(WebAssembly.validate(bytes), `Invalid ${variant.name} gdev Wasm`);
    report.cold.push({
      variant: variant.name,
      run,
      wall_ms,
      process_cpu_rss: JSON.parse(stderr.trim()),
      metrics,
      wasm_sha256: await hash(bytes),
    });
    await save();
  }
}
for (let run = 0; run < 3; run++) {
  for (
    const variant of run % 2 ? [...variants].reverse() : variants
  ) {
    const options = {
      executable: variant.compiler,
      entry,
      stdRoot: variant.std,
      prelude: `${variant.std}/prelude.blot`,
      imports: { "gdev/": packages },
    };
    const opened = performance.now();
    const compiler = await createZigProjectCompiler(options);
    try {
      for (
        const [name, sources] of [
          ["population", undefined],
          ["first_edit", { [dependency]: edited }],
          ["revert", undefined],
          ["subsequent_edit", { [dependency]: edited }],
          ["noop", { [dependency]: edited }],
        ] as const
      ) {
        const begin = name === "population" ? opened : performance.now();
        const result = await compiler.build({ sources });
        const wall_ms = performance.now() - begin;
        assert(result.success, JSON.stringify(result));
        report.retained.push({
          variant: variant.name,
          run,
          name,
          wall_ms,
          stats: result.stats,
          wasm_sha256: await hash(result.bytes),
        });
        // Compare each edit to an independently populated session.
        if (run === 0 && name === "first_edit") {
          const fresh = await createZigProjectCompiler(options);
          try {
            const check = await fresh.build({ sources });
            assert(check.success);
            assert.deepEqual(result.bytes, check.bytes);
          } finally {
            await fresh.close();
          }
        }
      }
    } finally {
      await compiler.close();
    }
    await save();
  }
}
const median = (xs: number[]) =>
  [...xs].sort((a, b) => a - b)[Math.floor(xs.length / 2)];
console.log(JSON.stringify(
  {
    runtime: report.runtime.map((r) => ({
      name: r.name,
      variant: r.variant,
      median_ms: median(r.samples_ms),
      memory_bytes: r.memory_bytes,
    })),
    cold: variants.map((v) => ({
      variant: v.name,
      median_ms: median(
        report.cold.filter((r) => r.variant === v.name).map((r) => r.wall_ms),
      ),
    })),
    retained: variants.flatMap((v) =>
      ["population", "first_edit", "subsequent_edit", "noop"].map((name) => ({
        variant: v.name,
        name,
        median_ms: median(
          report.retained.filter((r) => r.variant === v.name && r.name === name)
            .map((r) => r.wall_ms),
        ),
      }))
    ),
  },
  null,
  2,
));
