import { strict as assert } from "node:assert";
import {
  type BuildFailure,
  type CpuSample,
  pairedCpuGuard,
  unexpectedBuildFailures,
} from "./bench/verification.ts";

const entry = "tests/rejected.blot";
const phases = ["fresh", "shared", "restart"];
const failures: BuildFailure[] = phases.flatMap((phase) =>
  ["baseline", "candidate"].map((variant) => ({
    workload: entry,
    phase,
    variant,
    code: "type_mismatch",
  }))
);

Deno.test("bench: recorded test rejections remain expected after restart", () => {
  assert.deepEqual(
    unexpectedBuildFailures(
      failures,
      [{ name: entry, group: "tests" }],
      new Set([entry]),
      new Set(),
    ),
    [],
  );
});

function cpuPairs(ratios: number[]): CpuSample[] {
  return ratios.flatMap((ratio, run) => [
    { workload: "game", phase: "fresh", variant: "baseline", run, cpu_ms: 100 },
    {
      workload: "game",
      phase: "fresh",
      variant: "candidate",
      run,
      cpu_ms: 100 * ratio,
    },
  ]);
}

Deno.test("CPU guard permits five percent and rejects a larger regression", () => {
  assert.deepEqual(pairedCpuGuard(cpuPairs([1.05, 1.05, 1.05])).problems, []);
  assert.match(
    pairedCpuGuard(cpuPairs([1.06, 1.07, 1.06])).problems.join(),
    /regressed.*limit 5%/,
  );
});

Deno.test("CPU guard pairs rounds before taking the median and tolerates one noisy pair", () => {
  const samples = cpuPairs([1.02, 1.01, 1.5]);
  for (const sample of samples) if (sample.run === 1) sample.cpu_ms *= 10;
  const result = pairedCpuGuard(samples.reverse());
  assert.equal(result.median_ratio, 1.02);
  assert.deepEqual(result.problems, []);
});

Deno.test("CPU guard refuses missing, duplicate, failed and invalid samples", () => {
  assert(pairedCpuGuard(cpuPairs([1, 1])).problems.length);
  assert(
    pairedCpuGuard(cpuPairs([1, 1, 1]).slice(1)).problems.some((p) =>
      p.includes("incomplete")
    ),
  );
  const duplicate = cpuPairs([1, 1, 1]);
  assert(
    pairedCpuGuard([...duplicate, duplicate[0]]).problems.some((p) =>
      p.includes("duplicate")
    ),
  );
  for (const cpu_ms of [0, -1, NaN, Infinity]) {
    const samples = cpuPairs([1, 1, 1]);
    samples[0].cpu_ms = cpu_ms;
    assert(
      pairedCpuGuard(samples).problems.some((p) =>
        p.includes("positive finite")
      ),
    );
  }
  const failed = cpuPairs([1, 1, 1]);
  failed[0].failure = { code: "type_mismatch" };
  assert(
    pairedCpuGuard(failed).problems.some((p) => p.includes("must succeed")),
  );
});

Deno.test("CPU guard uses only fresh game pairs, never wall or retained timings", () => {
  const extra = cpuPairs([10, 10, 10]).map((s) => ({
    ...s,
    phase: "population",
  }));
  assert.deepEqual(
    pairedCpuGuard([...cpuPairs([1, 1, 1]), ...extra]).problems,
    [],
  );
  assert(pairedCpuGuard(extra).problems.length);
});

Deno.test("bench: unrecorded test rejections allow fresh, shared and restart phases", () => {
  assert.deepEqual(
    unexpectedBuildFailures(
      failures,
      [{ name: entry, group: "tests" }],
      new Set(),
      new Set([entry]),
    ),
    [],
  );
});

Deno.test("bench: a recorded successful test cannot start rejecting", () => {
  assert.equal(
    unexpectedBuildFailures(
      failures,
      [{ name: entry, group: "tests" }],
      new Set(),
      new Set(),
    ).length,
    failures.length,
  );
});

Deno.test("bench: known test rejection does not excuse a retained edit failure", () => {
  assert.deepEqual(
    unexpectedBuildFailures(
      [{ ...failures[0], phase: "edit:body_change" }],
      [{ name: entry, group: "tests" }],
      new Set([entry]),
      new Set(),
    ),
    [`${entry} edit:body_change: baseline failed with type_mismatch`],
  );
});

Deno.test("bench: game and synthetic failures are never expected test rejections", () => {
  for (const group of ["gdev", "synthetic"] as const) {
    assert.equal(
      unexpectedBuildFailures(
        failures,
        [{ name: entry, group }],
        new Set([entry]),
        new Set([entry]),
      ).length,
      failures.length,
    );
  }
});

Deno.test("bench: phase coverage uses elapsed wall and rejects missing or overlapping clocks", async () => {
  const { phaseCoverage, costSummary } = await import("./bench/costs.ts");
  const profile = {
    total_us: 1000,
    phases: { other: { us: 100 }, backend: { us: 900 } },
  };
  assert.equal(phaseCoverage(profile).named_wall_ratio, 0.9);
  assert.throws(
    () => phaseCoverage({ ...profile, total_us: 500 }),
    /partition/,
  );
  assert.throws(() => phaseCoverage({ total_us: 1000, phases: {} }), /invalid/);
  const [summary] = costSummary([{
    workload: "game",
    variant: "candidate",
    phase: "fresh",
    cpu_ms: 4,
    wall_ms: 1.2,
    peak_rss_kib: 1024,
    stats: {
      phaseProfile: profile,
      backendTiming: {
        generate_us: 800,
        work: {
          inference_us: 600,
          constants_us: 200,
          semantic_job_sum_us: 2000,
        },
      },
    },
  }]);
  assert.equal(summary.phase_coverage[0].named_wall_ratio, 0.9);
  assert.equal(summary.cpu_ms.median, 4);
  assert.equal(summary.backend_work_wall_ms?.inference_us.median, 0.6);
  assert(!Object.hasOwn(summary.backend_work_wall_ms!, "semantic_job_sum_us"));
});

Deno.test("bench: frozen pen settings preserve budget, standard library and explicit text assets", async () => {
  const { gdevWorkloads, sessionOptions } = await import("./bench/gdev.ts");
  const root = await Deno.makeTempDir();
  try {
    for (const name of ["src", "ink", "std"]) {
      await Deno.mkdir(`${root}/${name}`);
    }
    await Deno.writeTextFile(
      `${root}/pen.json`,
      JSON.stringify({
        compiler: {
          settings: {
            imports: { "ink/": "../ink/lib/" },
            std: "../blot2/std",
            inferenceBudget: 200000000,
            codegenTier: "development",
            nativeAssets: {
              roots: ["src"],
              imports: [{
                module: "src/names.json.blot",
                path: "src/names.json",
                kind: "text",
              }],
            },
          },
        },
      }),
    );
    const [game] = await gdevWorkloads("/unused-live-repository", root);
    const options = sessionOptions("/compiler", game);
    assert.equal(options.inferenceBudget, 200000000);
    assert.equal(options.codegenTier, "development");
    assert.equal(options.prelude, `${root}/std/prelude.blot`);
    assert.deepEqual(options.nativeAssets?.imports, [{
      module: `${root}/src/names.json.blot`,
      path: `${root}/src/names.json`,
      kind: "text",
    }]);
    await Deno.remove(`${root}/std`);
    await assert.rejects(() => gdevWorkloads("/unused-live-repository", root));
  } finally {
    await Deno.remove(root, { recursive: true });
  }
});

Deno.test("bench: snapshot pinning rejects same-size edits, additions and symlinks", async () => {
  const { snapshotFiles, verifySnapshotFiles } = await import(
    "./bench/snapshot.ts"
  );
  const root = await Deno.makeTempDir();
  try {
    await Deno.writeTextFile(`${root}/source`, "one");
    const pins = await snapshotFiles(root);
    await Deno.writeTextFile(`${root}/source`, "two");
    await assert.rejects(() => verifySnapshotFiles(root, pins), /changed/);
    await Deno.writeTextFile(`${root}/source`, "one");
    await Deno.writeTextFile(`${root}/new`, "extra");
    await assert.rejects(() => verifySnapshotFiles(root, pins), /changed/);
    await Deno.remove(`${root}/new`);
    assert.equal(await verifySnapshotFiles(root, pins), 1);
    await Deno.symlink(`${root}/source`, `${root}/link`);
    await assert.rejects(() => verifySnapshotFiles(root, pins), /symlink/);
  } finally {
    await Deno.remove(root, { recursive: true });
  }
});
