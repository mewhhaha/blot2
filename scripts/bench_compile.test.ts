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
