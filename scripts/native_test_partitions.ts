/** Timing hints change placement only; every current inventory item is kept. */
export function nativeTestPartitions(
  inventory: readonly string[],
  shards: number,
  costs?: ReadonlyMap<string, number>,
) {
  if (!Number.isInteger(shards) || shards < 1 || shards > 4) {
    throw new Error("Invalid native shard count");
  }
  const roundRobin = Array.from(
    { length: shards },
    (_, shard) => inventory.filter((_, index) => index % shards === shard),
  );
  const known = inventory.map((name) => costs?.get(name)).filter((
    value,
  ): value is number =>
    value !== undefined && Number.isFinite(value) && value > 0
  ).sort((a, b) => a - b);
  if (known.length === 0 || inventory.length < shards) {
    return {
      groups: roundRobin,
      weighted: false,
      estimated_ns: [] as number[],
    };
  }
  const fallback = known[Math.floor(known.length / 2)];
  const cost = (name: string) => {
    const value = costs?.get(name);
    return value !== undefined && Number.isFinite(value) && value > 0
      ? value
      : fallback;
  };
  const groups: string[][] = Array.from({ length: shards }, () => []);
  const totals = Array.from({ length: shards }, () => 0);
  const ordered = inventory.map((name, index) => ({
    name,
    index,
    ns: cost(name),
  }))
    .sort((a, b) => b.ns - a.ns || a.index - b.index);
  for (const entry of ordered) {
    let target = 0;
    for (let i = 1; i < shards; i++) if (totals[i] < totals[target]) target = i;
    groups[target].push(entry.name);
    totals[target] += entry.ns;
  }
  const originalTotals = roundRobin.map((group) =>
    group.reduce((sum, name) => sum + cost(name), 0)
  );
  if (Math.max(...totals) >= Math.max(...originalTotals)) {
    return {
      groups: roundRobin,
      weighted: false,
      estimated_ns: originalTotals,
    };
  }
  // The executable still runs selected names in its original inventory order.
  const rank = new Map(inventory.map((name, index) => [name, index]));
  for (const group of groups) group.sort((a, b) => rank.get(a)! - rank.get(b)!);
  return { groups, weighted: true, estimated_ns: totals };
}
