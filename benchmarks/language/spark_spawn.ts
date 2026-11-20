// deno run -A benchmarks/language/spark_spawn.ts [gdev checkout] [blotc executable]
import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { cpus } from "node:os";
import { instantiateGuest } from "../../host/guest.ts";
import { SparkCopyBudget, SparkPool } from "../../host/sparks.ts";
import { ProcessHost } from "../../host/processes.ts";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { gdevProject } from "../../scripts/integration/gdev_project.ts";
import { selectFour } from "./route_result.js";

const root = resolve(Deno.args[0] ?? "../gdev");
const executable = resolve(Deno.args[1] ?? "compiler-goose/build/blotc-goose");
const samples = 21;
const sha = async (bytes: Uint8Array<ArrayBuffer>) =>
  new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)).toHex();
async function build(stem: string) {
  const path = "performance/modernize/" + stem + ".blot";
  const project = await gdevProject(root, resolve("std"), path, executable);
  const src = await Deno.readFile(
    new URL("./" + stem + ".blot", import.meta.url),
  );
  const client = await createZigProjectCompiler({
    ...project,
    frontendWorkers: 8,
  });
  try {
    const r = await client.build({
      sources: { [project.entry]: new TextDecoder().decode(src) },
      signal: AbortSignal.timeout(15000),
    });
    if (!r.success) throw Error(JSON.stringify(r.diagnostics));
    if (stem === "spark_routes") {
      const output = Deno.env.get("BLOT_ROUTE_WASM");
      if (output) await Deno.writeFile(output, r.bytes);
    }
    return {
      module: await WebAssembly.compile(r.bytes),
      source: await sha(src),
      wasm: await sha(r.bytes),
      bytes: r.bytes.length,
    };
  } finally {
    await client.dispose();
  }
}

function summary(v: number[]) {
  const s = v.toSorted((a, b) => a - b);
  const q = (p: number) => s[Math.ceil(p * s.length) - 1];
  return { median_ms: q(0.5), p95_ms: q(0.95), p99_ms: q(0.99), samples_ms: v };
}
type Output = Uint32Array | Float32Array;
function bits(a: Output) {
  return new Uint32Array(a.buffer, a.byteOffset, a.length);
}
async function compare(
  fns: Record<string, () => Output | Promise<Output>>,
  expected: Output,
) {
  const names = Object.keys(fns);
  const times: Record<string, number[]> = Object.fromEntries(
    names.map((n) => [n, []]),
  );
  for (let i = -4; i < samples; i++) {
    for (let j = 0; j < names.length; j++) {
      const name = names[(j + i + 4) % names.length];
      const t = performance.now();
      const v = await fns[name]();
      const ms = performance.now() - t;
      assert.deepEqual(bits(v), bits(expected), name);
      if (i >= 0) times[name].push(ms);
    }
  }
  return Object.fromEntries(names.map((n) => [n, summary(times[n])]));
}

const scalar = await build("spark_spawn"), route = await build("spark_routes");
const guest = await instantiateGuest(scalar.module),
  game = await instantiateGuest(route.module);
const scalarRuns = [],
  markedWorkerRuns = [],
  routeRuns = [],
  fullRouteRuns = [],
  processes = [];
try {
  for (const size of [32, 1024, 4096]) {
    const xs = Uint32Array.from(
      { length: size },
      (_, i) => Math.imul(i, 0xf00dbeef),
    );
    const entries = ["ordinary_mix", "indexed_mix", "spark_mix"];
    const expected = xs.map((x) => (Math.imul(x, 1664525) ^ 1013904223) >>> 0);
    const fns = Object.fromEntries(
      entries.map((name) => [name, () => guest.call(name, xs) as Uint32Array]),
    );
    scalarRuns.push({ size, result: await compare(fns, expected) });
  }
  const marked = await SparkPool.open(scalar.module, {
    entry: "spark_mix",
    width: 1,
    workers: 4,
    waitMs: 2000,
  });
  try {
    for (const size of [1024, 32768]) {
      const xs = Uint32Array.from(
        { length: size },
        (_, i) => Math.imul(i, 0xf00dbeef),
      );
      const expected = xs.map((x) =>
        (Math.imul(x, 1664525) ^ 1013904223) >>> 0
      );
      const result = await compare({
        indexed: () => guest.call("indexed_mix", xs) as Uint32Array,
        spark: () => marked.direct(xs),
        worker_spark: () => marked.run(xs),
      }, expected);
      markedWorkerRuns.push({ size, result });
    }
    assert.equal(marked.fallbacks, 0);
  } finally {
    await marked.close();
  }
  const seed = 11;
  const ref = game.call("serial_shared", seed) as Float32Array;
  const rows = game.call(
    "routes",
    Uint32Array.of(seed, 0, 1, 2, 3),
  ) as Float32Array;
  assert.deepEqual(bits(selectFour(rows)), bits(ref));
  for (const workers of [1, 2, 4, 8]) {
    const budget = new SparkCopyBudget(10 * game.numericPacketCapacity());
    const t = performance.now();
    const pool = await SparkPool.open(route.module, {
      entry: "routes",
      width: 392,
      prefix: Uint32Array.of(seed),
      workers,
      waitMs: 2000,
      copyBudget: budget,
    });
    const setup_ms = performance.now() - t;
    try {
      for (
        const queries of [new Uint32Array(), Uint32Array.of(3, 99, 3, 1, 0)]
      ) {
        budget.beginFrame();
        assert.deepEqual(
          bits(await pool.run(queries)),
          bits(pool.direct(queries)),
        );
      }
      for (const size of [4, 32, 128]) {
        const queries = Uint32Array.from({ length: size }, (_, i) => i % 4);
        budget.beginFrame();
        const expected = pool.direct(queries);
        const before = pool.copiedBytes;
        const result = await compare({
          direct: () => {
            budget.beginFrame();
            return pool.direct(queries);
          },
          workers: () => {
            budget.beginFrame();
            return pool.run(queries);
          },
        }, expected);
        const copies = Object.fromEntries(
          (Object.keys(before) as (keyof typeof before)[]).map((site) => [
            site,
            pool.copiedBytes[site] - before[site],
          ]),
        );
        routeRuns.push({ size, workers, setup_ms, copies, result });
        if (size === 4) {
          const full = await compare({
            serial_shared: () =>
              game.call("serial_shared", seed) as Float32Array,
            workers: async () => {
              budget.beginFrame();
              return selectFour(await pool.run(queries));
            },
          }, ref);
          fullRouteRuns.push({ workers, result: full });
        }
      }
      assert.equal(pool.fallbacks, 0);
      budget.beginFrame();
      const queries = Uint32Array.of(3, 99, 3, 1, 0);
      const expected = pool.direct(queries);
      const restart = pool.run(queries);
      const retired = pool.retireWorkers();
      assert.deepEqual(bits(await restart), bits(expected));
      assert.equal(pool.fallbacks, 1);
      await retired;
    } finally {
      await pool.close();
    }
  }
  for (
    const [program, g, compiled, entry] of [
      ["planner", guest, scalar, "live"],
      ["route_planner", game, route, "start_route"],
    ] as const
  ) {
    const host = new ProcessHost(
      compiled.module,
      [{ name: program, initWork: 1, stepWork: 1 }],
      1,
      1,
    );
    const cap = g.capability({
      parameter: "Array U32",
      result: "U32",
      call: (packet) => host.admit(packet),
    });
    let t = performance.now();
    const endpoint = g.call(entry, cap) as number;
    const admission_ms = performance.now() - t;
    assert(endpoint > 0);
    t = performance.now();
    await host.advance(1);
    const init_ms = performance.now() - t;
    assert.equal(host.status(endpoint), "ready");
    const direct: number[] = [], process: number[] = [];
    let state = 11;
    for (let i = -4; i < samples; i++) {
      const command = (i + 4) * 5, pair = Uint32Array.of(state, command);
      const step = () => {
        const t = performance.now();
        state = g.call(program + "_step", pair) as number;
        if (i >= 0) direct.push(performance.now() - t);
      };
      let output = 0;
      const turn = async () => {
        const t = performance.now();
        const ticket = host.send(endpoint, command);
        await host.advance(1);
        const event = host.poll(endpoint);
        const elapsed = performance.now() - t;
        assert(event?.status === "done");
        assert.equal(event.ticket, ticket);
        output = event.value;
        if (i >= 0) process.push(elapsed);
      };
      if (i % 2 === 0) {
        step();
        await turn();
      } else {
        await turn();
        step();
      }
      assert.equal(output, state);
    }
    processes.push({
      program,
      admission_ms,
      init_ms,
      direct: summary(direct),
      process: summary(process),
    });
    host.restore();
  }
} finally {
  guest.dispose();
  game.dispose();
}
function identity(metadata: typeof route) {
  return {
    source: metadata.source,
    wasm: metadata.wasm,
    bytes: metadata.bytes,
  };
}
const dependencyFiles = [
  "test_support/path_plans.blot",
  "../ink/lib/navigation/lookahead.blot",
  "../ink/lib/navigation/locomotion.blot",
  "../ink/lib/navigation/ground.blot",
];
const deps = Object.fromEntries(
  await Promise.all(
    dependencyFiles.map(
      async (path) => [
        path,
        await sha(await Deno.readFile(resolve(root, path))),
      ],
    ),
  ),
);
console.log(JSON.stringify(
  {
    platform: Deno.build,
    deno: Deno.version,
    cpu: cpus()[0].model,
    logical_cpus: cpus().length,
    compiler: await sha(await Deno.readFile(executable)),
    kernel_inputs: deps,
    samples,
    scalar: identity(scalar),
    route: identity(route),
    scalarRuns,
    markedWorkerRuns,
    routeRuns,
    fullRouteRuns,
    processes,
  },
  null,
  2,
));
