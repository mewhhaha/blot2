// Clocks here have different scopes: whole-build phases partition elapsed wall
// time; backend work is nested inside them; process CPU includes all workers.
export interface CostSample {
  workload: string;
  variant: string;
  phase: string;
  cpu_ms: number;
  wall_ms: number;
  peak_rss_kib: number;
  stats: Record<string, unknown>;
}
export function spread(values: number[]) {
  if (!values.length || values.some((v) => !Number.isFinite(v) || v < 0)) {
    throw new Error("Measurement requires nonnegative finite samples");
  }
  const sorted = [...values].sort((a, b) => a - b), middle = sorted.length >> 1;
  return {
    samples: values.length,
    median: sorted.length % 2
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2,
    min: sorted[0],
    max: sorted.at(-1)!,
  };
}
export function phaseCoverage(
  profile: { total_us: number; phases: Record<string, { us: number }> },
) {
  const times = Object.values(profile.phases).map((v) => v.us);
  if (
    !times.length || !Number.isFinite(profile.total_us) ||
    profile.total_us <= 0 || times.some((v) => !Number.isFinite(v) || v < 0)
  ) throw new Error("Missing or invalid phase clocks");
  const sum = times.reduce((a, b) => a + b, 0);
  // Each clock is truncated separately to microseconds.
  if (Math.abs(profile.total_us - sum) > times.length + 1) {
    throw new Error(
      "Exclusive phase clocks do not partition their profiled wall interval",
    );
  }
  return {
    accounted_wall_ratio: sum / profile.total_us,
    named_wall_ratio: (sum - (profile.phases.other?.us ?? 0)) /
      profile.total_us,
  };
}
export function costSummary(samples: CostSample[]) {
  const groups = Map.groupBy(
    samples,
    (s) => JSON.stringify([s.workload, s.variant, s.phase]),
  );
  return [...groups.values()].map((group) => {
    const first = group[0];
    const profiled = group.map((s) =>
      s.stats.phaseProfile as Parameters<typeof phaseCoverage>[0] | undefined
    ).filter((p) => p?.phases !== undefined);
    for (const profile of profiled) phaseCoverage(profile!);
    const phases = profiled.length
      ? Object.fromEntries(
        Object.keys(profiled[0]!.phases).map((
          name,
        ) => [name, spread(profiled.map((p) => p!.phases[name].us / 1000))]),
      )
      : null;
    const backends = group.map((s) =>
      s.stats.backendTiming as Record<string, unknown> | undefined
    );
    const clocks = (records: (Record<string, unknown> | undefined)[]) => {
      if (!records.every((v) => v !== undefined)) return null;
      return Object.fromEntries(
        Object.keys(records[0]!).filter((k) =>
          k.endsWith("_us") && k !== "semantic_job_sum_us"
        ).map((
          key,
        ) => [key, spread(records.map((r) => Number(r![key]) / 1000))]),
      );
    };
    return {
      workload: first.workload,
      variant: first.variant,
      phase: first.phase,
      wall_ms: spread(group.map((s) => s.wall_ms)),
      cpu_ms: spread(group.map((s) => s.cpu_ms)),
      peak_rss_mib: spread(group.map((s) => s.peak_rss_kib / 1024)),
      exclusive_phase_wall_ms: phases,
      phase_coverage: profiled.map((p) => phaseCoverage(p!)),
      backend_wall_ms: clocks(backends),
      // Child clocks: do not add these to backend or whole-build clocks.
      backend_work_wall_ms: clocks(
        backends.map((b) => b?.work as Record<string, unknown> | undefined),
      ),
    };
  });
}
