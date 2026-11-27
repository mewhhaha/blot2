// deno run -A benchmarks/language/spark_spawn.ts [gdev checkout] [squidc executable]
import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { cpus } from "node:os";
import { compileKernelModule, instantiateGuest } from "../../host/guest.ts";
import { KernelPool } from "../../host/kernels.ts";
import { Processes, type ProcessHandle } from "../../host/processes.ts";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { gdevProject } from "../../scripts/integration/gdev_project.ts";
import { selectFour } from "./route_result.js";

const root = resolve(Deno.args[0] ?? "../gdev");
const executable = resolve(Deno.args[1] ?? "compiler-goose/build/squidc-goose");
const samples = 21;
const sha = async (bytes: Uint8Array<ArrayBuffer>) =>
  new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)).toHex();

async function build(stem: string) {
  const path = "performance/modernize/" + stem + ".sq";
  const project = await gdevProject(root, resolve("std"), path, executable);
  const src = await Deno.readFile(
    new URL("./" + stem + ".sq", import.meta.url),
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
      const output = Deno.env.get("SQUID_ROUTE_WASM");
      if (output) await Deno.writeFile(output, r.bytes);
    }
    return {
      receipt: compileKernelModule(r.bytes),
      rawBytes: r.bytes,
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
const guest = await instantiateGuest(scalar.receipt.module),
  game = await instantiateGuest(route.receipt.module);
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
  const directMix = await KernelPool.open(scalar.receipt, "mix_kernel", {
    workers: 0,
  });
  const parallelMix = await KernelPool.open(scalar.receipt, "mix_kernel", {
    workers: 4,
    defaultChunkItems: 8192,
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
        direct_kernel: () => directMix.runFixed(xs),
        worker_kernel: () => parallelMix.runFixed(xs),
      }, expected);
      markedWorkerRuns.push({ size, result });
    }
  } finally {
    await Promise.all([directMix.close(), parallelMix.close()]);
  }

  const seed = 11;
  const seedBytes = Uint32Array.of(seed);
  const ref = game.call("serial_shared", seed) as Float32Array;
  const unpackTo392 = (packed: Uint32Array, count: number): Float32Array => {
    const out = new Float32Array(count * 392);
    const fview = new Float32Array(
      packed.buffer,
      packed.byteOffset,
      packed.length,
    );
    let at = 0;
    for (let i = 0; i < count; i++) {
      const len = packed[at++];
      out[i * 392] = len;
      if (len > 0) {
        out.set(fview.subarray(at, at + len), i * 392 + 1);
        at += len;
      }
    }
    return out;
  };
  const directRoutePool = await KernelPool.open(route.receipt, "routes", {
    workers: 0,
    defaultChunkItems: 4,
  });
  await directRoutePool.setContext(1, seedBytes);
  try {
    const rowsWords = await directRoutePool.runVariable(
      Uint32Array.of(0, 1, 2, 3),
    );
    const rows = unpackTo392(rowsWords, 4);
    assert.deepEqual(bits(selectFour(rows)), bits(ref));

    for (const workers of [1, 2, 4, 8]) {
      const t = performance.now();
      const pool = await KernelPool.open(route.receipt, "routes", {
        workers,
        defaultChunkItems: 4,
        deadlineMs: 5000,
      });
      await pool.setContext(1, seedBytes);
      const setup_ms = performance.now() - t;
      try {
        for (
          const queries of [new Uint32Array(), Uint32Array.of(3, 99, 3, 1, 0)]
        ) {
          assert.deepEqual(
            bits(await pool.runVariable(queries)),
            bits(await directRoutePool.runVariable(queries)),
          );
        }
        for (const size of [4, 32, 128]) {
          const queries = Uint32Array.from({ length: size }, (_, i) => i % 4);
          const expected = await directRoutePool.runVariable(queries);
          const result = await compare({
            direct: () => directRoutePool.runVariable(queries),
            workers: () => pool.runVariable(queries),
          }, expected);
          routeRuns.push({
            size,
            workers,
            setup_ms,
            peak_charged_bytes: pool.stats.peakChargedBytes,
            result,
          });
          if (size === 4) {
            const full = await compare({
              serial_shared: () =>
                game.call("serial_shared", seed) as Float32Array,
              workers: async () => {
                const w = await pool.runVariable(queries);
                return selectFour(unpackTo392(w, 4));
              },
            }, ref);
            fullRouteRuns.push({ workers, result: full });
          }
        }
      } finally {
        await pool.close();
      }
    }
  } finally {
    await directRoutePool.close();
  }

  for (
    const [program, g, compiled, entry] of [
      ["planner", guest, scalar, "live"],
      ["route_planner", game, route, "start_route"],
    ] as const
  ) {
    const host = new Processes(
      compiled.receipt,
      [{
        name: program,
        initWork: 1,
        stepWork: 1,
        mailbox: 1,
        mailboxBytes: 64,
        maxReplyBytes: 4,
      }],
      { slots: 1 },
    );
    let admittedHandle: ProcessHandle | null = null;
    const cap = g.capability({
      parameter: "Array U32",
      result: "U32",
      call: (packet) => {
        const name = new TextDecoder().decode(
          Uint8Array.from(packet.subarray(1)),
        );
        const h = host.admit(name, packet[0]);
        if (h === null) return 0;
        admittedHandle = h;
        return h.endpoint;
      },
    });
    let t = performance.now();
    const endpoint = g.call(entry, cap) as number;
    const admission_ms = performance.now() - t;
    assert(endpoint > 0 && admittedHandle !== null);
    t = performance.now();
    await host.advance(1);
    const init_ms = performance.now() - t;
    assert.equal(host.status(admittedHandle), "ready");
    const processTimes: number[] = [];
    for (let i = -4; i < samples; i++) {
      const command = (i + 4) * 5;
      const t0 = performance.now();
      const ticket = host.send(admittedHandle, command);
      assert.equal(typeof ticket, "number");
      await host.advance(1);
      const event = host.poll(admittedHandle);
      const elapsed = performance.now() - t0;
      assert(event?.status === "done");
      assert.equal(event.ticket, ticket);
      if (i >= 0) processTimes.push(elapsed);
    }
    processes.push({
      program,
      admission_ms,
      init_ms,
      process: summary(processTimes),
    });
    await host.restore();
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
  "test_support/path_plans.sq",
  "../ink/lib/navigation/lookahead.sq",
  "../ink/lib/navigation/locomotion.sq",
  "../ink/lib/navigation/ground.sq",
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
