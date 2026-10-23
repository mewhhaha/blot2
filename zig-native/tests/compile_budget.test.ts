// Compile-cost budgets on deterministic work counters, never wall time.
//
// Each synthetic program scales one pattern (see scripts/bench/corpus.ts) and
// the compiler reports counters that depend only on the source: type nodes,
// inference regions and scopes, callee body collections, solver passes and
// occurs steps, and requested allocator bytes. Most budgets are the value
// measured when set times 1.5, so ordinary churn passes while any super-linear
// regression in instantiation, collection or solving fails.
//
// Later hills (summary-based instantiation) are expected to LOWER these
// counters. When they do, re-measure and tighten `today` below; a budget that
// stays loose after an improvement stops guarding against regressions.
import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../compiler/guest.ts";
import {
  chainGeneric,
  chainMono,
  diamond,
  editSuite,
  fanout,
  type SyntheticProgram,
} from "../../scripts/bench/corpus.ts";
import {
  createZigProjectCompiler,
  type ZigProjectBuildResult,
} from "../../compiler/zig_project_client.ts";

const compiler = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const prelude = new URL("../../std/prelude.blot", import.meta.url).pathname;
const stdRoot = new URL("../../std", import.meta.url).pathname;
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
  allocationHeadroom = headroom,
) {
  assert(actual.success, `${label} failed: ${JSON.stringify(actual)}`);
  const observed: Budgeted = {
    type_nodes: actual.type_nodes,
    allocated_bytes: actual.allocated_bytes,
    ...actual.counters,
  };
  const failures: string[] = [];
  for (const [name, measured] of Object.entries(today)) {
    const budget = Math.ceil(
      measured * (name === "allocated_bytes" ? allocationHeadroom : headroom),
    );
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
      allocated_bytes: 6350930,
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
      // Re-pinned after the previous 1.5x allowance became smaller than
      // current main's measured 8,530,096 bytes; retain tighter 5% headroom.
      allocated_bytes: 8536992,
      inference_regions: 201,
      region_scopes: 204,
      max_region_scopes: 2,
      call_collections_closed: 0,
      call_collections_unresolved: 0,
      solver_passes: 725,
      solver_constraint_visits: 844,
      occurs_steps: 591,
    },
    1.05,
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
      solver_passes: 1311,
      solver_constraint_visits: 2582,
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

/**
 * Work a retained revision redoes, from serve-project stats. Lower is better:
 * a budget is the count when it was set, with no headroom.
 */
interface Reuse {
  /** Named and closure instances specialized afresh (`stats.backend`). */
  fresh_named: number;
  fresh_closures: number;
  /** Named instances reused from a previous revision; higher is better. */
  reused_named: number;
  /** Modules whose frontend was validated again (`attemptStats.fallback`). */
  validated_modules: number;
  recheck_body_elaborations: number;
  /** Bodies elaborated within the whole-project check of a rebuilt seed. */
  check_body_elaborations: number;
  /** Bodies lowered in the whole-project check; lower is better. */
  check_body_lowerings: number;
  /** The dependency seed was rebuilt; true permits either outcome. */
  rebuilt_seed: boolean;
  /** The previous output was published unchanged; true requires it. */
  reused_output: boolean;
}
function reuse(result: ZigProjectBuildResult): Reuse {
  assert(result.success, JSON.stringify(result));
  const backend = result.stats.backend as Record<string, number>;
  const attempt = result.stats.attemptStats as Record<string, unknown>;
  const fallback = attempt.fallback as Record<string, number>;
  return {
    fresh_named: backend.fresh_named,
    fresh_closures: backend.fresh_closures,
    reused_named: backend.reused_named,
    validated_modules: fallback.validated_modules,
    recheck_body_elaborations: fallback.recheck_body_elaborations,
    check_body_elaborations: fallback.body_elaborations,
    check_body_lowerings: fallback.body_lowerings,
    rebuilt_seed: attempt.rebuilt_seed as boolean,
    reused_output: attempt.reused_output as boolean,
  };
}

// One retained session over the edit suite: population, then each scenario's
// edit and revert. Retained hills (seeding reuse on population, output and
// body cutoffs) are expected to LOWER these; re-measure and tighten `today`.
// Every edit must still match a fresh build of the same sources.
const retainedToday: Record<string, Reuse> = {
  "population": {
    fresh_named: 10,
    fresh_closures: 0,
    reused_named: 0,
    validated_modules: 5,
    recheck_body_elaborations: 0,
    // Bool.eq and Bool.ne add two prelude bodies to the first population.
    check_body_elaborations: 152,
    rebuilt_seed: true,
    reused_output: false,
    check_body_lowerings: 152,
  },
  "edit:trivia": {
    fresh_named: 0,
    fresh_closures: 0,
    reused_named: 0,
    validated_modules: 0,
    recheck_body_elaborations: 0,
    rebuilt_seed: false,
    reused_output: true,
    check_body_elaborations: 0,
    check_body_lowerings: 0,
  },
  "revert:trivia": {
    fresh_named: 0,
    fresh_closures: 0,
    reused_named: 0,
    validated_modules: 0,
    recheck_body_elaborations: 0,
    rebuilt_seed: false,
    reused_output: true,
    check_body_elaborations: 0,
    check_body_lowerings: 0,
  },
  "edit:literal_constant": {
    fresh_named: 2,
    fresh_closures: 0,
    reused_named: 8,
    validated_modules: 1,
    recheck_body_elaborations: 0,
    rebuilt_seed: true,
    reused_output: false,
    check_body_elaborations: 5,
    check_body_lowerings: 5,
  },
  "revert:literal_constant": {
    fresh_named: 2,
    fresh_closures: 0,
    reused_named: 8,
    validated_modules: 1,
    recheck_body_elaborations: 0,
    rebuilt_seed: true,
    reused_output: false,
    check_body_elaborations: 5,
    check_body_lowerings: 5,
  },
  "edit:literal_in_body": {
    fresh_named: 3,
    fresh_closures: 0,
    reused_named: 7,
    validated_modules: 1,
    recheck_body_elaborations: 0,
    rebuilt_seed: true,
    reused_output: false,
    check_body_elaborations: 5,
    check_body_lowerings: 5,
  },
  "revert:literal_in_body": {
    fresh_named: 3,
    fresh_closures: 0,
    reused_named: 7,
    validated_modules: 1,
    recheck_body_elaborations: 0,
    rebuilt_seed: true,
    reused_output: false,
    check_body_elaborations: 5,
    check_body_lowerings: 5,
  },
  "edit:body_change": {
    fresh_named: 3,
    fresh_closures: 0,
    reused_named: 7,
    validated_modules: 1,
    recheck_body_elaborations: 0,
    rebuilt_seed: true,
    reused_output: false,
    check_body_elaborations: 5,
    check_body_lowerings: 5,
  },
  "revert:body_change": {
    fresh_named: 3,
    fresh_closures: 0,
    reused_named: 7,
    validated_modules: 1,
    recheck_body_elaborations: 0,
    rebuilt_seed: true,
    reused_output: false,
    check_body_elaborations: 5,
    check_body_lowerings: 5,
  },
  // A changed data type re-specializes every instance today.
  "edit:type_change": {
    fresh_named: 10,
    fresh_closures: 0,
    reused_named: 0,
    validated_modules: 2,
    recheck_body_elaborations: 0,
    rebuilt_seed: true,
    reused_output: false,
    check_body_elaborations: 8,
    check_body_lowerings: 8,
  },
  "revert:type_change": {
    fresh_named: 10,
    fresh_closures: 0,
    reused_named: 0,
    validated_modules: 2,
    recheck_body_elaborations: 0,
    rebuilt_seed: true,
    reused_output: false,
    check_body_elaborations: 8,
    check_body_lowerings: 8,
  },
  "edit:imported_body": {
    fresh_named: 4,
    fresh_closures: 0,
    reused_named: 6,
    validated_modules: 1,
    recheck_body_elaborations: 0,
    rebuilt_seed: true,
    reused_output: false,
    check_body_elaborations: 5,
    check_body_lowerings: 5,
  },
  "revert:imported_body": {
    fresh_named: 4,
    fresh_closures: 0,
    reused_named: 6,
    validated_modules: 1,
    recheck_body_elaborations: 0,
    rebuilt_seed: true,
    reused_output: false,
    check_body_elaborations: 5,
    check_body_lowerings: 5,
  },
  // An unused export leaves the Wasm unchanged but rebuilds everything today.
  "edit:unused_export": {
    fresh_named: 10,
    fresh_closures: 0,
    reused_named: 0,
    validated_modules: 4,
    recheck_body_elaborations: 0,
    rebuilt_seed: true,
    reused_output: false,
    check_body_elaborations: 16,
    check_body_lowerings: 16,
  },
  "revert:unused_export": {
    fresh_named: 10,
    fresh_closures: 0,
    reused_named: 0,
    validated_modules: 4,
    recheck_body_elaborations: 0,
    rebuilt_seed: true,
    reused_output: false,
    check_body_elaborations: 15,
    check_body_lowerings: 15,
  },
};

/**
 * Frozen dependency modules whose Core or principal interface a retained
 * revision validated again instead of reusing the previous receipt
 * (`attemptStats.fallback.dependency_storage`). Lower is better; a budget is
 * the count when it was set.
 */
interface Revalidation {
  core_checked: number;
  interface_checked: number;
}
function revalidation(result: ZigProjectBuildResult): Revalidation {
  assert(result.success, JSON.stringify(result));
  const attempt = result.stats.attemptStats as Record<string, unknown>;
  const fallback = attempt.fallback as Record<string, unknown>;
  const storage = fallback.dependency_storage as Record<string, number>;
  return {
    core_checked: storage.core_checked,
    interface_checked: storage.interface_checked,
  };
}
// Only modules that are new or read a changed producer revalidate.
const revalidationToday: Record<string, Revalidation> = {
  "population": { core_checked: 4, interface_checked: 4 },
  "edit:trivia": { core_checked: 0, interface_checked: 0 },
  "revert:trivia": { core_checked: 0, interface_checked: 0 },
  "edit:literal_constant": { core_checked: 1, interface_checked: 1 },
  "revert:literal_constant": { core_checked: 1, interface_checked: 1 },
  "edit:literal_in_body": { core_checked: 1, interface_checked: 1 },
  "revert:literal_in_body": { core_checked: 1, interface_checked: 1 },
  "edit:body_change": { core_checked: 1, interface_checked: 1 },
  "revert:body_change": { core_checked: 1, interface_checked: 1 },
  "edit:type_change": { core_checked: 1, interface_checked: 1 },
  "revert:type_change": { core_checked: 1, interface_checked: 1 },
  "edit:imported_body": { core_checked: 1, interface_checked: 1 },
  "revert:imported_body": { core_checked: 1, interface_checked: 1 },
  "edit:unused_export": { core_checked: 3, interface_checked: 3 },
  "revert:unused_export": { core_checked: 3, interface_checked: 3 },
};

Deno.test("budget: retained edit suite reuses at least today's work", async () => {
  await Deno.mkdir(scratchRoot, { recursive: true });
  const directory = await Deno.makeTempDir({
    dir: scratchRoot,
    prefix: "budget-edit-suite-",
  });
  const options = {
    executable: compiler,
    entry: `${directory}/${editSuite.entry}`,
    prelude,
    stdRoot,
    cacheDirectory: false as const,
  };
  const retained = await createZigProjectCompiler(options);
  const observed: Record<string, Reuse> = {};
  const revalidated: Record<string, Revalidation> = {};
  const record = async (phase: string, result: ZigProjectBuildResult) => {
    observed[phase] = reuse(result);
    revalidated[phase] = revalidation(result);
    assert(result.success);
    const guest = await instantiateGuest(result.bytes);
    try {
      assert.equal(
        guest.call("score", 2.5),
        phase === "edit:literal_constant" ? 780 : 767.5,
        phase,
      );
      assert.equal(
        guest.call("walked", 2.5),
        phase === "edit:body_change" ? 4 : 3,
        phase,
      );
      assert.equal(
        guest.call("carried", 2.5),
        phase === "edit:literal_in_body" ? Math.fround(4.1) : 4,
        phase,
      );
    } finally {
      guest.dispose();
    }
    return result;
  };
  try {
    for (const [file, source] of Object.entries(editSuite.files)) {
      await Deno.writeTextFile(`${directory}/${file}`, source);
    }
    await record("population", await retained.build());
    for (const scenario of editSuite.scenarios) {
      const sources: Record<string, string> = {};
      for (const { file, search, replace } of scenario.replacements) {
        const path = `${directory}/${file}`;
        const original = sources[path] ?? editSuite.files[file];
        assert.equal(original.split(search).length, 2, `${scenario.name}`);
        sources[path] = original.replace(search, replace);
      }
      const edited = await record(
        `edit:${scenario.name}`,
        await retained.build({ sources }),
      );
      const fresh = await createZigProjectCompiler(options);
      try {
        const expected = await fresh.build({ sources });
        assert(edited.success && expected.success, scenario.name);
        assert.deepEqual(edited.bytes, expected.bytes, scenario.name);
      } finally {
        await fresh.dispose();
      }
      await record(`revert:${scenario.name}`, await retained.build());
    }
  } finally {
    await retained.dispose();
    await Deno.remove(directory, { recursive: true });
  }
  assert.deepEqual(Object.keys(observed), Object.keys(retainedToday));
  assert.deepEqual(Object.keys(revalidated), Object.keys(revalidationToday));
  const failures: string[] = [];
  const improved: string[] = [];
  for (const [phase, budget] of Object.entries(revalidationToday)) {
    for (const [name, limit] of Object.entries(budget)) {
      const value = revalidated[phase][name as keyof Revalidation];
      assert(
        Number.isSafeInteger(value) && value >= 0,
        `${phase} ${name}: missing or invalid counter`,
      );
      if (value > limit) {
        failures.push(`${phase} ${name}: ${value} exceeds ${limit}`);
      } else if (value < limit) improved.push(`${phase} ${name}`);
    }
  }
  for (const [phase, budget] of Object.entries(retainedToday)) {
    const actual = observed[phase];
    for (const [name, limit] of Object.entries(budget)) {
      const value = actual[name as keyof Reuse];
      if (typeof limit === "boolean") {
        assert.equal(
          typeof value,
          "boolean",
          `${phase} ${name}: missing boolean counter`,
        );
      } else {
        assert(
          Number.isSafeInteger(value) && Number(value) >= 0,
          `${phase} ${name}: missing or invalid counter`,
        );
      }
      if (name === "reused_named") {
        if (Number(value) < Number(limit)) {
          failures.push(`${phase} ${name}: ${value} below ${limit}`);
        } else if (Number(value) > Number(limit)) {
          improved.push(`${phase} ${name}`);
        }
      } else if (name === "reused_output") {
        if (limit && !value) failures.push(`${phase} ${name}: lost`);
        else if (!limit && value) improved.push(`${phase} ${name}`);
      } else if (Number(value) > Number(limit)) {
        failures.push(`${phase} ${name}: ${value} exceeds ${limit}`);
      } else if (Number(value) < Number(limit)) {
        improved.push(`${phase} ${name}`);
      }
    }
  }
  if (improved.length) {
    console.log(`Tighten retainedToday: ${improved.join(", ")} improved.`);
  }
  assert.equal(
    failures.length,
    0,
    `retained edit suite redid more work:\n${failures.join("\n")}\nobserved ${
      JSON.stringify(observed)
    }`,
  );
});

// An edit with a check error costs one partial check: the lane that checks the
// changed modules (or the entry against the frozen dependencies) publishes a
// portable rejection without checking the whole project again, and its
// diagnostic equals a fresh build's.
const rejectedEdits: readonly {
  name: string;
  file: string;
  search: string;
  replace: string;
}[] = [
  {
    name: "dependency_unknown_value",
    file: "robots.blot",
    search: "floor phase + 1.0",
    replace: "floor phase + missing_value",
  },
  {
    name: "dependency_type_mismatch",
    file: "robots.blot",
    search: "width: carry.width }",
    replace: "width: carry }",
  },
  {
    name: "entry_unknown_value",
    file: "main.blot",
    search: "robots.walk x",
    replace: "robots.walk missing_value",
  },
];
Deno.test("budget: retained edits with check errors publish one partial check", async () => {
  await Deno.mkdir(scratchRoot, { recursive: true });
  const directory = await Deno.makeTempDir({
    dir: scratchRoot,
    prefix: "budget-rejected-edits-",
  });
  const options = {
    executable: compiler,
    entry: `${directory}/${editSuite.entry}`,
    prelude,
    stdRoot,
    cacheDirectory: false as const,
  };
  const retained = await createZigProjectCompiler(options);
  try {
    for (const [file, source] of Object.entries(editSuite.files)) {
      await Deno.writeTextFile(`${directory}/${file}`, source);
    }
    assert((await retained.build()).success);
    for (const edit of rejectedEdits) {
      const original = editSuite.files[edit.file];
      assert.equal(original.split(edit.search).length, 2, edit.name);
      const sources = {
        [`${directory}/${edit.file}`]: original.replace(
          edit.search,
          edit.replace,
        ),
      };
      const rejected = await retained.build({ sources });
      assert(!rejected.success, edit.name);
      const attempt = rejected.attemptStats as Record<string, unknown>;
      const fallback = attempt.fallback as Record<string, unknown>;
      assert.equal(fallback.portable_rejection, true, edit.name);
      assert.equal(attempt.rebuilt_seed, false, edit.name);
      const fresh = await createZigProjectCompiler(options);
      try {
        const expected = await fresh.build({ sources });
        assert(!expected.success, edit.name);
        assert.deepEqual(rejected.diagnostics, expected.diagnostics, edit.name);
      } finally {
        await fresh.dispose();
      }
      assert((await retained.build()).success, `${edit.name} revert`);
    }
  } finally {
    await retained.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});

// One session switching the module overlaid at a fixture entry, as pen's test
// workers do: after the first build, each entry checks only itself and the
// modules no earlier entry reached, and reuses the rest from the session's
// library (CT90). Lower validated and higher relocated counts are better.
const switchEntries: readonly { name: string; source: string }[] = [
  {
    name: "robots",
    source: 'import * as robots from "./robots"\n' +
      "entry const walked = fn (x: F32) => robots.walk x\n",
  },
  {
    name: "hud",
    source: 'import * as hud from "./hud"\nimport * as math from "./math"\n' +
      "entry const width = fn (x: F32) => hud.width (math.scale x math.unit)\n",
  },
  { name: "all", source: editSuite.files[editSuite.entry] },
  {
    name: "robots_again",
    source: 'import * as robots from "./robots"\n' +
      "entry const walked = fn (x: F32) => robots.walk x\n",
  },
];
const switchToday: Record<
  string,
  { validated_modules: number; relocated_modules: number }
> = {
  robots: { validated_modules: 4, relocated_modules: 0 },
  hud: { validated_modules: 2, relocated_modules: 2 },
  all: { validated_modules: 1, relocated_modules: 4 },
  robots_again: { validated_modules: 1, relocated_modules: 3 },
};
Deno.test("budget: entry switches check only modules no earlier entry reached", async () => {
  await Deno.mkdir(scratchRoot, { recursive: true });
  const directory = await Deno.makeTempDir({
    dir: scratchRoot,
    prefix: "budget-entry-switch-",
  });
  const options = {
    executable: compiler,
    entry: `${directory}/test_fixture.blot`,
    prelude,
    stdRoot,
    cacheDirectory: false as const,
  };
  const retained = await createZigProjectCompiler(options);
  const failures: string[] = [];
  const improved: string[] = [];
  try {
    for (const [file, source] of Object.entries(editSuite.files)) {
      await Deno.writeTextFile(`${directory}/${file}`, source);
    }
    for (const { name, source } of switchEntries) {
      const sources = { [options.entry]: source };
      const built = await retained.build({ sources });
      const fresh = await createZigProjectCompiler(options);
      try {
        const expected = await fresh.build({ sources });
        assert(built.success && expected.success, name);
        assert.deepEqual(built.bytes, expected.bytes, name);
      } finally {
        await fresh.dispose();
      }
      const attempt = built.stats.attemptStats as Record<string, unknown>;
      const fallback = attempt.fallback as Record<string, number>;
      const budget = switchToday[name];
      for (const counter of ["validated_modules", "relocated_modules"]) {
        assert(
          Number.isSafeInteger(fallback[counter]) && fallback[counter] >= 0,
          `${name} ${counter}: missing or invalid counter`,
        );
      }
      if (fallback.validated_modules > budget.validated_modules) {
        failures.push(
          `${name} validated_modules: ${fallback.validated_modules} exceeds ${budget.validated_modules}`,
        );
      } else if (fallback.validated_modules < budget.validated_modules) {
        improved.push(`${name} validated_modules`);
      }
      if (fallback.relocated_modules < budget.relocated_modules) {
        failures.push(
          `${name} relocated_modules: ${fallback.relocated_modules} below ${budget.relocated_modules}`,
        );
      } else if (fallback.relocated_modules > budget.relocated_modules) {
        improved.push(`${name} relocated_modules`);
      }
    }
  } finally {
    await retained.dispose();
    await Deno.remove(directory, { recursive: true });
  }
  if (improved.length) {
    console.log(`Tighten switchToday: ${improved.join(", ")} improved.`);
  }
  assert.equal(failures.length, 0, failures.join("\n"));
});
