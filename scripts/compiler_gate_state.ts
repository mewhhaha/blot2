import { createHash } from "node:crypto";
import { isAbsolute, relative, resolve } from "node:path";
import type { Phase } from "./compiler_phase.ts";

export async function fileDigest(path: string): Promise<string> {
  const hash = createHash("sha256");
  const file = await Deno.open(path);
  for await (const bytes of file.readable) hash.update(bytes);
  return hash.digest("hex");
}

export async function inputDigest(paths: string[]): Promise<string> {
  const hash = createHash("sha256");
  for (const path of [...new Set(paths)].sort()) {
    hash.update(JSON.stringify(path));
    try {
      hash.update(await fileDigest(path));
    } catch (error) {
      if (!(error instanceof Deno.errors.NotFound)) throw error;
      hash.update("missing");
    }
  }
  return hash.digest("hex");
}

async function filesBelow(directory: string): Promise<string[]> {
  const paths: string[] = [];
  for await (const entry of Deno.readDir(directory)) {
    const path = resolve(directory, entry.name);
    if (entry.isDirectory) paths.push(...await filesBelow(path));
    else paths.push(path);
  }
  return paths;
}

async function fixtureFiles(
  directory: string,
  blotOnly = false,
): Promise<string[]> {
  const paths: string[] = [];
  try {
    for await (const entry of Deno.readDir(directory)) {
      const path = resolve(directory, entry.name);
      if (entry.isDirectory) {
        if (
          entry.name === ".zig-cache" || entry.name === ".zig-analyzer" ||
          entry.name.startsWith("zig-out")
        ) continue;
        paths.push(...await fixtureFiles(path, blotOnly));
      } else if (!blotOnly || entry.name.endsWith(".blot")) paths.push(path);
    }
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
    // Presence affects corpus checks, including their skip/fallback behavior.
    paths.push(directory);
  }
  return paths;
}

// Compile inputs and files read by native corpus laws. Keep new runtime fixture
// roots here; test/source changes and this manifest itself invalidate the key.
// Qualification notes and guest-only repairs do not change native evidence.
export async function nativeInputs(root: string): Promise<string[]> {
  const paths = [
    "zig-native/build.zig",
    "zig-native/build.zig.zon",
    "zig-native/compiler_fingerprint.zig",
    "compiler/guide.md",
    "scripts/test_compiler.ts",
    "scripts/compiler_phase.ts",
    "scripts/compiler_gate_state.ts",
  ].map((path) => resolve(root, path));
  // Compilation can import ignored files. Parser corpus laws also read sibling
  // gdev source, including their alternative lookup from a native working dir.
  paths.push(...await fixtureFiles(resolve(root, "zig-native/src")));
  paths.push(...await fixtureFiles(resolve(root, "zig-native/fixtures")));
  for (
    const directory of [
      "std",
      "examples",
      "../gdev/packages",
      "../gdev/src",
      "../../gdev/packages",
      "../../gdev/src",
    ]
  ) {
    paths.push(...await fixtureFiles(resolve(root, directory), true));
  }
  return paths;
}

export async function nativeToolchainFiles(): Promise<string> {
  const result = await new Deno.Command("zig", { args: ["env"] }).output();
  if (!result.success) throw new Error("Cannot identify Zig toolchain");
  const text = new TextDecoder().decode(result.stdout);
  const field = (name: string) => {
    const match = text.match(
      new RegExp(`\\.${name} = ("(?:[^"\\\\]|\\\\.)*")`),
    );
    if (!match) throw new Error(`Missing Zig environment field: ${name}`);
    return JSON.parse(match[1]) as string;
  };
  const paths = [field("zig_exe"), ...await filesBelow(field("lib_dir"))];
  return inputDigest(paths);
}

export async function nativeToolchain(): Promise<string> {
  const hash = createHash("sha256");
  hash.update(await nativeToolchainFiles());
  hash.update(JSON.stringify(Deno.version));
  hash.update(JSON.stringify(Deno.build));
  hash.update(JSON.stringify(Object.entries(Deno.env.toObject()).sort()));
  return hash.digest("hex");
}

type Entry = {
  key: string;
  phase: Phase;
  outputs: Record<string, string>;
};

export class NativeJournal {
  private entries: Record<string, Entry> = {};
  private writes: Promise<void> = Promise.resolve();

  constructor(private path: string) {}

  async load() {
    try {
      const state = JSON.parse(await Deno.readTextFile(this.path));
      if (
        state.version === 1 && state.entries &&
        typeof state.entries === "object"
      ) this.entries = state.entries;
    } catch (error) {
      if (
        !(error instanceof Deno.errors.NotFound) &&
        !(error instanceof SyntaxError)
      ) {
        throw error;
      }
    }
  }

  async reuse(name: string, key: string): Promise<Phase | undefined> {
    const entry = this.entries[name];
    if (!entry || entry.key !== key || entry.phase.code !== 0) return;
    if (name === "native-run" && entry.phase.cache === "hit") return;
    if (!Object.keys(entry.outputs).length) return;
    try {
      for (const [path, digest] of Object.entries(entry.outputs)) {
        if (await fileDigest(path) !== digest) return;
      }
    } catch (error) {
      if (error instanceof Deno.errors.NotFound) return;
      throw error;
    }
    return { ...entry.phase, wall_seconds: 0, cache: "resumed" };
  }

  async record(key: string, phase: Phase, artifacts: string[]) {
    if (phase.code !== 0 || phase.stopped) return;
    // Zig's own run cache contains no execution log. Only a completed run or
    // our separately verified journal may provide reusable native evidence.
    if (phase.name === "native-run" && phase.cache === "hit") return;
    const outputs: Record<string, string> = {};
    for (const path of [...artifacts, phase.stdout, phase.stderr]) {
      outputs[path] = await fileDigest(path);
    }
    this.entries[phase.name] = { key, phase, outputs };
    await this.save();
  }

  async invalidate(name: string) {
    delete this.entries[name];
    await this.save();
  }

  private async save() {
    this.writes = this.writes.then(async () => {
      const temporary = `${this.path}.${Deno.pid}.tmp`;
      await Deno.writeTextFile(
        temporary,
        JSON.stringify({ version: 1, entries: this.entries }, null, 2) + "\n",
      );
      await Deno.rename(temporary, this.path);
    });
    await this.writes;
  }
}

function xmlText(value: string): string {
  return value.replaceAll("&quot;", '"').replaceAll("&apos;", "'")
    .replaceAll("&lt;", "<").replaceAll("&gt;", ">")
    .replaceAll("&amp;", "&");
}

export function failedGuestFiles(xml: string, root: string): string[] {
  const files: string[] = [];
  for (const suite of xml.matchAll(/<testsuite\s+([^>]+)>/g)) {
    const attributes = Object.fromEntries(
      [...suite[1].matchAll(/(\w+)="([^"]*)"/g)].map((
        match,
      ) => [match[1], xmlText(match[2])]),
    );
    if (!(Number(attributes.failures) > 0 || Number(attributes.errors) > 0)) {
      continue;
    }
    const path = relative(root, resolve(root, attributes.name ?? ""));
    if (
      !path.endsWith(".test.ts") || path.startsWith("..") || isAbsolute(path)
    ) continue;
    files.push(path);
  }
  return [...new Set(files)].sort();
}

export async function recentFailures(path: string): Promise<string[]> {
  try {
    const files = JSON.parse(await Deno.readTextFile(path));
    if (!Array.isArray(files)) return [];
    return files.filter((file) =>
      typeof file === "string" && file.endsWith(".test.ts")
    );
  } catch (error) {
    if (error instanceof Deno.errors.NotFound || error instanceof SyntaxError) {
      return [];
    }
    throw error;
  }
}
