// The complete gate always checks every file. Local checks reuse only successful
// results with the same tool, configuration and transitive import contents.
import { fileURLToPath } from "node:url";
import { dirname, isAbsolute, relative, resolve } from "node:path";

const root = fileURLToPath(new URL("../", import.meta.url));
const source = "zig-native/src";
const fixtures = "zig-native/fixtures";
type Graph = Map<string, string[]>;
type Cache = { version: 2; tool: string; passed: Record<string, string[]> };

// A shared allocator/test-helper edit can affect nearly every file. Starting
// hundreds of analyzer processes is slower than the complete directory scan.
export async function checkSelection(
  paths: string[],
  check: (path: string) => Promise<number>,
): Promise<Map<string, number>> {
  const results = new Map<string, number>();
  if (paths.length < 32) {
    for (const path of paths) results.set(path, await check(path));
    return results;
  }
  for (const directory of [source, fixtures]) {
    const members = paths.filter((path) => path.startsWith(directory + "/"));
    if (!members.length) continue;
    const code = await check(directory);
    for (const path of members) results.set(path, code);
  }
  if (results.size !== paths.length) {
    throw new Error("Unclassified Zig lint input");
  }
  return results;
}

function embeddedDirectories(text: string): string[] {
  return [...text.matchAll(/@embedFile\s*\(\s*"([^"\n]+\/)"\s*\+\+/g)].map((
    match,
  ) => match[1]);
}
export function hasOpaqueImports(text: string): boolean {
  const calls = [...text.matchAll(/@(?:import|embedFile)\s*\(/g)];
  const literals = [
    ...text.matchAll(/@(?:import|embedFile)\s*\(\s*"([^"\n]+)"\s*\)/g),
  ];
  return calls.length !== literals.length + embeddedDirectories(text).length ||
    literals.some((match) => match[1].includes("\\")) ||
    embeddedDirectories(text).some((path) => path.includes("\\"));
}

export function importGraph(
  files: Map<string, string>,
  resources: string[] = [],
): Graph {
  const graph: Graph = new Map();
  for (const [path, text] of files) {
    const imports: string[] = [];
    for (
      const match of text.matchAll(
        /@(?:import|embedFile)\s*\(\s*"([^"\n]+)"\s*\)/g,
      )
    ) {
      if (match[1] === "fixtures") {
        imports.push(
          fixtures + "/",
          ...resources.filter((input) => input.startsWith(fixtures + "/")),
        );
        continue;
      }
      if (match[1].endsWith(".zig") || match[0].startsWith("@embedFile")) {
        imports.push(relative(root, resolve(root, dirname(path), match[1])));
      }
    }
    for (const directory of embeddedDirectories(text)) {
      const prefix = relative(root, resolve(root, dirname(path), directory)) +
        "/";
      imports.push(
        prefix,
        ...resources.filter((input) => input.startsWith(prefix)),
      );
    }
    graph.set(path, imports);
  }
  return graph;
}

export function affectedFiles(
  graph: Graph,
  changed: Iterable<string>,
): string[] {
  const affected = new Set(changed);
  for (const path of [...affected]) {
    let directory = dirname(path);
    while (directory !== ".") {
      affected.add(directory + "/");
      directory = dirname(directory);
    }
  }
  const dependents = new Map<string, string[]>();
  for (const [path, imports] of graph) {
    for (const imported of imports) {
      const users = dependents.get(imported) ?? [];
      users.push(path);
      dependents.set(imported, users);
    }
  }
  const queue = [...affected];
  for (let index = 0; index < queue.length; index++) {
    for (const user of dependents.get(queue[index]) ?? []) {
      if (affected.has(user)) continue;
      affected.add(user);
      queue.push(user);
    }
  }
  return [...affected].filter((path) => graph.has(path)).sort();
}

export function dependencyInputs(graph: Graph, path: string): string[] {
  const inputs = new Set([path]);
  const queue = [path];
  for (let index = 0; index < queue.length; index++) {
    for (const imported of graph.get(queue[index]) ?? []) {
      if (inputs.has(imported)) continue;
      inputs.add(imported);
      queue.push(imported);
    }
  }
  return [...inputs].sort();
}

async function digest(bytes: Uint8Array | undefined): Promise<string> {
  if (bytes === undefined) return "missing";
  return Array.from(
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", new Uint8Array(bytes)),
    ),
  )
    .map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
const encoder = new TextEncoder();
async function readOptional(path: string): Promise<Uint8Array | undefined> {
  try {
    return await Deno.readFile(path);
  } catch (error) {
    if (error instanceof Deno.errors.IsADirectory) {
      return encoder.encode(
        JSON.stringify(await sourceFiles(relative(root, path))),
      );
    }
    if (!(error instanceof Deno.errors.NotFound)) throw error;
    return undefined;
  }
}
async function sourceFiles(directory: string): Promise<string[]> {
  const files: string[] = [];
  for await (const item of Deno.readDir(resolve(root, directory))) {
    const path = `${directory}/${item.name}`;
    if (item.isDirectory) files.push(...await sourceFiles(path));
    else if (item.isFile) files.push(path);
  }
  return files.sort();
}
async function fixtureFiles(): Promise<string[]> {
  try {
    return await sourceFiles(fixtures);
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return [];
    throw error;
  }
}
export function changedPaths(status: string): string[] {
  const records = status.split("\0");
  const paths: string[] = [];
  for (let index = 0; index < records.length; index++) {
    const record = records[index];
    if (!record) continue;
    paths.push(record.slice(3));
    if (record.slice(0, 2).includes("R") || record.slice(0, 2).includes("C")) {
      paths.push(records[++index]);
    }
  }
  return paths;
}
async function gitChanges(): Promise<string[]> {
  const result = await new Deno.Command("git", {
    cwd: root,
    args: ["status", "--porcelain=v1", "-z", "--untracked-files=all"],
    stdout: "piped",
    stderr: "piped",
  }).output();
  if (!result.success) throw new Error(new TextDecoder().decode(result.stderr));
  return changedPaths(new TextDecoder().decode(result.stdout));
}

// The analyzer may omit standard-library diagnostics when Zig is unavailable.
// Doctor checks compatibility; zig env (ZON in 0.17) owns resolved tool paths.
async function backendInputs(analyzer: string): Promise<string[]> {
  let doctor: Deno.CommandOutput;
  try {
    doctor = await new Deno.Command(analyzer, {
      cwd: root,
      args: ["doctor"],
      stdout: "piped",
      stderr: "piped",
    }).output();
  } catch (cause) {
    throw new Error(`Zig lint cannot start zig-analyzer at ${analyzer}`, {
      cause,
    });
  }
  if (!doctor.success) {
    const detail = new TextDecoder().decode(doctor.stdout) +
      new TextDecoder().decode(doctor.stderr);
    throw new Error(
      `Zig lint backend unavailable or incompatible; put Zig 0.17.0 on PATH and install a compatible analyzer backend.\n${detail}`,
    );
  }
  const environment = await new Deno.Command("zig", {
    cwd: root,
    args: ["env"],
    stdout: "piped",
    stderr: "piped",
  }).output();
  if (!environment.success) {
    throw new Error(
      `Zig lint cannot resolve Zig: ${
        new TextDecoder().decode(environment.stderr)
      }`,
    );
  }
  const text = new TextDecoder().decode(environment.stdout);
  const field = (name: string): string => {
    const value = text.match(
      new RegExp(String.raw`\.${name}\s*=\s*("(?:[^"\\]|\\.)*")`),
    );
    if (!value) {
      throw new Error(`Zig lint cannot resolve zig env field ${name}`);
    }
    return JSON.parse(value[1]);
  };
  const executable = field("zig_exe");
  const library = resolve(field("lib_dir"), "std");
  try {
    if (!(await Deno.stat(resolve(library, "std.zig"))).isFile) {
      throw new Error("Not a file");
    }
  } catch (cause) {
    throw new Error(`Zig lint standard library unavailable at ${library}`, {
      cause,
    });
  }
  let extension = "";
  if (executable.endsWith(".exe")) extension = ".exe";
  const analyzerDirectory = dirname(
    await Deno.realPath(resolve(root, analyzer)),
  );
  const directories = [
    resolve(analyzerDirectory, "../libexec/zig-analyzer"),
    resolve(analyzerDirectory, "../backend"),
    resolve(root, "zig-out/backend"),
  ];
  const backends = directories.flatMap((directory, index) => {
    let binary = resolve(directory, `bin/zig${extension}`);
    if (index === 0) binary = resolve(directory, `zig${extension}`);
    return [binary, resolve(directory, "zig-analyzer-backend.json")];
  });
  return [executable, ...await sourceFiles(library), ...backends];
}

export async function lint(args: string[]): Promise<number> {
  const analyzer = Deno.env.get("ZIG_ANALYZER") ??
    resolve(root, "../zig-analyzer/zig-out/bin/zig-analyzer");
  const backend = await backendInputs(analyzer);
  async function check(path: string, quiet = false): Promise<number> {
    try {
      const result = await new Deno.Command(analyzer, {
        cwd: root,
        args: ["check", path],
        stdout: "piped",
        stderr: "piped",
      }).output();
      if (!quiet || !result.success) {
        await Deno.stdout.write(result.stdout);
        await Deno.stderr.write(result.stderr);
      }
      return result.code;
    } catch (error) {
      if (!(error instanceof Deno.errors.NotFound)) throw error;
      throw new Error(
        `zig-analyzer not found at ${analyzer}; build it or set ZIG_ANALYZER`,
      );
    }
  }
  if (args.length === 0) {
    const result = await check(source);
    if (result !== 0) return result;
    if ((await fixtureFiles()).length !== 0) return await check(fixtures);
    return 0;
  }
  if (args[0] !== "--changed" && args[0] !== "--files") {
    throw new Error("Usage: lint_zig.ts [--changed | --files path...]");
  }
  if (
    args[0] === "--changed" && args.length !== 1 ||
    args[0] === "--files" && args.length < 2
  ) {
    throw new Error("Usage: lint_zig.ts [--changed | --files path...]");
  }
  let changed: string[];
  if (args[0] === "--changed") {
    changed = await gitChanges();
  } else {
    changed = args.slice(1).map((path) =>
      relative(root, resolve(Deno.cwd(), path))
    );
    for (const path of changed) {
      if (isAbsolute(path) || path.startsWith("../")) {
        throw new Error(`File outside repository: ${path}`);
      }
    }
  }
  const resources = [...await sourceFiles(source), ...await fixtureFiles()];
  const files = resources.filter((path) => path.endsWith(".zig"));
  const contents = new Map(
    await Promise.all(
      files.map(async (path) =>
        [path, await Deno.readFile(resolve(root, path))] as const
      ),
    ),
  );
  const texts = new Map(
    [...contents].map((
      [path, bytes],
    ) => [path, new TextDecoder().decode(bytes)]),
  );
  if (
    [...texts].some(([path, text]) =>
      path !== fixtures + "/root.zig" && hasOpaqueImports(text)
    )
  ) {
    console.log(
      "Computed or escaped Zig imports require a complete lint check.",
    );
    return await lint([]);
  }
  const graph = importGraph(texts, resources);
  const configuration = [
    "zig-native/.zig-version",
    "zig-native/build.zig",
    "zig-native/build.zig.zon",
    ".zig-analyzer.json",
    "zig-analyzer.json",
    ".zig-analyzer/config.json",
    "scripts/lint_zig.ts",
  ];
  let selected = affectedFiles(graph, changed);
  if (changed.some((path) => configuration.includes(path))) selected = files;
  const toolInputs = await Promise.all(
    [analyzer, ...backend, ...configuration.map((path) => resolve(root, path))]
      .map(async (path) => [path, await digest(await readOptional(path))]),
  );
  const tool = await digest(encoder.encode(JSON.stringify(toolInputs)));
  const cachePath = resolve(root, ".zig-cache/lint-zig.json");
  let cache: Cache = { version: 2, tool, passed: {} };
  try {
    const prior = JSON.parse(await Deno.readTextFile(cachePath));
    if (
      prior.version === 2 && prior.tool === tool &&
      typeof prior.passed === "object" && prior.passed !== null &&
      Object.values(prior.passed).every((stamps) =>
        Array.isArray(stamps) &&
        stamps.every((stamp) => typeof stamp === "string")
      )
    ) cache = prior;
  } catch (error) {
    if (
      !(error instanceof Deno.errors.NotFound) &&
      !(error instanceof SyntaxError)
    ) throw error;
  }
  const inputs = new Set(
    selected.flatMap((path) => dependencyInputs(graph, path)),
  );
  const digests = new Map(
    await Promise.all(
      [...inputs].map(async (path) =>
        [
          path,
          await digest(
            contents.get(path) ?? await readOptional(resolve(root, path)),
          ),
        ] as const
      ),
    ),
  );
  const completed = new Map<string, string>();
  const pending = new Map<string, string>();
  let checked = 0;
  let reused = 0;
  let failure = 0;
  for (const path of selected) {
    const stamp = await digest(
      encoder.encode(JSON.stringify(
        dependencyInputs(graph, path)
          .map((input) => [input, digests.get(input)]),
      )),
    );
    if (cache.passed[path]?.includes(stamp)) {
      cache.passed[path] = [
        ...cache.passed[path].filter((old) => old !== stamp),
        stamp,
      ];
      reused++;
      continue;
    }
    pending.set(path, stamp);
  }
  if (pending.size >= 32) {
    console.log(
      `Checking ${pending.size} affected files in directory batches.`,
    );
  }
  const results = await checkSelection(
    [...pending.keys()],
    (path) => check(path, pending.size < 32),
  );
  for (const [path, stamp] of pending) {
    checked++;
    const code = results.get(path)!;
    if (code === 0) {
      completed.set(path, stamp);
    } else {
      delete cache.passed[path];
      failure = code;
    }
  }
  // An editor may save during lint. Cache only the exact snapshot checked.
  const observed = new Map(
    await Promise.all([
      ...new Set(
        [...completed.keys()].flatMap((path) => dependencyInputs(graph, path)),
      ),
    ].map(async (path) =>
      [path, await digest(await readOptional(resolve(root, path)))] as const
    )),
  );
  for (const [path, stamp] of completed) {
    if (
      dependencyInputs(graph, path).every((input) =>
        observed.get(input) === digests.get(input)
      )
    ) {
      cache.passed[path] = [
        ...(cache.passed[path] ?? []).filter((old) => old !== stamp),
        stamp,
      ].slice(-2);
    } else delete cache.passed[path];
  }
  for (const path of Object.keys(cache.passed)) {
    if (!graph.has(path)) delete cache.passed[path];
  }
  await Deno.mkdir(dirname(cachePath), { recursive: true });
  const temporary = await Deno.makeTempFile({
    dir: dirname(cachePath),
    prefix: "lint-zig-",
  });
  try {
    await Deno.writeTextFile(temporary, JSON.stringify(cache));
    await Deno.rename(temporary, cachePath);
  } finally {
    try {
      await Deno.remove(temporary);
    } catch (error) {
      if (!(error instanceof Deno.errors.NotFound)) throw error;
    }
  }
  console.log(
    `Local Zig lint: ${checked} checked, ${reused} unchanged results reused (${selected.length}/${files.length} files selected).`,
  );
  return failure;
}

if (import.meta.main) Deno.exit(await lint(Deno.args));
