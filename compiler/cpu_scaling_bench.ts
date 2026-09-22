import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { cpus } from "node:os";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { deserialize, serialize } from "node:v8";
import { benchmarkWorkloads } from "./benchmark_workloads.ts";
import type { Artifact } from "./host.ts";

// Linux diagnostic driver. Each sample runs in a separately pinned host and
// inherits that affinity in its native child. No instrumentation in blotc.
const decoder = new TextDecoder();
const warmups = 2;
const retainedRequests = 50;
async function digest(bytes: Uint8Array<ArrayBuffer>) {
  return Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}
async function execute(artifact: Artifact, expected: number) {
  const { instance } = await WebAssembly.instantiate(artifact.bytes);
  const entry = instance.exports.entry_0;
  ok(typeof entry === "function");
  equal(entry(0), expected);
}
function median(values: number[]) {
  const sorted = values.toSorted((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2
    ? sorted[middle]
    : (sorted[middle - 1] + sorted[middle]) / 2;
}
async function usage(pid: number) {
  const status = await Deno.readTextFile(`/proc/${pid}/status`);
  const stat = await Deno.readTextFile(`/proc/${pid}/stat`);
  const fields = stat.slice(stat.lastIndexOf(")") + 2).trim().split(/\s+/);
  return {
    cpu_ticks: Number(fields[11]) + Number(fields[12]),
    rss_kib: Number(/^VmRSS:\s+(\d+)/m.exec(status)![1]),
  };
}

if (Deno.args[0] === "--reference") {
  const [, project, name, output] = Deno.args;
  const root = pathToFileURL(resolve(project) + "/");
  const { createSourceCompiler } = await import(
    new URL("compiler/source.ts", root).href
  ) as typeof import("./source.ts");
  const workload = benchmarkWorkloads.find((workload) =>
    workload.name === name
  )!;
  const js = await createSourceCompiler({ prelude: "none" });
  try {
    const reference = js.compile(workload.source);
    const changed = js.compile(workload.changed);
    await execute(reference, workload.expected);
    await execute(changed, workload.expected + 1);
    await Deno.writeFile(output, serialize({ reference, changed }));
    console.log(JSON.stringify({ wasm_sha256: await digest(reference.bytes) }));
  } finally {
    js.dispose();
  }
} else if (Deno.args[0] === "--sample") {
  const [
    ,
    project,
    name,
    backend,
    count,
    regime,
    executablePath,
    referencePath,
  ] = Deno.args;
  const root = pathToFileURL(resolve(project) + "/");
  const frontendModule = await import(
    new URL("compiler/source_frontend.ts", root).href
  ) as typeof import("./source_frontend.ts");
  const protocol = await import(
    new URL("compiler/native_protocol.ts", root).href
  ) as typeof import("./native_protocol.ts");
  const { NativeProcess } = await import(
    new URL("compiler/native_process.ts", root).href
  ) as typeof import("./native_process.ts");
  const { createNativeIncrementalCompiler } = await import(
    new URL("compiler/native_incremental.ts", root).href
  ) as typeof import("./native_incremental.ts");
  const workload = benchmarkWorkloads.find((workload) =>
    workload.name === name
  )!;
  const threads = Number(count);
  const executable = executablePath
    ? pathToFileURL(resolve(executablePath))
    : new URL("generated/compiler/blotc", root);
  // Oracles are built in separate processes: JS JIT/GC work must not spill into
  // native samples, and all backends receive exactly the explicit warmups.
  const { reference, changed } = deserialize(
    await Deno.readFile(referencePath),
  ) as {
    reference: Artifact;
    changed: Artifact;
  };
  const frontend = (backend === "native" && regime !== "incremental"
    ? await frontendModule.createSourceFrontend({ prelude: "none", threads })
    : undefined) as
      | (Awaited<ReturnType<typeof frontendModule.createSourceFrontend>> & {
        prepareParallel?: (
          source: string,
        ) => Promise<
          ReturnType<
            Awaited<
              ReturnType<typeof frontendModule.createSourceFrontend>
            >["prepare"]
          >
        >;
      })
      | undefined;
  const rows = [];
  try {
    if (backend === "js") {
      const { createSourceCompiler } = await import(
        new URL("compiler/source.ts", root).href
      ) as typeof import("./source.ts");
      const js = await createSourceCompiler({ prelude: "none" });
      try {
        for (let sample = -warmups; sample < 1; sample++) {
          const before = await usage(Deno.pid);
          const start = performance.now();
          const artifact = js.compile(workload.source);
          const total_ms = performance.now() - start;
          const after = await usage(Deno.pid);
          equal(artifact, reference);
          rows.push({
            sample,
            total_ms,
            cpu_ticks: after.cpu_ticks - before.cpu_ticks,
            rss_kib: after.rss_kib,
          });
        }
      } finally {
        js.dispose();
      }
    } else if (regime === "incremental") {
      const session = await createNativeIncrementalCompiler({
        prelude: "none",
        threads,
        executable,
      });
      try {
        for (let sample = -warmups; sample < 1; sample++) {
          const baseStart = performance.now();
          const { stats: base_cache } = await session.compile(workload.source);
          const base_revision_ms = performance.now() - baseStart;
          const start = performance.now();
          const edited = await session.compile(workload.changed);
          const body_edit_ms = performance.now() - start;
          // Session closure identities and source offsets are declaration-local.
          equal(edited.artifact.bytes, changed.bytes);
          equal(edited.artifact.analysis.functions, changed.analysis.functions);
          equal(
            edited.artifact.analysis.remaining_steps,
            changed.analysis.remaining_steps,
          );
          const unchangedStart = performance.now();
          const unchanged = await session.compile(workload.changed);
          const unchanged_ms = performance.now() - unchangedStart;
          equal(unchanged.artifact, edited.artifact);
          rows.push({
            sample,
            base_revision_ms,
            base_cache,
            body_edit_ms,
            unchanged_ms,
            cache: edited.stats,
          });
        }
        await execute(changed, workload.expected + 1);
      } finally {
        await session.dispose();
      }
    } else {
      ok(frontend);
      const prepared = regime === "reuse"
        ? frontend.prepare(workload.source)
        : undefined;
      const payload = prepared === undefined
        ? undefined
        : protocol.encodeNativeRequest({
          operation: "compile",
          root: prepared.root,
          prelude: prepared.prelude,
          fuel: prepared.nodeCount,
          const_steps: 10000n,
        });
      const measure = async (
        process: Awaited<ReturnType<typeof NativeProcess.start>>,
        sample: number,
        lifetime: string,
        startup_ms: number,
      ) => {
        const before = await usage(process.pid);
        const hostBefore = await usage(Deno.pid);
        const start = performance.now();
        const tree = prepared ??
          await (frontend.prepareNative?.(workload.source) ??
            frontend.prepareParallel?.(workload.source) ??
            frontend.prepare(workload.source));
        const parsed = performance.now();
        const request = payload ?? ("encode" in tree
          ? tree.encode("compile", 10000n)
          : protocol.encodeNativeRequest({
            operation: "compile",
            root: tree.root,
            prelude: tree.prelude,
            fuel: tree.nodeCount,
            const_steps: 10000n,
          }));
        const encoded = performance.now();
        const bytes = await process.request(request);
        const received = performance.now();
        const result = protocol.decodeNativeResponse(bytes);
        const decoded = performance.now();
        const after = await usage(process.pid);
        const hostAfter = await usage(Deno.pid);
        ok(result.operation === "compile");
        equal(result.artifact, reference);
        rows.push({
          sample,
          pid: process.pid,
          lifetime,
          startup_ms,
          frontend_ms: parsed - start,
          encoding_ms: encoded - parsed,
          native_ms: received - encoded,
          decoding_ms: decoded - received,
          total_ms: decoded - start,
          request_bytes: request.length,
          cpu_ticks: after.cpu_ticks - before.cpu_ticks,
          rss_kib: after.rss_kib,
          host_cpu_ticks: hostAfter.cpu_ticks - hostBefore.cpu_ticks,
          host_rss_kib: hostAfter.rss_kib,
        });
      };
      const start = performance.now();
      const process = await NativeProcess.start({ executable, threads });
      const startup = performance.now() - start;
      try {
        const requests = regime === "reuse" ? retainedRequests : warmups + 1;
        for (let index = 0; index < requests; index++) {
          await measure(process, index - warmups, "retained", startup);
          if (regime === "reuse" && [10, 30, 50].includes(index + 1)) {
            const freshStart = performance.now();
            const fresh = await NativeProcess.start({ executable, threads });
            const freshStartup = performance.now() - freshStart;
            try {
              for (let warmup = 0; warmup <= warmups; warmup++) {
                await measure(
                  fresh,
                  index - warmups,
                  warmup === warmups ? "fresh" : "fresh_warmup",
                  freshStartup,
                );
              }
            } finally {
              await fresh.dispose();
            }
          }
        }
      } finally {
        await process.dispose();
      }
    }
    console.log(
      JSON.stringify({
        name,
        backend,
        threads,
        regime,
        source_sha256: await digest(new TextEncoder().encode(workload.source)),
        wasm_sha256: await digest(reference.bytes),
        rows,
      }),
    );
  } finally {
    frontend?.dispose();
  }
} else {
  const resume = Deno.args[0] === "--resume";
  const invocation = resume ? Deno.args.slice(1) : Deno.args;
  const [
    report = "build/cpu-scaling.json",
    project = ".",
    sampleCount = "9",
    workerCounts = "1,2,3,4,5,6,7,8",
    selected = benchmarkWorkloads.map((workload) => workload.name).join(","),
    regimes = "full,incremental,reuse",
    executableOverride,
  ] = invocation;
  const samples = Number(sampleCount);
  const threads = workerCounts.split(",").map(Number);
  const names = selected.split(",");
  const modes = regimes.split(",");
  ok(
    Deno.build.os === "linux",
    "CPU affinity and process accounting require Linux",
  );
  ok(
    invocation.length <= 7 && Number.isInteger(samples) && samples >= 1 &&
      samples <= 100,
  );
  ok(
    threads.length > 0 && new Set(threads).size === threads.length &&
      threads.every((n) => Number.isInteger(n) && n >= 1 && n <= 8),
  );
  ok(
    names.every((name) =>
      benchmarkWorkloads.some((workload) => workload.name === name)
    ),
  );
  ok(modes.every((mode) => ["full", "incremental", "reuse"].includes(mode)));
  const status = await Deno.readTextFile("/proc/self/status");
  const allowed = new Set<number>();
  for (
    const part of /^Cpus_allowed_list:\s+(.+)$/m.exec(status)![1].split(",")
  ) {
    const [first, last = first] = part.split("-").map(Number);
    for (let cpu = first; cpu <= last; cpu++) allowed.add(cpu);
  }
  const physical = new Map<string, number>();
  for (const cpu of allowed) {
    const base = `/sys/devices/system/cpu/cpu${cpu}/topology/`;
    const identity = `${
      (await Deno.readTextFile(base + "physical_package_id")).trim()
    }:${(await Deno.readTextFile(base + "core_id")).trim()}`;
    if (!physical.has(identity)) physical.set(identity, cpu);
  }
  const cores = [...physical.values()];
  ok(
    cores.length >= Math.max(...threads),
    "Not enough eligible physical cores; refusing to label SMT threads as cores",
  );
  const ticks = await new Deno.Command("getconf", { args: ["CLK_TCK"] })
    .output();
  ok(ticks.success);
  const variants = await Promise.all(
    project.split(",").map(async (path) => {
      const fingerprints = [];
      for (const directory of ["compiler", "generated/wasm"]) {
        for await (const entry of Deno.readDir(resolve(path, directory))) {
          if (!entry.isFile || !/\.(ts|bend|c|wasm|json)$/.test(entry.name)) {
            continue;
          }
          const relative = `${directory}/${entry.name}`;
          fingerprints.push(
            `${relative}\0${await digest(
              await Deno.readFile(resolve(path, relative)),
            )}`,
          );
        }
      }
      return {
        project: resolve(path),
        executable: executableOverride
          ? resolve(executableOverride)
          : resolve(path, "generated/compiler/blotc"),
        source_sha256: await digest(
          new TextEncoder().encode(fingerprints.sort().join("\n")),
        ),
        executable_sha256: await digest(
          await Deno.readFile(
            executableOverride ?? resolve(path, "generated/compiler/blotc"),
          ),
        ),
        javascript_sha256: await digest(
          await Deno.readFile(resolve(path, "generated/compiler/compiler.js")),
        ),
      };
    }),
  );
  const configurations = [
    ...(modes.includes("full")
      ? [{ backend: "js", threads: 1, regime: "full" }]
      : []),
    ...modes.flatMap((regime) =>
      threads.filter((n) => regime !== "reuse" || n === 1 || n === 8).map((
        threads,
      ) => ({ backend: "native", threads, regime }))
    ),
  ].flatMap((config) =>
    variants.map(({ project, executable }) => ({
      ...config,
      project,
      executable,
    }))
  );
  const previous = resume
    ? JSON.parse(await Deno.readTextFile(report))
    : undefined;
  if (previous) {
    equal(
      previous.variants,
      variants,
      "Cannot resume different compiler builds",
    );
    equal(previous.samples, samples);
    equal(previous.warmups, warmups);
    equal(previous.retained_requests, retainedRequests);
    equal(previous.physical_cores, Object.fromEntries(physical));
    equal(previous.deno, Deno.version);
    equal(previous.cpu, cpus()[0].model);
    ok(Array.isArray(previous.results));
  }
  const results = previous?.results ?? [];
  const resumedAt = previous
    ? [...(previous.resumed_at ?? []), new Date().toISOString()]
    : [];
  const expectedHashes = new Map<string, string>();
  const completed = new Set<string>();
  const configurationKey = (row: {
    sample: number;
    name: string;
    project: string;
    backend: string;
    threads: number;
    regime: string;
  }) =>
    JSON.stringify([
      row.sample,
      row.name,
      row.project,
      row.backend,
      row.threads,
      row.regime,
    ]);
  for (const result of results) {
    ok(
      Number.isInteger(result.sample) && result.sample >= 0 &&
        result.sample < samples,
    );
    ok(names.includes(result.name));
    ok(configurations.some((config) =>
      config.project === result.project &&
      config.backend === result.backend && config.threads === result.threads &&
      config.regime === result.regime
    ));
    equal(result.affinity, cores.slice(0, result.threads));
    equal(
      result.source_sha256,
      await digest(new TextEncoder().encode(
        benchmarkWorkloads.find((workload) => workload.name === result.name)!
          .source,
      )),
    );
    if (expectedHashes.has(result.name)) {
      equal(result.wasm_sha256, expectedHashes.get(result.name));
    }
    expectedHashes.set(result.name, result.wasm_sha256);
    const key = configurationKey(result);
    ok(!completed.has(key), "Duplicate measurement in resumed report");
    completed.add(key);
  }
  if (resume) console.log(`Resuming ${results.length} completed measurements`);
  await Deno.mkdir(resolve(report, ".."), { recursive: true });
  const referenceDirectory = await Deno.makeTempDir({
    dir: resolve(report, ".."),
    prefix: ".cpu-references-",
  });
  for (const name of names) {
    const references = new Map<string, string>();
    for (const [index, variant] of variants.entries()) {
      const referencePath = resolve(referenceDirectory, `${name}-${index}.bin`);
      const output = await new Deno.Command("taskset", {
        args: [
          "-c",
          String(cores[0]),
          Deno.execPath(),
          "run",
          "--allow-all",
          import.meta.filename!,
          "--reference",
          variant.project,
          name,
          referencePath,
        ],
        stdout: "piped",
        stderr: "piped",
      }).output();
      if (!output.success) throw new Error(decoder.decode(output.stderr));
      const { wasm_sha256 } = JSON.parse(decoder.decode(output.stdout));
      if (expectedHashes.has(name)) {
        equal(wasm_sha256, expectedHashes.get(name));
      }
      expectedHashes.set(name, wasm_sha256);
      references.set(variant.project, referencePath);
    }
    for (let sample = 0; sample < samples; sample++) {
      const offset = sample % configurations.length;
      const order = [
        ...configurations.slice(offset),
        ...configurations.slice(0, offset),
      ];
      if (sample % 2) order.reverse();
      for (const config of order) {
        if (
          config.regime === "reuse" && (sample > 0 || name !== "balanced_64")
        ) continue;
        const key = configurationKey({ sample, name, ...config });
        if (completed.has(key)) continue;
        const affinity = cores.slice(0, config.threads);
        const output = await new Deno.Command("taskset", {
          args: [
            "-c",
            affinity.join(","),
            Deno.execPath(),
            "run",
            "--allow-all",
            import.meta.filename!,
            "--sample",
            config.project,
            name,
            config.backend,
            String(config.threads),
            config.regime,
            config.executable,
            references.get(config.project)!,
          ],
          stdout: "piped",
          stderr: "piped",
        }).output();
        if (!output.success) throw new Error(decoder.decode(output.stderr));
        const result = JSON.parse(decoder.decode(output.stdout));
        if (expectedHashes.has(name)) {
          equal(result.wasm_sha256, expectedHashes.get(name));
        }
        expectedHashes.set(name, result.wasm_sha256);
        results.push({ sample, affinity, project: config.project, ...result });
        completed.add(key);
        console.log(
          `${config.project} ${name} ${config.backend}/${config.threads} ${config.regime} sample ${
            sample + 1
          }: ${
            median(
              result.rows.filter((row: { sample: number }) => row.sample >= 0)
                .map((row: { total_ms?: number; body_edit_ms: number }) =>
                  row.total_ms ?? row.body_edit_ms
                ),
            ).toFixed(2)
          } ms`,
        );
        await Deno.mkdir(resolve(report, ".."), { recursive: true });
        await Deno.writeTextFile(
          report,
          JSON.stringify(
            {
              measured_at: new Date().toISOString(),
              resumed_at: resumedAt,
              variants,
              samples,
              warmups,
              retained_requests: retainedRequests,
              cpu: cpus()[0].model,
              physical_cores: Object.fromEntries(physical),
              clock_ticks_per_second: Number(decoder.decode(ticks.stdout)),
              deno: Deno.version,
              timing:
                "Fresh pinned host and native process per sample; exactly two warmups. JS oracles are compiled/executed in separate processes and deserialized before timing; native hosts never load the JS compiler. Configurations and project variants interleaved. Startup, /proc CPU/RSS reads, artifact parity and Wasm execution excluded. Clean: complete artifact parity. Incremental: identical Wasm and function signatures, session-local closure metadata; unchanged calls equal the previous complete session artifact. Reuse: identical preencoded request, 50 requests, fresh controls at 10/30/50. CPU ticks are native-only for native rows. Incremental body edits alternate revisions; unchanged calls measured separately.",
              results,
            },
            null,
            2,
          ) + "\n",
        );
      }
    }
  }
}
