/** Executed counters from an opt-in --profile-memory module. */
export const memoryProfileMetrics = [
  "allocations",
  "requested_bytes",
  "rounded_bytes",
  "frees",
  "freed_requested_bytes",
  "freed_rounded_bytes",
  "live_bytes",
  "peak_live_bytes",
  "retains",
  "releases",
  "retired_objects",
  "copy_bytes",
  "fill_bytes",
  "read_bytes",
  "write_bytes",
  "cycle_passes",
  "cycle_vertices",
  "cycle_edges",
  "cycle_bytes",
  "cycle_candidates",
  "copy_operations",
  "reused_blocks",
  "fresh_blocks",
] as const;
export type MemoryMetric = typeof memoryProfileMetrics[number];
export type MemoryCounts = Record<MemoryMetric, bigint>;
const memoryProfileCategories = [
  "source",
  "allocation",
  "retirement",
  "roots",
  "cycles",
  "runtime_other",
] as const;
type Site = {
  unit: number;
  node: number;
  start: number;
  end: number;
  filename: string;
  operation: string;
  source_type: string;
  source_blake3: number[] | null;
  inline_context: {
    unit: number;
    node: number;
    start: number;
    end: number;
    filename: string;
  }[];
  inline_depth: number;
  inline_truncated: boolean;
};
type Metadata = {
  version: number;
  base: number;
  counters: number;
  row_bytes: number;
  total_row: number;
  metrics: readonly string[];
  sites: (Omit<Site, "filename" | "source_blake3" | "inline_context"> & {
    inline_context: Omit<Site["inline_context"][number], "filename">[];
  })[];
  sources: { unit: number; filename: string; source_blake3: number[] | null }[];
  reserved_bytes: number;
  categories: string[];
  category_row: number;
  identity: number[];
  compiler_identity: number[] | null;
  aggregation: string;
  cycle_candidate_reason: string;
};

export function readMemoryProfile(
  module: WebAssembly.Module,
  exports: WebAssembly.Exports,
) {
  const sections = WebAssembly.Module.customSections(
    module,
    "blot:memory-profile",
  );
  if (sections.length !== 1) {
    throw new Error("Expected one memory profile section");
  }
  const meta = JSON.parse(
    new TextDecoder("utf-8", { fatal: true }).decode(sections[0]),
  ) as Metadata;
  const memory = exports["blot:memory"];
  if (!(memory instanceof WebAssembly.Memory)) {
    throw new Error("Missing profile memory");
  }
  const view = new DataView(memory.buffer);
  const u32 = (n: number) => Number.isInteger(n) && n >= 0 && n <= 0xffff_ffff;
  const digest = (value: unknown): value is number[] =>
    Array.isArray(value) && value.length === 32 &&
    value.every((n) => Number.isInteger(n) && n >= 0 && n <= 255);
  if (
    meta.version !== 2 || !digest(meta.identity) ||
    (meta.compiler_identity !== null && !digest(meta.compiler_identity)) ||
    !Array.isArray(meta.sites) ||
    !Array.isArray(meta.sources) || meta.sources.length > 327_680 ||
    meta.sites.length > 65_536 ||
    JSON.stringify(meta.metrics) !== JSON.stringify(memoryProfileMetrics) ||
    meta.row_bytes !== memoryProfileMetrics.length * 8 ||
    meta.total_row !== meta.sites.length + 1 || !u32(meta.base) ||
    !u32(meta.counters) || !u32(meta.reserved_bytes) ||
    meta.counters !== meta.base + 16 || meta.base % 16 !== 0 ||
    meta.base + meta.reserved_bytes > view.byteLength ||
    JSON.stringify(meta.categories) !==
      JSON.stringify(memoryProfileCategories) ||
    meta.category_row !== meta.total_row + 1 ||
    meta.counters +
          (meta.category_row + memoryProfileCategories.length) *
            meta.row_bytes >
      meta.base + meta.reserved_bytes
  ) throw new Error("Invalid memory profile geometry");
  const identity = new DataView(Uint8Array.from(meta.identity).buffer);
  for (let word = 0; word < 8; word++) {
    const actual = exports[`blot:profile_identity_${word}`];
    if (
      !(actual instanceof WebAssembly.Global) ||
      (Number(actual.value) >>> 0) !== identity.getUint32(word * 4, true)
    ) {
      throw new Error(
        "Memory profile metadata does not match the live instance",
      );
    }
  }
  const sources = new Map<number, Metadata["sources"][number]>();
  for (const source of meta.sources) {
    if (
      !u32(source.unit) || sources.has(source.unit) ||
      typeof source.filename !== "string" ||
      (source.source_blake3 !== null && !digest(source.source_blake3))
    ) {
      throw new Error("Invalid memory profile source table");
    }
    sources.set(source.unit, source);
  }
  const expandedSites: Site[] = meta.sites.map((site) => {
    const source = sources.get(site.unit);
    if (
      !u32(site.unit) || !u32(site.node) || !u32(site.start) ||
      !u32(site.end) ||
      site.end < site.start || !source ||
      !Array.isArray(site.inline_context) ||
      !u32(site.inline_depth) || site.inline_depth > 4 ||
      site.inline_context.length !== site.inline_depth
    ) throw new Error("Invalid memory profile source site");
    const inline_context = site.inline_context.map((frame) => {
      const caller = sources.get(frame.unit);
      if (
        !caller || !u32(frame.node) || !u32(frame.start) ||
        !u32(frame.end) || frame.end < frame.start
      ) {
        throw new Error("Invalid memory profile inline caller");
      }
      return { ...frame, filename: caller.filename };
    });
    return {
      ...site,
      filename: source.filename,
      source_blake3: source.source_blake3,
      inline_context,
    };
  });
  const row = (index: number): MemoryCounts =>
    Object.fromEntries(
      memoryProfileMetrics.map((name, metric) => [
        name,
        view.getBigUint64(
          meta.counters + index * meta.row_bytes + metric * 8,
          true,
        ),
      ]),
    ) as MemoryCounts;
  const unknown = row(0);
  const sites = expandedSites.map((site, i) => ({
    ...site,
    id: i + 1,
    counts: row(i + 1),
  }));
  const totals = row(meta.total_row);
  const categories = meta.categories.map((name, i) => ({
    name,
    counts: row(meta.category_row + i),
  }));
  const status = view.getUint32(meta.base, true);
  const reconciliationErrors: string[] = [];
  // Per-site peaks occur at different times and must never be added together.
  for (const metric of memoryProfileMetrics) {
    if (metric === "peak_live_bytes") continue;
    const sum = sites.reduce(
      (sum, site) => sum + site.counts[metric],
      unknown[metric],
    );
    if (
      categories.reduce((sum, item) => sum + item.counts[metric], 0n) !==
        totals[metric]
    ) reconciliationErrors.push(`Unreconciled helper category: ${metric}`);
    if (sum !== totals[metric]) {
      reconciliationErrors.push(`Unreconciled memory metric: ${metric}`);
    }
  }
  if (totals.reused_blocks + totals.fresh_blocks !== totals.allocations) {
    reconciliationErrors.push("Allocation outcomes do not reconcile");
  }
  if (
    totals.requested_bytes - totals.freed_requested_bytes !== totals.live_bytes
  ) {
    reconciliationErrors.push(
      "Live bytes do not reconcile with allocation and release traffic",
    );
  }
  if (status === 0 && reconciliationErrors.length) {
    throw new Error(reconciliationErrors.join("; "));
  }
  const hex = (bytes: number[]) =>
    bytes.map((n) => n.toString(16).padStart(2, "0")).join("");
  return {
    version: 1 as const,
    complete: status === 0,
    status,
    reconciliationErrors,
    profileIdentity: hex(meta.identity),
    compilerIdentity: meta.compiler_identity === null
      ? null
      : hex(meta.compiler_identity),
    aggregation: meta.aggregation,
    cycleCandidateReason: meta.cycle_candidate_reason,
    reservedDiagnosticBytes: meta.reserved_bytes,
    committedMemoryBytes: view.byteLength,
    totals,
    unknown,
    sites,
    categories,
  };
}

/** Pin the exact instrumented binary; offsets never identify another module. */
export async function memoryProfileReport(
  bytes: Uint8Array<ArrayBuffer>,
  exports: WebAssembly.Exports,
  expectedWasmSha256?: string,
) {
  const snapshot = readMemoryProfile(new WebAssembly.Module(bytes), exports);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  const wasmSha256 = [...new Uint8Array(digest)].map((n) =>
    n.toString(16).padStart(2, "0")
  ).join("");
  if (expectedWasmSha256 !== undefined && expectedWasmSha256 !== wasmSha256) {
    throw new Error(
      "Wasm hash does not match the pinned memory profile artifact",
    );
  }
  return {
    ...snapshot,
    wasmSha256,
  };
}

export function stringifyMemoryProfile(
  report: Awaited<ReturnType<typeof memoryProfileReport>>,
) {
  return JSON.stringify(
    report,
    (_, value) => typeof value === "bigint" ? value.toString() : value,
    2,
  ) + "\n";
}
