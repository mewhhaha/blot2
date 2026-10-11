import { dirname, isAbsolute, join, relative, resolve } from "node:path";
import { parse } from "jsr:@std/yaml@1.3.0";

type Dependency = string | { path: string };
type Manifest = {
  dependencies: Record<string, Dependency>;
  prelude?: string | null;
};
type Pin = { source: string; ref: string; revision: string };
type Lock = { version: 1; packages: Record<string, Pin> };
type Workspace = { exports: Record<string, string>; prelude?: string };
type Package = { identity: string; root: string; workspace: Workspace };
export type PackageOptions = { cacheDirectory?: string };
export type PackageProject = {
  root: string;
  imports: Record<string, string>;
  prelude: string | null;
  stdRoot: null;
};

function object(value: unknown, label: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${label} must be an object`);
  }
  return value as Record<string, unknown>;
}
function fields(
  value: Record<string, unknown>,
  allowed: string[],
  label: string,
) {
  for (const name of Object.keys(value)) {
    if (!allowed.includes(name)) {
      throw new Error(`${label}: unknown field ${name}`);
    }
  }
}
function text(value: unknown, label: string): string {
  if (typeof value !== "string" || !value || /[\u0000\r\n]/.test(value)) {
    throw new Error(`${label} must be a nonempty string`);
  }
  return value;
}
function name(value: string) {
  if (!/^(?:@[A-Za-z0-9_-]+\/)?[A-Za-z][A-Za-z0-9_-]*$/.test(value)) {
    throw new Error(`Invalid package name: ${value}`);
  }
}
function order(a: string, b: string): number {
  if (a < b) return -1;
  if (a > b) return 1;
  return 0;
}
function contained(boundary: string, target: string): boolean {
  const path = relative(boundary, target);
  return !isAbsolute(path) && path !== ".." && !path.startsWith("../");
}
async function read(
  path: string,
  boundary?: string,
): Promise<string | undefined> {
  try {
    if (boundary && !contained(boundary, await Deno.realPath(path))) {
      throw new Error(`Package configuration escapes its repository: ${path}`);
    }
    const info = await Deno.stat(path);
    if (!info.isFile || info.size > 1024 * 1024) {
      throw new Error(`${path}: expected a file below 1 MiB`);
    }
    return await Deno.readTextFile(path);
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return undefined;
    throw error;
  }
}
async function manifest(
  root: string,
  required = false,
  boundary?: string,
): Promise<Manifest | undefined> {
  const path = join(root, "blot.json"), source = await read(path, boundary);
  if (source === undefined) {
    if (required) throw new Error(`${path}: manifest not found`);
    return;
  }
  const value = object(JSON.parse(source), path);
  fields(value, ["dependencies", "prelude"], path);
  const dependencies: Record<string, Dependency> = Object.create(null);
  for (
    const [alias, input] of Object.entries(
      object(value.dependencies ?? {}, "dependencies"),
    )
  ) {
    name(alias);
    if (typeof input === "string") dependencies[alias] = text(input, alias);
    else {
      const item = object(input, alias);
      fields(item, ["path"], alias);
      dependencies[alias] = { path: text(item.path, `${alias}.path`) };
    }
  }
  const result: Manifest = { dependencies };
  if (value.prelude !== undefined && value.prelude !== null) {
    result.prelude = text(value.prelude, "prelude");
    name(result.prelude);
  }
  return result;
}
function gitSource(input: string): { source: string; ref: string } {
  const split = input.lastIndexOf("#");
  let source = input, ref = "HEAD";
  if (split >= 0) {
    source = input.slice(0, split);
    ref = text(input.slice(split + 1), "Git ref");
  }
  if (source.startsWith("github:")) source = source.slice(7);
  if (/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(source)) {
    source = `https://github.com/${source}.git`;
  }
  if (!/^(?:https?:\/\/|ssh:\/\/|git:\/\/|file:\/\/|git@[^:]+:)/.test(source)) {
    throw new Error(`Expected a Git URL or GitHub owner/repo: ${input}`);
  }
  if (ref.startsWith("-") || /[\s~^:?*\[\\]/.test(ref) || ref.includes("..")) {
    throw new Error(`Invalid Git ref: ${ref}`);
  }
  return { source, ref };
}
async function hash(value: string): Promise<string> {
  return [
    ...new Uint8Array(
      await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)),
    ),
  ].map(
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}
function cacheRoot(options: PackageOptions): string {
  if (options.cacheDirectory) return resolve(options.cacheDirectory);
  const custom = Deno.env.get("BPM_CACHE_DIR");
  if (custom) return resolve(custom);
  const xdg = Deno.env.get("XDG_CACHE_HOME");
  if (xdg) return resolve(xdg, "bpm");
  const home = Deno.env.get("HOME");
  if (!home) throw new Error("Set BPM_CACHE_DIR or pass --cache DIR");
  return resolve(home, ".cache", "bpm");
}
async function git(args: string[]): Promise<string> {
  const process = await new Deno.Command("git", {
    args,
    stdin: "null",
    stdout: "piped",
    stderr: "piped",
  }).output();
  if (!process.success) {
    throw new Error(
      new TextDecoder().decode(process.stderr).trim() || "Git failed",
    );
  }
  return new TextDecoder().decode(process.stdout).trim();
}
async function checkoutPath(cache: string, pin: Pin): Promise<string> {
  return join(
    cache,
    "packages",
    await hash(`${pin.source}\u0000${pin.revision}`),
  );
}
async function cached(cache: string, pin: Pin): Promise<string | undefined> {
  const folder = await checkoutPath(cache, pin);
  const metadata = await read(join(folder, "package.json"));
  if (metadata === undefined) return;
  const info = object(JSON.parse(metadata), "cached package");
  if (info.source !== pin.source || info.revision !== pin.revision) {
    throw new Error(`Invalid BPM cache entry: ${folder}`);
  }
  const root = join(folder, "source");
  const head = await read(join(root, ".git", "HEAD"));
  if (head?.trim() !== pin.revision) {
    throw new Error(`Changed BPM checkout: ${root}`);
  }
  const changes = await git([
    "-c",
    "core.fsmonitor=false",
    "-c",
    "core.untrackedCache=false",
    "-C",
    root,
    "status",
    "--porcelain=v1",
    "--untracked-files=all",
    "--ignored=matching",
  ]);
  if (changes) throw new Error(`Changed BPM checkout: ${root}`);
  return root;
}
async function download(
  cache: string,
  source: string,
  ref: string,
  revision?: string,
): Promise<{ pin: Pin; root: string }> {
  await Deno.mkdir(join(cache, "packages"), { recursive: true });
  const staging = await Deno.makeTempDir({
    dir: join(cache, "packages"),
    prefix: ".install-",
  });
  try {
    const root = join(staging, "source");
    const target = revision ?? ref;
    let format = "sha1";
    if (/^[a-f0-9]{64}$/.test(target)) format = "sha256";
    async function fetch() {
      await git(["init", "--quiet", `--object-format=${format}`, root]);
      await git([
        "-C",
        root,
        "fetch",
        "--quiet",
        "--depth=1",
        "--no-tags",
        "--",
        source,
        target,
      ]);
    }
    try {
      await fetch();
    } catch (error) {
      if (
        format !== "sha1" || !(error instanceof Error) ||
        !error.message.includes(
          "mismatched algorithms: client sha1; server sha256",
        )
      ) throw error;
      await Deno.remove(root, { recursive: true });
      format = "sha256";
      await fetch();
    }
    const commit = await git([
      "-C",
      root,
      "rev-parse",
      "--verify",
      "FETCH_HEAD^{commit}",
    ]);
    if (
      !/^(?:[a-f0-9]{40}|[a-f0-9]{64})$/.test(commit) ||
      revision && commit !== revision
    ) {
      throw new Error("Git did not return the pinned revision");
    }
    const pin: Pin = { source, ref, revision: commit };
    const existing = await cached(cache, pin);
    if (existing) return { pin, root: existing };
    await git(["-C", root, "checkout", "--quiet", "--detach", commit]);
    await workspace(root);
    await Deno.writeTextFile(
      join(staging, "package.json"),
      JSON.stringify({ source, revision: commit }),
    );
    const destination = await checkoutPath(cache, pin);
    try {
      await Deno.rename(staging, destination);
    } catch (error) {
      const winner = await cached(cache, pin);
      if (!winner) throw error;
      return { pin, root: winner };
    }
    return { pin, root: join(destination, "source") };
  } finally {
    await Deno.remove(staging, { recursive: true }).catch((error) => {
      if (!(error instanceof Deno.errors.NotFound)) throw error;
    });
  }
}
async function inside(
  root: string,
  path: string,
  directory: boolean,
): Promise<string> {
  text(path, "export path");
  if (isAbsolute(path) || path.includes("\\")) {
    throw new Error(`Package paths must be relative: ${path}`);
  }
  const boundary = await Deno.realPath(root);
  const target = await Deno.realPath(resolve(root, path));
  if (!contained(boundary, target)) {
    throw new Error(`Package export escapes its workspace: ${path}`);
  }
  const info = await Deno.stat(target);
  if (directory && !info.isDirectory || !directory && !info.isFile) {
    throw new Error(`Invalid package export: ${path}`);
  }
  if (!directory && !target.endsWith(".blot")) {
    throw new Error("Prelude must be a .blot file");
  }
  return target;
}
async function workspace(root: string): Promise<Workspace> {
  const filename = join(root, "blot-workspace.yaml"),
    source = await read(filename, await Deno.realPath(root));
  if (source === undefined) {
    throw new Error(`${filename}: package must declare its exports`);
  }
  const value = object(
    parse(source, { schema: "core", allowDuplicateKeys: false }),
    filename,
  );
  fields(value, ["name", "exports", "prelude"], filename);
  if (value.name !== undefined) text(value.name, "workspace name");
  const exports: Record<string, string> = Object.create(null);
  for (
    const [key, input] of Object.entries(
      object(value.exports, "workspace exports"),
    )
  ) {
    if (key !== "." && !/^[A-Za-z][A-Za-z0-9_-]*$/.test(key)) {
      throw new Error(`Invalid export name: ${key}`);
    }
    exports[key] = await inside(root, text(input, key), true);
  }
  if (!Object.keys(exports).length) {
    throw new Error("Workspace must export at least one directory");
  }
  const result: Workspace = { exports };
  if (value.prelude !== undefined) {
    result.prelude = await inside(
      root,
      text(value.prelude, "workspace prelude"),
      false,
    );
  }
  return result;
}
async function readLock(root: string): Promise<Lock | undefined> {
  const path = join(root, "blot.lock.json"), source = await read(path);
  if (source === undefined) return;
  const value = object(JSON.parse(source), path);
  fields(value, ["version", "packages"], path);
  if (value.version !== 1) throw new Error(`${path}: unsupported lock version`);
  const packages: Record<string, Pin> = Object.create(null);
  for (
    const [alias, input] of Object.entries(
      object(value.packages, "locked packages"),
    )
  ) {
    name(alias);
    const item = object(input, alias);
    fields(item, ["source", "ref", "revision"], alias);
    const pin = {
      source: text(item.source, "source"),
      ref: text(item.ref, "ref"),
      revision: text(item.revision, "revision"),
    };
    if (!/^(?:[a-f0-9]{40}|[a-f0-9]{64})$/.test(pin.revision)) {
      throw new Error(`Invalid locked revision: ${alias}`);
    }
    packages[alias] = pin;
  }
  return { version: 1, packages };
}
async function graph(
  root: string,
  input: Manifest,
  options: PackageOptions,
  mode: "resolve" | "install" | "update",
  frozen: boolean,
) {
  const old = await readLock(root);
  const lock: Lock = { version: 1, packages: Object.create(null) };
  const packages = new Map<string, Package>();
  async function visit(
    owner: string,
    dependencies: Record<string, Dependency>,
    boundary?: string,
  ) {
    for (
      const [alias, dependency] of Object.entries(dependencies).sort((
        [a],
        [b],
      ) => order(a, b))
    ) {
      let identity: string, directory: string;
      let childBoundary = boundary;
      if (typeof dependency !== "string") {
        directory = await Deno.realPath(resolve(owner, dependency.path));
        if (boundary && !contained(boundary, directory)) {
          throw new Error(
            `${alias}: downloaded package dependency escapes its repository`,
          );
        }
        identity = `path:${directory}`;
      } else {
        const spec = gitSource(dependency);
        identity = `${spec.source}#${spec.ref}`;
        const existing = packages.get(alias);
        if (existing) {
          if (existing.identity !== identity) {
            throw new Error(
              `Conflicting dependency ${alias}; choose distinct package names`,
            );
          }
          continue;
        }
        let pin = old?.packages[alias];
        if (pin && (pin.source !== spec.source || pin.ref !== spec.ref)) {
          pin = undefined;
        }
        if (!pin && (mode === "resolve" || frozen)) {
          throw new Error(`${alias}: run bpm install to update blot.lock.json`);
        }
        const cache = cacheRoot(options);
        let found: string | undefined;
        if (pin && mode !== "update") found = await cached(cache, pin);
        if (mode === "resolve" && !found) {
          throw new Error(`${alias}: cached package missing; run bpm install`);
        }
        if (!found) {
          let revision: string | undefined;
          if (mode !== "update") revision = pin?.revision;
          const result = await download(cache, spec.source, spec.ref, revision);
          pin = result.pin;
          found = result.root;
        }
        lock.packages[alias] = pin!;
        directory = found;
        childBoundary = await Deno.realPath(directory);
      }
      const existing = packages.get(alias);
      if (existing) {
        if (existing.identity !== identity) {
          throw new Error(
            `Conflicting dependency ${alias}; choose distinct package names`,
          );
        }
        continue;
      }
      if (packages.size >= 256) {
        throw new Error("Package graph exceeds 256 packages");
      }
      const item = {
        identity,
        root: directory,
        workspace: await workspace(directory),
      };
      packages.set(alias, item);
      const child = await manifest(directory, false, childBoundary);
      if (child) await visit(directory, child.dependencies, childBoundary);
    }
  }
  await visit(root, input.dependencies);
  if (frozen && !sameLock(lock, old)) {
    throw new Error("blot.lock.json needs updating; run bpm install");
  }
  const imports: Record<string, string> = Object.create(null);
  for (const [alias, item] of packages) {
    for (const [key, directory] of Object.entries(item.workspace.exports)) {
      let prefix = `${alias}/`;
      if (key !== ".") prefix += `${key}/`;
      imports[prefix] = directory;
    }
  }
  let prelude: string | null = null;
  if (input.prelude) {
    if (!Object.hasOwn(input.dependencies, input.prelude)) {
      throw new Error("Prelude must name a direct dependency");
    }
    prelude = packages.get(input.prelude)?.workspace.prelude ?? null;
    if (!prelude) {
      throw new Error(`${input.prelude}: workspace does not export a prelude`);
    }
  }
  return {
    project: { root, imports, prelude, stdRoot: null } satisfies PackageProject,
    lock,
  };
}

function sameLock(current: Lock, previous: Lock | undefined): boolean {
  if (
    !previous ||
    Object.keys(current.packages).length !==
      Object.keys(previous.packages).length
  ) return false;
  for (const [alias, pin] of Object.entries(current.packages)) {
    const old = previous.packages[alias];
    if (
      !old || old.source !== pin.source || old.ref !== pin.ref ||
      old.revision !== pin.revision
    ) return false;
  }
  return true;
}

/** Resolve installed packages without network access. Manifest projects have no implicit prelude. */
export async function resolveProject(
  entry: string,
  options: PackageOptions = {},
): Promise<PackageProject | undefined> {
  let root = dirname(resolve(entry));
  while (true) {
    const input = await manifest(root);
    if (input) {
      return (await graph(root, input, options, "resolve", false)).project;
    }
    const parent = dirname(root);
    if (parent === root) return;
    root = parent;
  }
}

/** Populate Git packages and atomically publish their exact commit lock. Local packages stay live. */
export async function installPackages(
  root: string,
  options: PackageOptions & { update?: boolean; frozen?: boolean } = {},
): Promise<PackageProject> {
  root = resolve(root);
  const input = (await manifest(root, true))!;
  let mode: "install" | "update" = "install";
  if (options.update) mode = "update";
  if (options.frozen && options.update) {
    throw new Error("--frozen cannot update revisions");
  }
  const result = await graph(
    root,
    input,
    options,
    mode,
    options.frozen ?? false,
  );
  if (!options.frozen) {
    const temporary = await Deno.makeTempFile({
      dir: root,
      prefix: ".blot-lock-",
    });
    try {
      await Deno.writeTextFile(
        temporary,
        JSON.stringify(result.lock, null, 2) + "\n",
      );
      await Deno.rename(temporary, join(root, "blot.lock.json"));
    } finally {
      await Deno.remove(temporary).catch((error) => {
        if (!(error instanceof Deno.errors.NotFound)) throw error;
      });
    }
  }
  return result.project;
}
