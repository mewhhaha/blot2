/** Paired, public synthetic numeric-layout qualification (Linux).
 * deno run -A --v8-flags=--no-liftoff,--no-wasm-lazy-compilation
 *   scripts/bench_numeric_aggregates.ts BASELINE CANDIDATE OUTPUT [RUNS]
 * Runtime samples call scalar Wasm exports inside the ownership boundary;
 * public guest.call and allocator probes validate results separately.
 */
import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { cpuUsage } from "node:process";
import { createZigProjectCompiler } from "../compiler/zig_project_client.ts";
import { instantiateGuest } from "../compiler/guest.ts";
import {
  numericAggregateSources,
  numericShapes,
} from "./bench/numeric_aggregates.ts";
import { observeGuestAllocations } from "./bench/guest_heap_observer.ts";

assert(
  Deno.args.length >= 3 && Deno.args.length <= 4,
  "BASELINE CANDIDATE OUTPUT [RUNS]",
);
const [baseline, candidate, output] = Deno.args.slice(0, 3).map((path) =>
  resolve(path)
);
const runs = Number(Deno.args[3] ?? 7);
assert(Number.isInteger(runs) && runs >= 3);
const command = new TextDecoder().decode(
  await Deno.readFile("/proc/self/cmdline"),
).split("\0").filter(Boolean);
const engineFlags = command.filter((arg) => arg.startsWith("--v8-flags=")).join(
  ",",
);
assert(
  engineFlags.includes("--no-liftoff") &&
    engineFlags.includes("--no-wasm-lazy-compilation"),
  "Use --v8-flags=--no-liftoff,--no-wasm-lazy-compilation to exclude background Wasm tiering from timing",
);
await Deno.mkdir(output); // A new output directory prevents mixing campaigns.
const fixture = numericAggregateSources();
const entry = `${output}/main.blot`, library = `${output}/shapes.blot`;
const sources = { [entry]: fixture.main, [library]: fixture.shapes };
for (const [path, source] of Object.entries(sources)) {
  await Deno.writeTextFile(path, source);
}
const hash = async (bytes: Uint8Array<ArrayBuffer>) =>
  [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map((
    byte,
  ) => byte.toString(16).padStart(2, "0")).join("");
async function standardLibraryPins(
  root = new URL("../std/", import.meta.url),
  prefix = "",
) {
  const rows: [string, string][] = [];
  for await (const entry of Deno.readDir(root)) {
    const path = new URL(entry.name + (entry.isDirectory ? "/" : ""), root);
    if (entry.isDirectory) {
      rows.push(...await standardLibraryPins(path, prefix + entry.name + "/"));
    } else if (entry.isFile && entry.name.endsWith(".blot")) {
      rows.push([prefix + entry.name, await hash(await Deno.readFile(path))]);
    }
  }
  return rows.sort(([left], [right]) => left.localeCompare(right));
}
const stdPins = await standardLibraryPins();
const harnessSha = await hash(await Deno.readFile(new URL(import.meta.url)));
const executables = { baseline, candidate };
const pins = Object.fromEntries(
  await Promise.all(
    Object.entries(executables).map(async (
      [name, path],
    ) =>
      [name, { path, sha256: await hash(await Deno.readFile(path)) }] as const
    ),
  ),
);
const measurements: unknown[] = [];
const report = {
  version: 1,
  started: new Date().toISOString(),
  runs,
  pins,
  standard_library: stdPins,
  harness_sha256: harnessSha,
  source_sha256: await hash(
    new TextEncoder().encode(fixture.main + fixture.shapes),
  ),
  deno: Deno.version,
  command,
  os: Deno.build,
  cpu: await Deno.readTextFile("/proc/cpuinfo"),
  load: await Deno.readTextFile("/proc/loadavg"),
  scope:
    "Compiler process CPU excludes opening. Runtime calls raw scalar Wasm exports with ownership enter/leave, using the median of three batches; public guest.call and allocation instrumentation validate separately.",
  measurements,
};
const save = () =>
  Deno.writeTextFile(
    `${output}/report.json`,
    JSON.stringify(report, null, 2) + "\n",
  );
async function usage(pid: number) {
  let cpu_ns = 0;
  for await (const thread of Deno.readDir(`/proc/${pid}/task`)) {
    try {
      cpu_ns += Number(
        (await Deno.readTextFile(`/proc/${pid}/task/${thread.name}/schedstat`))
          .split(" ")[0],
      );
    } catch (error) {
      if (!(error instanceof Deno.errors.NotFound)) throw error;
    }
  }
  const status = await Deno.readTextFile(`/proc/${pid}/status`);
  return {
    cpu_ns,
    peak_rss_kib: Number(status.match(/^VmHWM:\s+(\d+)/m)?.[1] ?? 0),
  };
}
for (const tier of ["development", "optimized"] as const) {
  for (let run = 0; run < runs; run++) {
    const order = run % 2 === 0
      ? ["baseline", "candidate"] as const
      : ["candidate", "baseline"] as const;
    for (const variant of order) {
      const options = {
        executable: executables[variant],
        entry,
        stdRoot: new URL("../std", import.meta.url),
        prelude: new URL("../std/prelude.blot", import.meta.url),
        codegenTier: tier,
        codegenWorkers: 1,
        cacheDirectory: false as const,
      };
      const compiler = await createZigProjectCompiler(options);
      try {
        async function build(phase: string, input = sources) {
          const before = await usage(compiler.pid), started = performance.now();
          const result = await compiler.build({ sources: input });
          const elapsed_ms = performance.now() - started,
            after = await usage(compiler.pid);
          assert(result.success, JSON.stringify(result));
          measurements.push({
            variant,
            tier,
            run,
            phase,
            elapsed_ms,
            cpu_ms: (after.cpu_ns - before.cpu_ns) / 1e6,
            peak_rss_kib: after.peak_rss_kib,
            wasm_bytes: result.bytes.length,
            wasm_sha256: await hash(result.bytes),
            stats: result.stats,
          });
          return result.bytes;
        }
        const bytes = await build("fresh");
        assert.deepEqual(await build("noop"), bytes);
        const changedSources = {
          ...sources,
          [library]: fixture.shapes.replaceAll("seed + 15.0", "seed + 16.0"),
        };
        const changed = await build("import_edit", changedSources);
        const control = await createZigProjectCompiler(options);
        try {
          const fresh = await control.build({ sources: changedSources });
          assert(fresh.success, JSON.stringify(fresh));
          assert.deepEqual(
            changed,
            fresh.bytes,
            "retained import edit differs from fresh",
          );
        } finally {
          await control.dispose();
        }
        assert.deepEqual(await build("revert"), bytes);
        const guest = await instantiateGuest(bytes);
        const runtimeModule = new WebAssembly.Module(bytes);
        assert.equal(WebAssembly.Module.imports(runtimeModule).length, 0);
        const runtime = new WebAssembly.Instance(runtimeModule).exports;
        const enter = runtime["blot:ownership_enter"] as
          | (() => void)
          | undefined;
        const leave = runtime["blot:ownership_leave"] as
          | (() => void)
          | undefined;
        try {
          for (let warm = 0; warm < 1000; warm++) {
            assert.equal(guest.call("direct_structural_flat", 5), 200);
          }
          const cases: {
            name: string;
            argument: number | boolean | null;
            expected: number;
          }[] = [];
          for (const [shape] of numericShapes) {
            for (const kind of ["direct", "callback"]) {
              cases.push({
                name: `${kind}_${shape}`,
                argument: 5,
                expected: 200,
              });
            }
            cases.push({
              name: `dynamic_${shape}`,
              argument: true,
              expected: 200,
            });
            for (const count of [1, 32, 128, 512]) {
              cases.push({
                name: `array_${shape}`,
                argument: count,
                expected: 8 * count * count + 112 * count,
              });
            }
            cases.push({
              name: `snapshot_${shape}`,
              argument: 32,
              expected: 16240,
            });
            cases.push({
              name: `list_${shape}`,
              argument: 128,
              expected: 8 * 128 * 128 + 112 * 128 + 16120,
            });
            cases.push({
              name: `nested_edit_${shape}`,
              argument: 5,
              expected: 276,
            });
            cases.push({
              name: `constant_${shape}`,
              argument: null,
              expected: 136,
            });
            for (const seed of [-0, 1.5, -1000, 16777216]) {
              const lanes = Array.from(
                { length: 16 },
                (_, index) => Math.fround(seed + index),
              );
              assert.deepEqual([
                ...guest.call(`stored_wire_${shape}`, seed) as Float32Array,
              ], lanes);
            }
          }
          for (const spec of run % 2 ? [...cases].reverse() : cases) {
            assert.equal(guest.call(spec.name, spec.argument), spec.expected);
            const call = runtime[spec.name] as (argument: number) => number;
            const argument = Number(spec.argument);
            const invoke = () => {
              enter?.();
              try {
                if (call(argument) !== spec.expected) {
                  throw new Error(`Wrong runtime result: ${spec.name}`);
                }
              } finally {
                leave?.();
              }
            };
            for (let warm = 0; warm < 20; warm++) invoke();
            const calibration = performance.now();
            for (let index = 0; index < 20; index++) invoke();
            const repetitions = Math.max(
              20,
              Math.min(
                50000,
                Math.ceil(
                  20 * 25 / Math.max(0.01, performance.now() - calibration),
                ),
              ),
            );
            const samples = [];
            for (let batch = 0; batch < 3; batch++) {
              const cpu = cpuUsage(), started = performance.now();
              for (let index = 0; index < repetitions; index++) invoke();
              const elapsed_ms = performance.now() - started,
                spent = cpuUsage(cpu);
              samples.push({
                elapsed_ns_per_call: elapsed_ms * 1e6 / repetitions,
                cpu_ns_per_call: (spent.user + spent.system) * 1000 /
                  repetitions,
              });
            }
            for (const name of ["blot:rc_roots", "blot:rc_leases"]) {
              assert.equal(
                (runtime[name] as WebAssembly.Global | undefined)?.value ?? 0,
                0,
              );
            }
            const traffic = run === 0
              ? observeGuestAllocations(bytes, [[
                spec.name,
                Number(spec.argument),
                spec.expected,
              ]])
              : undefined;
            measurements.push({
              variant,
              tier,
              run,
              phase: "runtime",
              ...spec,
              repetitions,
              elapsed_ns_per_call: samples.map((sample) =>
                sample.elapsed_ns_per_call
              ).sort((a, b) =>
                a - b
              )[1],
              cpu_ns_per_call: samples.map((sample) =>
                sample.cpu_ns_per_call
              ).sort((a, b) => a - b)[1],
              samples,
              validation_instance_memory_bytes: guest.memoryBytes(),
              traffic,
            });
          }
        } finally {
          guest.dispose();
        }
      } finally {
        await compiler.dispose();
        await save();
      }
      console.log(`${tier} ${run + 1}/${runs} ${variant} passed`);
    }
  }
}
for (const [variant, pin] of Object.entries(pins)) {
  assert.equal(
    await hash(await Deno.readFile(pin.path)),
    pin.sha256,
    `${variant} compiler changed`,
  );
}
assert.deepEqual(
  await standardLibraryPins(),
  stdPins,
  "standard library changed",
);
assert.equal(
  await hash(await Deno.readFile(new URL(import.meta.url))),
  harnessSha,
  "benchmark changed",
);
await save();
