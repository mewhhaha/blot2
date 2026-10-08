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
      failures.push(
        `${name}: ${value} exceeds budget ${budget} (was ${measured})`,
      );
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
      type_nodes: 10461,
      allocated_bytes: 6354769,
      inference_regions: 264,
      region_scopes: 396,
      max_region_scopes: 2,
      call_collections_closed: 0,
      call_collections_unresolved: 0,
      solver_passes: 660,
      solver_constraint_visits: 780,
      occurs_steps: 9,
    },
  );
});

// Generic bodies are inferred once for each closed input signature.
Deno.test("budget: chain_generic N=64 stays linear", async () => {
  assertWithinBudget(
    "chain_generic N=64",
    await measure(chainGeneric(64)),
    {
      type_nodes: 9382,
      allocated_bytes: 5670642,
      inference_regions: 201,
      region_scopes: 204,
      max_region_scopes: 2,
      call_collections_closed: 0,
      call_collections_unresolved: 0,
      solver_passes: 725,
      solver_constraint_visits: 844,
      occurs_steps: 591,
    },
  );
});

// Shared callee summaries bound the work by bodies, regardless of path count.
Deno.test("budget: diamond N=8 stays linear", async () => {
  assertWithinBudget(
    "diamond N=8",
    await measure(diamond(8)),
    {
      type_nodes: 6479,
      allocated_bytes: 3357343,
      inference_regions: 33,
      region_scopes: 36,
      max_region_scopes: 2,
      call_collections_closed: 0,
      call_collections_unresolved: 0,
      solver_passes: 109,
      solver_constraint_visits: 116,
      occurs_steps: 87,
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
      type_nodes: 18554,
      allocated_bytes: 10786346,
      inference_regions: 782,
      region_scopes: 791,
      max_region_scopes: 2,
      call_collections_closed: 0,
      call_collections_unresolved: 0,
      solver_passes: 1312,
      solver_constraint_visits: 3095,
      occurs_steps: 1563,
    },
  );
});

// Deep calls and shared DAGs cannot consume the execution depth budget.
for (
  const program of [
    chainMono(300),
    chainMono(1000),
    chainGeneric(300),
    diamond(16),
  ]
) {
  Deno.test(`budget: ${program.name} N=${program.size} compiles with bounded regions`, async () => {
    const actual = await measure(program);
    assert(
      actual.success,
      `${program.name} rejected: ${actual.diagnostic?.code}`,
    );
    assert(actual.counters.region_scopes <= program.size * 4 + 20);
    assert(actual.counters.max_region_scopes <= 4);
    assert.equal(actual.counters.call_collections_unresolved, 0);
    assert(actual.counters.solver_constraint_visits <= program.size * 16 + 32);
  });
}
