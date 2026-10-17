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

/** A multi-module project with retained edit scenarios. */
export interface SyntheticProject {
  readonly name: string;
  /** Path relative to the project root, to source. */
  readonly files: Readonly<Record<string, string>>;
  readonly entry: string;
  readonly scenarios: readonly {
    readonly name: string;
    readonly replacements: readonly {
      readonly file: string;
      readonly search: string;
      readonly replace: string;
    }[];
  }[];
}

/**
 * The gdev edit suite in miniature: a widely imported math module, a game
 * module with constants, bodies and a data type, a second importer and an
 * entry. Each scenario is one kind of retained edit; the budget test pins how
 * much of the previous revision each one reuses.
 */
export const editSuite: SyntheticProject = {
  name: "edit_suite",
  entry: "main.blot",
  files: {
    "math.blot": lines([
      "type Vec2 is data = #Vec2 { x: F32, y: F32 }",
      "const zero = #Vec2 { x: 0.0, y: 0.0 }",
      "const unit = #Vec2 { x: 1.0, y: 1.0 }",
      "const dot = fn (a: Vec2) => fn (b: Vec2) => a.x * b.x + a.y * b.y",
      "const scale = fn (k: F32) => fn (v: Vec2) => #Vec2 { x: k * v.x, y: k * v.y }",
      "const add = fn (a: Vec2) => fn (b: Vec2) => #Vec2 { x: a.x + b.x, y: a.y + b.y }",
    ]),
    "robots.blot": lines([
      'import * as math from "./math"',
      "type Carry is data = #Carry { depth: F32, width: F32 }",
      "const floor_half_extent = 60.0",
      "const step = fn (carry: Carry) => #Carry { depth: carry.depth + 0.5, width: carry.width }",
      "const reach = fn (v: math.Vec2) => math.dot v v * floor_half_extent",
      "const walk = fn (phase: F32) => floor phase + 1.0",
      "const carried = fn (x: F32) => do:",
      "  let #Carry { depth, width } = step (#Carry { depth: x, width: 1.0 })",
      "  return depth + width",
    ]),
    "hud.blot": lines([
      'import * as math from "./math"',
      "const offset = math.add math.unit (math.scale 2.0 math.zero)",
      "const width = fn (v: math.Vec2) => math.dot v (math.add offset v)",
    ]),
    "main.blot": lines([
      'import * as math from "./math"',
      'import * as robots from "./robots"',
      'import * as hud from "./hud"',
      "entry const score = fn (x: F32) => robots.reach (math.scale x math.unit) + hud.width (math.scale x math.unit)",
      "entry const walked = fn (x: F32) => robots.walk x",
      "entry const carried = fn (x: F32) => robots.carried x",
    ]),
  },
  scenarios: [
    {
      name: "trivia",
      replacements: [{
        file: "robots.blot",
        search: "const floor_half_extent",
        replace: "// trivia: a comment\nconst floor_half_extent",
      }],
    },
    {
      name: "literal_constant",
      replacements: [{
        file: "robots.blot",
        search: "const floor_half_extent = 60.0",
        replace: "const floor_half_extent = 61.0",
      }],
    },
    {
      name: "literal_in_body",
      replacements: [{
        file: "robots.blot",
        search: "carry.depth + 0.5",
        replace: "carry.depth + 0.6",
      }],
    },
    {
      name: "body_change",
      replacements: [{
        file: "robots.blot",
        search: "floor phase + 1.0",
        replace: "ceil phase + 1.0",
      }],
    },
    {
      name: "type_change",
      replacements: [
        {
          file: "robots.blot",
          search: "#Carry { depth: F32, width: F32 }",
          replace: "#Carry { depth: F32, width: F32, spare: F32 }",
        },
        {
          file: "robots.blot",
          search: "width: carry.width }",
          replace: "width: carry.width, spare: 0.0 }",
        },
        {
          file: "robots.blot",
          search: "width: 1.0 })",
          replace: "width: 1.0, spare: 0.0 })",
        },
        {
          file: "robots.blot",
          search: "let #Carry { depth, width }",
          replace: "let #Carry { depth, width, spare }",
        },
      ],
    },
    {
      name: "imported_body",
      replacements: [{
        file: "math.blot",
        search: "a.x * b.x + a.y * b.y",
        replace: "a.y * b.y + a.x * b.x",
      }],
    },
    {
      name: "unused_export",
      replacements: [{
        file: "math.blot",
        search: "const unit =",
        replace: "const probe_unused = fn (x: F32) => x + 1.0\nconst unit =",
      }],
    },
  ],
};

/** Programs whose counters are budgeted today. */
export const syntheticCorpus: readonly SyntheticProgram[] = [
  chainMono(128),
  chainGeneric(64),
  diamond(8),
  fanout(128),
];
