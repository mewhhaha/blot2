// Compile-cost budgets on deterministic work counters, never wall time.
//
// Each synthetic program scales one pattern (see benchmarks/tools/corpus.ts) and
// the compiler reports counters that depend only on the source: type nodes and
// requested allocator bytes. Most budgets are the value measured when set times
// 1.5, so ordinary churn passes while any super-linear regression in checking
// or code generation fails.
//
// When an improvement lowers these counters, re-measure and tighten `today`
// below; a budget that stays loose after an improvement stops guarding against
// regressions.
import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../host/guest.ts";
import {
  chainGeneric,
  chainMono,
  diamond,
  editSuite,
  fanout,
  type SyntheticProgram,
} from "../../benchmarks/tools/corpus.ts";
import {
  createZigProjectCompiler,
  type ZigProjectBuildResult,
} from "../../host/zig_project_client.ts";

const compiler = Deno.args[0] ??
  new URL("../../compiler/zig-out/bin/blotc", import.meta.url).pathname;
const prelude = new URL("../../std/prelude.blot", import.meta.url).pathname;
const stdRoot = new URL("../../std", import.meta.url).pathname;
const scratchRoot = new URL("../../build/tmp/", import.meta.url).pathname;

/** Headroom over the measured value; a later hill should tighten `today`. */
const headroom = 1.5;

interface Measurement {
  success: boolean;
  diagnostic?: { code: string };
  type_nodes: number;
  allocated_bytes: number;
}
/** Counters pinned by a budget. */
type Budgeted = { type_nodes: number; allocated_bytes: number };

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
  Deno.test(`budget: ${program.name} N=${program.size} compiles`, async () => {
    const actual = await measure(program);
    assert(
      actual.success,
      `${program.name} rejected: ${actual.diagnostic?.code}`,
    );
  });
}

// Every retained edit and revert of the edit suite matches a fresh build.
Deno.test("budget: retained edit suite matches fresh builds", async () => {
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
  const record = async (phase: string, result: ZigProjectBuildResult) => {
    assert(result.success, JSON.stringify(result));
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
});

// An edit with a check error reports the diagnostic a fresh build reports, and
// reverting it builds again.
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
Deno.test("budget: retained edits with check errors match fresh diagnostics", async () => {
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
      "entry const walked = func (x: F32) => return robots.walk x\n",
  },
  {
    name: "hud",
    source: 'import * as hud from "./hud"\nimport * as math from "./math"\n' +
      "entry const width = func (x: F32) => return hud.width (math.scale x math.unit)\n",
  },
  { name: "all", source: editSuite.files[editSuite.entry] },
  {
    name: "robots_again",
    source: 'import * as robots from "./robots"\n' +
      "entry const walked = func (x: F32) => return robots.walk x\n",
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
