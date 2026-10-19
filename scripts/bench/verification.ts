import type { Workload } from "./gdev.ts";

export interface BuildFailure {
  workload: string;
  phase: string;
  variant: string;
  code: string;
}

/** Output parity is checked separately, including a restart's diagnostic code. */
export function unexpectedBuildFailures(
  failures: readonly BuildFailure[],
  workloads: readonly Pick<Workload, "name" | "group">[],
  expectedRejections: ReadonlySet<string>,
  unrecorded: ReadonlySet<string>,
): string[] {
  return failures.filter((failure) => {
    const workload = workloads.find((w) => w.name === failure.workload);
    const known = workload?.group === "tests" &&
      (expectedRejections.has(workload.name) || unrecorded.has(workload.name));
    return !known ||
      !["fresh", "shared", "restart"].includes(failure.phase);
  }).map((failure) =>
    `${failure.workload} ${failure.phase}: ${failure.variant} failed with ${failure.code}`
  );
}

export interface CpuSample {
  workload: string;
  phase: string;
  variant: string;
  run: number;
  cpu_ms: number;
  failure?: unknown;
}

/** CT93: compare the game in matching alternating rounds, using child CPU. */
export function pairedCpuGuard(samples: readonly CpuSample[]) {
  const pairs = new Map<number, Map<string, number>>();
  const problems: string[] = [];
  for (const sample of samples) {
    if (sample.workload !== "game" || sample.phase !== "fresh") continue;
    if (!["baseline", "candidate"].includes(sample.variant)) continue;
    if (
      !Number.isSafeInteger(sample.run) || sample.run < 0 || sample.failure ||
      !Number.isFinite(sample.cpu_ms) || sample.cpu_ms <= 0
    ) {
      problems.push(
        "CPU guard: game fresh samples must succeed with positive finite CPU",
      );
      continue;
    }
    const pair = pairs.get(sample.run) ?? new Map<string, number>();
    if (pair.has(sample.variant)) {
      problems.push(
        `CPU guard: duplicate ${sample.variant} in round ${sample.run}`,
      );
    }
    pair.set(sample.variant, sample.cpu_ms);
    pairs.set(sample.run, pair);
  }
  const ratios: number[] = [];
  for (const [run, pair] of [...pairs].sort(([a], [b]) => a - b)) {
    if (pair.size !== 2) {
      problems.push(`CPU guard: incomplete game pair in round ${run}`);
      continue;
    }
    ratios.push(pair.get("candidate")! / pair.get("baseline")!);
  }
  if (ratios.length < 3) {
    problems.push("CPU guard: at least three complete game pairs are required");
  }
  const ordered = [...ratios].sort((a, b) => a - b);
  const middle = Math.floor(ordered.length / 2);
  const median = !ordered.length
    ? null
    : ordered.length % 2
    ? ordered[middle]
    : (ordered[middle - 1] + ordered[middle]) / 2;
  if (median !== null && median > 1.05) {
    problems.push(
      `CPU guard: game fresh CPU regressed ${
        ((median - 1) * 100).toFixed(2)
      }% (limit 5%)`,
    );
  }
  return { limit: 1.05, paired_ratios: ratios, median_ratio: median, problems };
}
