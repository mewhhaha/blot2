// Compile-cost budgets on deterministic work counters, never wall time.
//
// Each synthetic program scales one pattern (see scripts/bench/corpus.ts) and
// the compiler reports counters that depend only on the source: type nodes,
// inference regions and scopes, callee body collections, solver passes and
// occurs steps, and requested allocator bytes. A budget is the value measured
// when it was set times 1.5, so ordinary churn passes while any super-linear
// regression in instantiation, collection or solving fails.
//
// Later hills (summary-based instantiation) are expected to LOWER these
// counters. When they do, re-measure and tighten `today` below; a budget that
// stays loose after an improvement stops guarding against regressions.
import { strict as assert } from "node:assert";
import {
  chainGeneric,
  chainMono,
  diamond,
  fanout,
  type SyntheticProgram,
} from "../../scripts/bench/corpus.ts";

const compiler = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const prelude = new URL("../../std/prelude.blot", import.meta.url).pathname;
const scratchRoot = new URL("../../build/tmp/", import.meta.url).pathname;

/** Headroom over the measured value; a later hill should tighten `today`. */
const headroom = 1.5;

interface Counters {
  inference_regions: number;
  region_scopes: number;
  max_region_scopes: number;
  call_collections_closed: number;
  call_collections_unresolved: number;
  call_memo_hits: number;
  solver_passes: number;
  solver_constraint_visits: number;
  occurs_steps: number;
}
interface Measurement {
  success: boolean;
  diagnostic?: { code: string };
  type_nodes: number;
  allocated_bytes: number;
  counters: Counters;
}
/** Counters pinned by a budget; call_memo_hits is informational only. */
type Budgeted =
  & { type_nodes: number; allocated_bytes: number }
  & Omit<Counters, "call_memo_hits">;

async function measure(program: SyntheticProgram): Promise<Measurement> {
  await Deno.mkdir(scratchRoot, { recursive: true });
  const directory = await Deno.makeTempDir({
    dir: scratchRoot,
    prefix: `budget-${program.name}-`,
  });
  try {
    const input = `${directory}/main.blot`;
    const output = `${directory}/main.wasm`;
    await Deno.writeTextFile(input, program.source);
    const result = await new Deno.Command(compiler, {
      args: ["build", input, output, "--prelude", prelude],
      stdout: "piped",
      stderr: "piped",
    }).output();
    const records = new TextDecoder().decode(result.stdout).trim().split("\n")
      .map((line) => JSON.parse(line));
    const metrics = records.find((record) => record.kind === "compilation");
    assert(metrics, new TextDecoder().decode(result.stderr));
    return {
      success: metrics.success,
      diagnostic: records.find((record) => record.kind === "diagnostic"),
      type_nodes: metrics.type_nodes,
      allocated_bytes: metrics.memory.allocated_bytes,
      counters: metrics.work_counters,
    };
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
}

function assertWithinBudget(
  label: string,
  actual: Measurement,
  today: Budgeted,
) {
  assert(actual.success, `${label} failed: ${JSON.stringify(actual)}`);
  const observed: Budgeted = {
    type_nodes: actual.type_nodes,
    allocated_bytes: actual.allocated_bytes,
    ...actual.counters,
  };
  const failures: string[] = [];
  for (const [name, measured] of Object.entries(today)) {
    const budget = Math.ceil(measured * headroom);
    const value = observed[name as keyof Budgeted];
    if (!(value <= budget)) {
      failures.push(`${name}: ${value} exceeds budget ${budget} (was ${measured})`);
    }
  }
  assert.equal(
    failures.length,
    0,
    `${label} regressed its compile budget:\n${failures.join("\n")}\nobserved ${
      JSON.stringify(observed)
    }`,
  );
}

// Annotated links are closed signatures: each body is collected once per call
// site and memoized by evidence, so work stays linear in the chain length.
Deno.test("budget: chain_mono N=128 stays linear", async () => {
  assertWithinBudget(
    "chain_mono N=128",
    await measure(chainMono(128)),
    {
      type_nodes: 11102,
      allocated_bytes: 5687109,
      inference_regions: 133,
      region_scopes: 910,
      max_region_scopes: 388,
      call_collections_closed: 259,
      call_collections_unresolved: 258,
      solver_passes: 137,
      solver_constraint_visits: 260,
      occurs_steps: 780,
    },
  );
});

// Generic links stay unresolved, so every use re-collects the callee body and
// the chain is quadratic today (compare unresolved collections with N^2/2).
Deno.test("budget: chain_generic N=64 holds today's quadratic cost", async () => {
  assertWithinBudget(
    "chain_generic N=64",
    await measure(chainGeneric(64)),
    {
      type_nodes: 23429,
      allocated_bytes: 9149403,
      inference_regions: 69,
      region_scopes: 6828,
      max_region_scopes: 196,
      call_collections_closed: 1,
      call_collections_unresolved: 4483,
      solver_passes: 2344,
      solver_constraint_visits: 52195,
      occurs_steps: 13583,
    },
  );
});

// Two uses per link re-collect the callee body per path: exponential today.
// N=8 is the largest size that stays cheap; see the ignored N=16 probe below.
Deno.test("budget: diamond N=8 holds today's cost", async () => {
  assertWithinBudget(
    "diamond N=8",
    await measure(diamond(8)),
    {
      type_nodes: 76681,
      allocated_bytes: 12107968,
      inference_regions: 13,
      region_scopes: 4084,
      max_region_scopes: 1024,
      call_collections_closed: 1,
      call_collections_unresolved: 3047,
      solver_passes: 1036,
      solver_constraint_visits: 109738,
      occurs_steps: 8151,
    },
  );
});

// Independent generic callees, each used at U32 and F32 in one body: the
// per-instance regions and memo hits grow linearly with the callee count.
Deno.test("budget: fanout N=128 stays linear", async () => {
  assertWithinBudget(
    "fanout N=128",
    await measure(fanout(128)),
    {
      type_nodes: 21095,
      allocated_bytes: 8672641,
      inference_regions: 264,
      region_scopes: 793,
      max_region_scopes: 265,
      call_collections_closed: 517,
      call_collections_unresolved: 2,
      solver_passes: 269,
      solver_constraint_visits: 10,
      occurs_steps: 1566,
    },
  );
});

// KNOWN FAILING TODAY. These document cliffs that upcoming hills must remove;
// un-ignore each one when the hill that fixes it lands.

// ClosureRegion.collect recurses once per chained call, so a monomorphic chain
// of 300 links exceeds options.max_depth (256) and the build is rejected with
// `constant_fuel`. Summary-based instantiation should compile it in linear work.
Deno.test({
  name: "cliff: chain_mono N=300 compiles",
  ignore: true,
  fn: async () => {
    const actual = await measure(chainMono(300));
    assert(
      actual.success,
      `chain_mono N=300 rejected with ${actual.diagnostic?.code}`,
    );
    assert(actual.counters.inference_regions <= 400, "regions must stay linear");
  },
});

// Each level collects its generic callee twice, so work doubles per level
// (diamond N=10 already performs ~12k unresolved collections and ~1.7M
// constraint visits). With one summary per callee the cost is linear in N.
Deno.test({
  name: "cliff: diamond N=16 stays linear",
  ignore: true,
  fn: async () => {
    const actual = await measure(diamond(16));
    assert(actual.success, `diamond N=16 rejected: ${actual.diagnostic?.code}`);
    assert(
      actual.counters.call_collections_unresolved <= 16 * 16,
      `diamond N=16 collected ${actual.counters.call_collections_unresolved} bodies`,
    );
    assert(
      actual.counters.solver_constraint_visits <= 16 * 1024,
      `diamond N=16 visited ${actual.counters.solver_constraint_visits} constraints`,
    );
  },
});
