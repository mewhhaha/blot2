// deno run -A benchmarks/intent/persistent.ts [compiler]
import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { gdevProject } from "../../scripts/integration/gdev_project.ts";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import {
  instrumentMemoryTraffic,
  traffic,
} from "../tools/guest_copy_observer.ts";
import { captureIntents } from "./capture.ts";

const root = resolve("../gdev");
const compilerPath = resolve(
  Deno.args[0] ?? "compiler-goose/build/blotc-goose",
);
const trace = await captureIntents(root, compilerPath);
const control = [
  [3, 0xffffffff],
  [0],
  [1, 0x80000000, 19, 23, 0xffffffff],
  [2, 33],
  [0],
  [0],
  [1, 1, 2, 3, 4],
];
const datasets = [trace, control];
const variants = [
  "fixed_flat",
  "fixed_chunks",
  "packed_flat",
  "packed_chunks",
  "grouped_flat",
  "grouped_chunks",
];
const helpers = `
func benchmark_handle kind -> region -> origin -> slot -> generation => return $Handle {kind, region, origin, slot, generation}
func benchmark_words (h: Handle kind): (U32, U32, U32, U32) => return (h.region, h.origin, h.slot, h.generation)
`;

function literal([tag, ...words]: number[]) {
  switch (tag) {
    case 0:
      return "$plan.Idle";
    case 1:
      return "($plan.Collect (handles.benchmark_handle $plan.Pile " +
        words.join(" ") + "))";
    case 2:
      return "($plan.Deliver (plan.home " + words[0] + "))";
    case 3:
      return "($plan.Rest (plan.home " + words[0] + "))";
    default:
      throw Error("unexpected intent " + tag);
  }
}
function entry(variant: string) {
  const [layout, join] = variant.split("_");
  let combine = `let branch_a = join_${layout} a tail
  let branch_b = join_${layout} b tail`;
  let scan = `let hash = scan_${layout} 1 branch_a
  hash := scan_${layout} self branch_b`;
  if (join === "chunks") {
    // A first-class list of immutable spans. Both branches reference the same tail.
    combine = "let branch_a = share a tail\n  let branch_b = share b tail";
    scan = `let hash = 1
  for chunk in branch_a:
    hash := scan_${layout} self chunk
  for chunk in branch_b:
    hash := scan_${layout} self chunk`;
  }
  return `
#entry func ${variant} (observe: U32 -> U32): U32 => return do:
  use count <- observe 0
  use control <- observe 1
  let source = if control == 0 then trace_input () else control_input ()
  use built_input <- observe 2
  let tail = ${layout} source 43 count
  let a = ${layout} source 7 (count / 8)
  let b = ${layout} source 19 ((count / 8) + 1)
  use built <- observe 3
  ${combine}
  use joined <- observe 4
  ${scan}
  hash := scan_${layout} self tail
  hash := scan_${layout} self a
  hash := scan_${layout} self b
  use scanned <- observe 5
  return hash + built_input + built + joined + scanned
`;
}
const chains = ["chain_flat", "chain_builder", "chain_chunks", "chain_grouped"];
function chain(name: string) {
  let layout = "fixed";
  if (name === "chain_grouped") layout = "grouped";
  let initial = "let joined: List plan.Intent = []";
  let extend = "joined := @list.concat self part";
  let scan = "let hash = scan_fixed 1 joined";
  if (name === "chain_builder") {
    extend = "for item in part:\n      joined := @list.append self item";
  }
  if (name === "chain_chunks" || name === "chain_grouped") {
    let chunkType = "List plan.Intent";
    if (layout === "grouped") chunkType = "Grouped";
    initial = `let joined: List (${chunkType}) = []`;
    extend = "joined := @list.append self part";
    scan =
      `let hash = 1\n  for chunk in joined:\n    hash := scan_${layout} self chunk`;
  }
  return `
#entry func ${name} (observe: U32 -> U32): U32 => return do:
  use count <- observe 0
  use control <- observe 1
  let source = if control == 0 then trace_input () else control_input ()
  use built_input <- observe 2
  let a = ${layout} source 7 31
  let b = ${layout} source 43 33
  use built <- observe 3
  ${initial}
  for i in 0..count:
    let part = if (i & 1) == 0 then a else b
    ${extend}
  use joined_at <- observe 4
  ${scan}
  hash := scan_${layout} self a
  hash := scan_${layout} self b
  use scanned <- observe 5
  return hash + built_input + built + joined_at + scanned
`;
}
const appendSites = ["homes_in_arms", "homes_after_match"];
function appendSiteEntry(name: string) {
  return `
#entry func test_${name} (observe: U32 -> U32): U32 => return do:
  use count <- observe 0
  use dataset <- observe 1
  let source = control_input ()
  use start <- observe 2
  let values = ${name} source count
  use built <- observe 3
  use read <- observe 4
  let hash = 1
  for value in values:
    hash := mix self value
  use end <- observe 5
  return hash + start + built + read + end
`;
}
const project = await gdevProject(
  root,
  resolve("std"),
  "performance/intent_builder_probe.blot",
  compilerPath,
);
const handles = resolve("../ink/lib/handles.blot");
const base = await Deno.readTextFile(
  resolve("benchmarks/intent/builders.blot"),
);
const inputs = datasets.map((rows, i) =>
  "func " + ["trace_input", "control_input"][i] +
  " (): Array plan.Intent => return #[\n  " + rows.map(literal).join(",\n  ") +
  "\n]\n"
).join("\n");
const handleSource = await Deno.readTextFile(handles) + "\n" + helpers;
async function compile(entries: string) {
  const source = base + "\n" + inputs + entries;
  const start = performance.now();
  const client = await createZigProjectCompiler(project);
  try {
    const result = await client.build({
      sources: { [project.entry]: source, [handles]: handleSource },
      signal: AbortSignal.timeout(12000),
    });
    if (!result.success) {
      throw Error(JSON.stringify(result.diagnostics, null, 2));
    }
    return {
      bytes: result.bytes,
      ms: performance.now() - start,
      fresh: result.stats.freshModules,
    };
  } finally {
    await client.dispose();
  }
}
const compiled = await compile(
  variants.map(entry).concat(
    chains.map(chain),
    appendSites.map(appendSiteEntry),
  ).join("\n"),
);
const bytes = compiled.bytes;
function expected(rows: number[][], n: number, repeated = false) {
  const prefix = Math.floor(n / 8);
  let spans = [[7, prefix], [43, n], [19, prefix + 1], [43, n], [43, n], [
    7,
    prefix,
  ], [19, prefix + 1]];
  if (repeated) {
    const chunks = [[7, 31], [43, 33]];
    spans = Array.from({ length: n }, (_, i) => chunks[i % 2]).concat(chunks);
  }
  let h = 1;
  for (const [start, len] of spans) {
    for (let i = 0; i < len; i++) {
      for (const word of rows[(start + i) % rows.length]) {
        h = (Math.imul(h, 16777619) + word) >>> 0;
      }
    }
  }
  return h;
}
type Receipt = { copy: number; reserved: number; owners: number };
type Sample = {
  buildUs: number;
  joinUs: number;
  scanUs: number;
  totalUs: number;
};
type Memory = {
  buildCopy: number;
  joinCopy: number;
  buildReserved: number;
  joinReserved: number;
  buildOwners: number;
  joinOwners: number;
};
function runner(wasm: Uint8Array<ArrayBuffer>, measured: boolean) {
  const mod = new WebAssembly.Module(wasm);
  let points: Receipt[] = [];
  let markers: number[] = [];
  let timestamps: number[] = [];
  let size = 0, dataset = 0;
  let ownerCapacity = 0;
  const observe = (_callback: number, marker: number) => {
    if (marker === 0) return size;
    if (marker === 1) return dataset;
    timestamps.push(performance.now());
    markers.push(marker);
    if (measured) {
      const ex = instance.exports;
      const top = Number((ex["qual:owner_top"] as WebAssembly.Global).value);
      const bottom = Number(
        (ex["qual:persistent_bottom"] as WebAssembly.Global).value,
      );
      const cap = ownerCapacity;
      assert(
        top >= 1 && top <= bottom && bottom <= cap,
        JSON.stringify({ top, bottom, cap }),
      );
      const u = new Uint32Array(
        (ex["qual:memory"] as WebAssembly.Memory).buffer,
      );
      let reserved = 0;
      for (let i = 1; i < top; i++) reserved += u[256 + 4 * i + 2] & 0x3fffffff;
      for (let i = bottom; i < cap; i++) {
        reserved += u[256 + 4 * i + 2] & 0x3fffffff;
      }
      points.push({
        copy: traffic(ex).copy,
        reserved,
        owners: top - 1 + cap - bottom,
      });
    }
    return 0;
  };
  assert.deepEqual(WebAssembly.Module.imports(mod), [{
    module: "blot:host/1",
    name: "call_u32_u32",
    kind: "function",
  }]);
  const instance = new WebAssembly.Instance(mod, {
    "blot:host/1": { call_u32_u32: observe },
  });
  if (measured) {
    assert.equal(
      (instance.exports["qual:owner_top"] as WebAssembly.Global).value,
      1,
    );
    ownerCapacity = Number(
      (instance.exports["qual:persistent_bottom"] as WebAssembly.Global).value,
    );
    assert(ownerCapacity > 1 && ownerCapacity <= 65536);
  }
  function run(variant: string, n: number, di: number, hash: number) {
    points = [];
    timestamps = [];
    markers = [];
    size = n;
    dataset = di;
    const exports = instance.exports as Record<string, CallableFunction>;
    try {
      assert.equal(exports[variant](1) >>> 0, hash, [variant, n, di].join(" "));
      assert.deepEqual(markers, [2, 3, 4, 5]);
    } finally {
      exports["blot:finish_invocation"]();
    }
    const [s, b, j, e] = timestamps;
    const sample: Sample = {
      buildUs: (b - s) * 1000,
      joinUs: (j - b) * 1000,
      scanUs: (e - j) * 1000,
      totalUs: (e - s) * 1000,
    };
    let allocation: Memory | undefined;
    if (measured) {
      const [input, built, joined] = points;
      allocation = {
        buildCopy: built.copy - input.copy,
        joinCopy: joined.copy - built.copy,
        buildReserved: built.reserved - input.reserved,
        joinReserved: joined.reserved - built.reserved,
        buildOwners: built.owners - input.owners,
        joinOwners: joined.owners - built.owners,
      };
    }
    return { sample, allocation };
  }
  return run;
}

const native = runner(bytes, false);
const observed = runner(
  instrumentMemoryTraffic(bytes, { ownerTable: true }),
  true,
);
for (let d = 0; d < datasets.length; d++) {
  for (
    const n of [
      0,
      1,
      2,
      3,
      4,
      7,
      8,
      15,
      16,
      23,
      24,
      31,
      32,
      33,
      63,
      64,
      65,
      287,
      288,
      289,
    ]
  ) {
    const hash = expected(datasets[d], n);
    for (const name of variants) native(name, n, d, hash);
    if (n <= 33) {
      for (const name of chains) {
        native(name, n, d, expected(datasets[d], n, true));
      }
    }
  }
}
const results = [];
function median(values: number[]) {
  const sorted = values.toSorted((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  if (sorted.length % 2) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) / 2;
}
function medianSample(samples: Sample[]): Sample {
  return {
    buildUs: median(samples.map((v) => v.buildUs)),
    joinUs: median(samples.map((v) => v.joinUs)),
    scanUs: median(samples.map((v) => v.scanUs)),
    totalUs: median(samples.map((v) => v.totalUs)),
  };
}
function measure(
  scenario: string,
  variants: string[],
  d: number,
  n: number,
  hash: number,
) {
  const rows = variants.map((name) => ({
    name,
    samples: [] as Sample[],
    memory: observed(name, n, d, hash).allocation!,
  }));
  for (const row of rows) {
    if (scenario === "shared_tail" && row.name.endsWith("_chunks")) {
      assert.equal(row.memory.joinCopy, 0);
      assert(row.memory.joinOwners <= 2);
    }
    if (scenario === "shared_tail" && row.name === "fixed_flat") {
      assert(row.memory.joinCopy <= 20 * (2 * n + 2 * Math.floor(n / 8) + 1));
    }
    if (row.name === "chain_flat") {
      let elements = 0, copied = 0;
      for (let i = 0; i < n; i++) {
        elements += [31, 33][i % 2];
        copied += 20 * elements;
      }
      assert(row.memory.joinCopy <= copied);
    }
  }
  for (let round = 0; round < 4 + variants.length * 2; round++) {
    for (let j = 0; j < variants.length; j++) {
      const row = rows[(j + round) % rows.length];
      const batch: Sample[] = [];
      for (let rep = 0; rep < 9; rep++) {
        batch.push(native(row.name, n, d, hash).sample);
      }
      if (round >= 4) {
        row.samples.push(medianSample(batch));
      }
    }
  }
  return {
    scenario,
    dataset: ["gdev", "mixed"][d],
    n,
    hash,
    variants: rows.map((row) => ({
      ...row,
      median: medianSample(row.samples),
    })),
  };
}
for (let d = 0; d < datasets.length; d++) {
  for (const n of [256, 1024, 4096]) {
    results.push(
      measure("shared_tail", variants, d, n, expected(datasets[d], n)),
    );
  }
  for (const n of [8, 32, 128]) {
    results.push(
      measure("repeated_concat", chains, d, n, expected(datasets[d], n, true)),
    );
  }
}
for (const n of [256, 1024, 4096]) {
  let hash = 1, length = 0;
  for (let i = 0; i < n; i++) {
    const [tag, word] = control[i % control.length];
    if (tag === 2 || tag === 3) {
      hash = (Math.imul(hash, 16777619) + word) >>> 0;
      length++;
    }
  }
  const record = measure(
    "exclusive_appends",
    appendSites.map((s) => "test_" + s),
    1,
    n,
    hash,
  );
  // Copying a flat prefix once per append moves 4 * (0 + ... + length-1) bytes.
  assert(record.variants[0].memory.buildCopy <= 2 * length * (length - 1));
  assert(record.variants[1].memory.buildCopy <= 8 * length);
  results.push(record);
}
const layouts = ["fixed", "packed", "grouped"];
const modules = new Map<
  string,
  { bytes: number; sha256: string; fresh: unknown; compileMs: number[] }
>();
// Equal exported names, each layout gets two independent builds in each position.
for (let round = 0; round < 6; round++) {
  for (let i = 0; i < 3; i++) {
    const layout = layouts[(i + round) % layouts.length];
    const entries = ["flat", "chunks"].map((kind) =>
      entry(layout + "_" + kind).replace(
        "#entry func " + layout + "_" + kind,
        "#entry func " + kind,
      )
    );
    const result = await compile(entries.join("\n"));
    const digest = await sha256(result.bytes);
    if (!modules.has(layout)) {
      modules.set(layout, {
        bytes: result.bytes.length,
        sha256: digest,
        fresh: result.fresh,
        compileMs: [],
      });
    }
    const saved = modules.get(layout)!;
    assert.equal(digest, saved.sha256);
    saved.compileMs.push(result.ms);
  }
}
async function sha256(data: Uint8Array<ArrayBuffer>) {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", data)).toHex();
}
async function revision(path: string) {
  const r = await new Deno.Command("git", {
    args: ["-C", path, "rev-parse", "HEAD"],
  }).output();
  assert(r.success);
  return new TextDecoder().decode(r.stdout).trim();
}
console.log(JSON.stringify(
  {
    hostCpu: Deno.env.get("PROCESSOR_IDENTIFIER") ??
      (await Deno.readTextFile("/proc/cpuinfo").catch(() => "")).split("\n")
        .find((s) => s.startsWith("model name"))?.split(":").at(-1)?.trim(),
    compilerSha256: await sha256(await Deno.readFile(compilerPath)),
    gdev: await revision(root),
    ink: await revision("../ink"),
    wasmSha256: await sha256(bytes),
    wasmBytes: bytes.length,
    compileMs: compiled.ms,
    layoutModules: Object.fromEntries(modules),
    tools: Deno.version,
    sourceTraceSha256: await sha256(
      new TextEncoder().encode(JSON.stringify(trace)),
    ),
    counts: datasets.map((rows) =>
      [0, 1, 2, 3].map((tag) => rows.filter((r) => r[0] === tag).length)
    ),
    results,
  },
  null,
  2,
));
