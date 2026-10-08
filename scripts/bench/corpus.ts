// Synthetic compile-cost corpus shared by the budget test and `bench:compile`.
// Each generator scales one structural pattern so super-linear behaviour in
// instantiation, region collection or solving shows up in deterministic
// compiler work counters long before it shows up in wall time.

export interface SyntheticProgram {
  /** Stable identifier used in budgets and result files. */
  readonly name: string;
  readonly size: number;
  readonly source: string;
  /** One-occurrence source edit used by retained-session phases. */
  readonly edit: { readonly search: string; readonly replace: string };
}

const lines = (rows: readonly string[]): string => rows.join("\n") + "\n";

/** Annotated chain: every link is monomorphic, so each call is closed. */
export function chainMono(size: number): SyntheticProgram {
  const rows = ["const f_0 = fn (x: U32) -> U32 => x + 1"];
  for (let i = 1; i <= size; i++) {
    rows.push(`const f_${i} = fn (x: U32) -> U32 => f_${i - 1} x + 1`);
  }
  rows.push(`entry const main = fn (x: U32) -> U32 => f_${size} x`);
  return {
    name: "chain_mono",
    size,
    source: lines(rows),
    edit: {
      search: "const f_0 = fn (x: U32) -> U32 => x + 1",
      replace: "const f_0 = fn (x: U32) -> U32 => x + 2",
    },
  };
}

/** The same chain without annotations: every link is generic. */
export function chainGeneric(size: number): SyntheticProgram {
  const rows = ["const f_0 = fn x => x + 1"];
  for (let i = 1; i <= size; i++) {
    rows.push(`const f_${i} = fn x => f_${i - 1} x + 1`);
  }
  rows.push(`entry const main = fn (x: U32) -> U32 => f_${size} x`);
  return {
    name: "chain_generic",
    size,
    source: lines(rows),
    edit: {
      search: "const f_0 = fn x => x + 1",
      replace: "const f_0 = fn x => x + 2",
    },
  };
}

/** Each generic link calls its predecessor twice: 2^size paths, size+1 bodies. */
export function diamond(size: number): SyntheticProgram {
  const rows = ["const f_0 = fn x => x + 1"];
  for (let i = 1; i <= size; i++) {
    rows.push(`const f_${i} = fn x => f_${i - 1} (f_${i - 1} x)`);
  }
  rows.push(`entry const main = fn (x: U32) -> U32 => f_${size} x`);
  return {
    name: "diamond",
    size,
    source: lines(rows),
    edit: {
      search: "const f_0 = fn x => x + 1",
      replace: "const f_0 = fn x => x + 2",
    },
  };
}

/** Many independent generic functions, each instantiated at U32 and F32. */
export function fanout(size: number): SyntheticProgram {
  const rows: string[] = [];
  for (let i = 0; i < size; i++) rows.push(`const g_${i} = fn x => x + x`);
  rows.push("entry const main = fn (x: U32) => do:");
  rows.push("  let whole = 0");
  rows.push("  let fraction = 0.0");
  for (let i = 0; i < size; i++) {
    rows.push(`  whole := self + g_${i} x`);
    rows.push(`  fraction := self + g_${i} 1.0`);
  }
  rows.push("  if fraction > 1.0:");
  rows.push("    return whole + 1");
  rows.push("  return whole");
  return {
    name: "fanout",
    size,
    source: lines(rows),
    edit: {
      search: "const g_0 = fn x => x + x",
      replace: "const g_0 = fn x => x + x + x",
    },
  };
}

/** Programs whose counters are budgeted today. */
export const syntheticCorpus: readonly SyntheticProgram[] = [
  chainMono(128),
  chainGeneric(64),
  diamond(8),
  fanout(128),
];
