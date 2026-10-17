// Workloads shared by `bench:compile` and `profile:compile`: the frozen gdev
// snapshot (private source under build/bench/gdev-snapshot, never committed)
// built the way pen builds it, and the retained edit scenarios on it.
import { resolve } from "node:path";
import type { ZigProjectCompilerOptions } from "../../compiler/zig_project_client.ts";

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
  readonly group: "gdev" | "synthetic";
  /** Directory holding every source of the workload. */
  readonly root: string;
  readonly entry: string;
  readonly stdRoot: string | null;
  readonly prelude: string;
  /** Import alias prefix to absolute directory. */
  readonly imports: Readonly<Record<string, string>>;
  readonly nativeAssetRoots: readonly string[] | null;
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
    ...(workload.nativeAssetRoots
      ? { nativeAssets: { roots: workload.nativeAssetRoots } }
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
const relocated: Readonly<Record<string, string>> = { "../ink/lib/": "ink/" };

interface PenSettings {
  readonly imports: Record<string, string>;
  readonly nativeAssetRoots: string[];
}
async function penSettings(snapshotRoot: string): Promise<PenSettings> {
  const pen = JSON.parse(await Deno.readTextFile(`${snapshotRoot}/pen.json`));
  const settings = pen?.compiler?.settings;
  if (!settings?.imports || !Array.isArray(settings.nativeAssets?.roots)) {
    throw new Error(`${snapshotRoot}/pen.json has no compiler settings`);
  }
  const inside = async (path: string, label: string) => {
    const local = relocated[path] ?? path;
    const absolute = resolve(snapshotRoot, local);
    if (!absolute.startsWith(`${snapshotRoot}/`)) {
      throw new Error(`${label} ${path} leaves the snapshot; relocate it`);
    }
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
  return { imports, nativeAssetRoots };
}

/** Retained edits on the game entry. Anchors must stay unique in the snapshot. */
export const gameScenarios: readonly Scenario[] = [
  {
    name: "literal_constant",
    replacements: [{
      file: "src/robots.blot",
      search: "const floor_half_extent = 60.0",
      replace: "const floor_half_extent = 61.0",
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
    stdRoot: `${repo}/std`,
    prelude: `${repo}/std/prelude.blot`,
    imports: settings.imports,
    nativeAssetRoots: settings.nativeAssetRoots,
    scenarios,
  });
  return [
    workload("game", "src/main.blot", gameScenarios),
    workload("devtools", "devtools/main.blot", []),
  ];
}
