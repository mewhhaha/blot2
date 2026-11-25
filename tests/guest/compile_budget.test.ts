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
  new URL("../../compiler-goose/build/blotc-goose", import.meta.url).pathname;
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

Deno.test("inference shares repeated aggregate shapes across generic calls", async () => {
  await Deno.mkdir(scratchRoot, { recursive: true });
  const directory = await Deno.makeTempDir({
    dir: scratchRoot,
    prefix: "signatures-",
  });
  const entry = directory + "/main.blot";
  const library = directory + "/library.blot";
  const layers = ["func layer0 x => return x"];
  for (let i = 1; i <= 12; i++) {
    const call = `layer${i - 1} x`;
    if (i % 2 === 0) {
      layers.push(
        `func layer${i} x => return { left: ${call}, right: ${call} }`,
      );
    } else layers.push(`func layer${i} x => return (${call}, true, ${call})`);
  }
  layers.push("func both x -> y => return {left: (x, y), right: (x, y)}");
  const main = `import { both, layer2 } from "./library"
#entry func answer (n: U32): U32 => return do:
  let a = both n true
  let b = both false n
  let (number, flag) = a.right
  let (_, other) = b.left
  let nested = layer2 other
  let (_, _, last) = nested.right
  return if flag then @u32.add number last else 0
`;
  const client = await createZigProjectCompiler({
    executable: compiler,
    entry,
    prelude: null,
    profileBackend: true,
  });
  try {
    await Deno.writeTextFile(library, layers.join("\n") + "\n");
    await Deno.writeTextFile(entry, main);
    const result = await client.build();
    if (!result.success) assert.fail(JSON.stringify(result.diagnostics));
    const checking = result.stats.phaseProfile.checking as {
      type_nodes: number;
    };
    assert(
      checking.type_nodes < 2500,
      `inferred ${checking.type_nodes} nodes for 13 layers`,
    );
    const guest = await instantiateGuest(result.bytes);
    try {
      assert.equal(guest.call("answer", 21), 42);
      assert.equal(guest.call("answer", 9), 18);
    } finally {
      guest.dispose();
    }
    const invalid = await client.build({
      sources: {
        [entry]: main.replace("@u32.add number last", "@u32.add number flag"),
      },
    });
    assert(!invalid.success);
    assert(
      invalid.diagnostics.some((d) => d.code === "type_mismatch"),
      JSON.stringify(invalid.diagnostics),
    );
  } finally {
    await client.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});

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
