// Workloads shared by `bench:compile` and `profile:compile`: the frozen gdev
// snapshot (private source under build/bench/gdev-snapshot, never committed)
// built the way pen builds it, and the retained edit scenarios on it.
import { resolve } from "node:path";
import type { ZigProjectCompilerOptions } from "../../compiler/zig_project_client.ts";
import type { NativeAssetImport } from "../../compiler/native_assets.ts";

export interface Replacement {
  /** Path relative to the workload root. */
  readonly file: string;
  readonly search: string;
  readonly replace: string;
}
/** A retained edit: applied to the populated session, then reverted. */
export interface Scenario {
  readonly name: string;
  readonly replacements: readonly Replacement[];
}
export interface Workload {
  readonly name: string;
  readonly group: "gdev" | "tests" | "synthetic";
  /** Directory holding every source of the workload. */
  readonly root: string;
  readonly entry: string;
  /** Sources every build overlays (absolute path to text), such as a test. */
  readonly overlay: Readonly<Record<string, string>>;
  /** Whether bench:compile also measures a retained session. */
  readonly retained: boolean;
  readonly stdRoot: string | null;
  readonly prelude: string;
  /** Import alias prefix to absolute directory. */
  readonly imports: Readonly<Record<string, string>>;
  readonly nativeAssetRoots: readonly string[] | null;
  readonly nativeAssetImports?: readonly NativeAssetImport[];
  readonly inferenceBudget?: number;
  readonly codegenTier?: "optimized" | "development";
  /** Retained scenarios; an empty list measures population and no-op only. */
  readonly scenarios: readonly Scenario[];
}

/** Project-compiler options opening `workload` with `executable`. */
export function sessionOptions(
  executable: string,
  workload: Workload,
): ZigProjectCompilerOptions {
  return {
    executable,
    entry: workload.entry,
    prelude: workload.prelude,
    ...(workload.stdRoot ? { stdRoot: workload.stdRoot } : {}),
    imports: workload.imports,
    inferenceBudget: workload.inferenceBudget,
    codegenTier: workload.codegenTier,
    ...(workload.nativeAssetRoots
      ? {
        nativeAssets: {
          roots: workload.nativeAssetRoots,
          imports: workload.nativeAssetImports,
        },
      }
      : {}),
  };
}

/** Overlay sources (absolute path to text) for a scenario's edited files. */
export async function editedSources(
  workload: Workload,
  scenario: Scenario,
): Promise<Record<string, string>> {
  const sources: Record<string, string> = {};
  for (const { file, search, replace } of scenario.replacements) {
    const path = `${workload.root}/${file}`;
    const original = sources[path] ?? await Deno.readTextFile(path);
    const at = original.indexOf(search);
    if (at < 0 || original.indexOf(search, at + 1) >= 0) {
      throw new Error(
        `${workload.name} ${scenario.name}: edit anchor must occur exactly once in ${file}: ${
          JSON.stringify(search)
        }`,
      );
    }
    sources[path] = original.slice(0, at) + replace +
      original.slice(at + search.length);
  }
  return sources;
}

/**
 * pen.json paths that point outside the game checkout, and where the snapshot
 * keeps them. The Ink library is frozen inside the snapshot as `ink/`.
 */
const relocated: Readonly<Record<string, string>> = {
  "../ink/lib": "ink",
  "../blot2/std": "std",
};

interface PenSettings {
  readonly imports: Record<string, string>;
  readonly nativeAssetRoots: string[];
  readonly nativeAssetImports: NativeAssetImport[];
  readonly stdRoot?: string;
  readonly inferenceBudget?: number;
  readonly codegenTier?: "optimized" | "development";
}
async function penSettings(snapshotRoot: string): Promise<PenSettings> {
  const pen = JSON.parse(await Deno.readTextFile(`${snapshotRoot}/pen.json`));
  const settings = pen?.compiler?.settings;
  if (!settings?.imports || !Array.isArray(settings.nativeAssets?.roots)) {
    throw new Error(`${snapshotRoot}/pen.json has no compiler settings`);
  }
  const located = (path: string, label: string) => {
    const local = relocated[path.replace(/\/+$/, "")] ?? path;
    const absolute = resolve(snapshotRoot, local);
    if (!absolute.startsWith(`${snapshotRoot}/`)) {
      throw new Error(`${label} ${path} leaves the snapshot; relocate it`);
    }
    return absolute;
  };
  const inside = async (path: string, label: string) => {
    const absolute = located(path, label);
    if (!(await Deno.stat(absolute)).isDirectory) {
      throw new Error(`${label} ${path} is not a snapshot directory`);
    }
    return absolute;
  };
  const imports: Record<string, string> = {};
  for (const [prefix, path] of Object.entries(settings.imports)) {
    imports[prefix] = await inside(String(path), `import ${prefix}`);
  }
  const nativeAssetRoots: string[] = [];
  for (const root of settings.nativeAssets.roots) {
    nativeAssetRoots.push(await inside(String(root), "native asset root"));
  }
  const nativeAssetImports = (settings.nativeAssets.imports ?? []).map((
    item: NativeAssetImport,
  ) => ({
    ...item,
    module: located(String(item.module), "asset module"),
    path: located(String(item.path), "asset input"),
  }));
  const stdRoot = settings.std
    ? await inside(settings.std, "standard library")
    : undefined;
  return {
    imports,
    nativeAssetRoots,
    nativeAssetImports,
    stdRoot,
    inferenceBudget: settings.inferenceBudget,
    codegenTier: settings.codegenTier,
  };
}

/**
 * The retained edit suite on the game entry, one scenario per kind of edit.
 * Anchors must stay unique in the snapshot. scripts/bench/corpus.ts mirrors
 * the suite on a small public project for the reuse budgets.
 */
export const gameScenarios: readonly Scenario[] = [
  {
    name: "trivia",
    replacements: [{
      file: "src/robots.blot",
      search: "const count = 10000\n",
      replace: "// trivia: an added comment line\nconst count = 10000\n",
    }],
  },
  {
    name: "literal_constant",
    replacements: [{
      file: "src/robots.blot",
      search: "const floor_half_extent = 60.0",
      replace: "const floor_half_extent = 61.0",
    }],
  },
  {
    name: "literal_in_body",
    replacements: [{
      file: "src/robots.blot",
      search: "if pose.position.y >= 0.1875 * old_scale:",
      replace: "if pose.position.y >= 0.1876 * old_scale:",
    }],
  },
  {
    name: "body_change",
    replacements: [{
      file: "src/robots.blot",
      search:
        "const walk_material = fn phase => first_material + from (floor phase)",
      replace:
        "const walk_material = fn phase => first_material + from (ceil phase)",
    }],
  },
  {
    name: "type_change",
    replacements: [
      {
        file: "src/robots.blot",
        search:
          "type Carry is data = #Carry { depth: F32, width: F32, height: F32, age: F32, random: U32 }",
        replace:
          "type Carry is data = #Carry { depth: F32, width: F32, height: F32, age: F32, random: U32, spare: F32 }",
      },
      {
        file: "src/robots.blot",
        search: "        random: lanes.join values[5] values[8],\n      }",
        replace:
          "        random: lanes.join values[5] values[8], spare: 0.0,\n      }",
      },
      {
        file: "src/robots.blot",
        search: "      age: 0.0, random: current.random,\n    }",
        replace: "      age: 0.0, random: current.random, spare: 0.0,\n    }",
      },
    ],
  },
  {
    // ink/math is imported by most of the game and the Ink library.
    name: "imported_body",
    replacements: [{
      file: "ink/math.blot",
      search:
        "const Quat.dot: Quat -> Quat -> F32 = fn a => fn b =>\n  a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w",
      replace:
        "const Quat.dot: Quat -> Quat -> F32 = fn a => fn b =>\n  a.w * b.w + a.z * b.z + a.y * b.y + a.x * b.x",
    }],
  },
  {
    // Leaves the Wasm unchanged.
    name: "unused_export",
    replacements: [{
      file: "ink/math.blot",
      search: "const zero2 = #Vec2 { x: 0.0, y: 0.0 }\n",
      replace:
        "const zero2 = #Vec2 { x: 0.0, y: 0.0 }\nconst probe_unused_export = fn (x: F32) => x + 1.0\n",
    }],
  },
];

/** The game and devtools entries, opened with the snapshot's pen.json. */
export async function gdevWorkloads(
  repo: string,
  snapshotRoot: string,
): Promise<Workload[]> {
  const settings = await penSettings(snapshotRoot);
  const workload = (
    name: string,
    entry: string,
    scenarios: readonly Scenario[],
  ): Workload => ({
    name,
    group: "gdev",
    root: snapshotRoot,
    entry: `${snapshotRoot}/${entry}`,
    overlay: {},
    retained: true,
    stdRoot: settings.stdRoot ?? `${repo}/std`,
    prelude: `${settings.stdRoot ?? `${repo}/std`}/prelude.blot`,
    imports: settings.imports,
    nativeAssetRoots: settings.nativeAssetRoots,
    nativeAssetImports: settings.nativeAssetImports,
    inferenceBudget: settings.inferenceBudget,
    codegenTier: settings.codegenTier,
    scenarios,
  });
  return [
    workload("game", "src/main.blot", gameScenarios),
    workload("devtools", "devtools/main.blot", []),
  ];
}

/**
 * Every `tests/*.blot` entry, built as pen builds tests: the game's
 * `src/test_fixture.blot` entry (which exists only as an overlay) holding the
 * test's source, so its relative imports resolve inside `src/`.
 */
export async function testWorkloads(
  repo: string,
  snapshotRoot: string,
): Promise<Workload[]> {
  const [game] = await gdevWorkloads(repo, snapshotRoot);
  const entry = `${snapshotRoot}/src/test_fixture.blot`;
  const names: string[] = [];
  for await (const item of Deno.readDir(`${snapshotRoot}/tests`)) {
    if (item.isFile && item.name.endsWith(".blot")) names.push(item.name);
  }
  const workloads: Workload[] = [];
  for (const name of names.sort()) {
    workloads.push({
      ...game,
      name: `tests/${name}`,
      group: "tests",
      entry,
      overlay: {
        [entry]: await Deno.readTextFile(`${snapshotRoot}/tests/${name}`),
      },
      retained: false,
      scenarios: [],
    });
  }
  return workloads;
}
