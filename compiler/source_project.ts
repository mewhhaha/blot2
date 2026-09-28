import { Fifo } from "./fifo.ts";
import { dirname, relative, resolve, sep } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { bendArray, bendList } from "./bend_list.ts";
import { createFrontend, type Cst, SourceError } from "./syntax.ts";

export interface SourceModule {
  readonly name: string;
  readonly filename: string;
  readonly source: string;
  readonly root: Cst;
  readonly nodeCount: bigint;
}

export interface SourceProject {
  readonly kind: "source_project";
  readonly entry: string;
  /** Dependency-first order; import cycles are diagnosed by the loader. */
  readonly modules: readonly SourceModule[];
}

export type SourceInput = string | SourceProject;

export interface ProjectOptions {
  /** Explicit directory aliases, e.g. { "std/": new URL("../std/", import.meta.url) }. */
  readonly imports?: Readonly<Record<string, URL>>;
  readonly readSource?: (url: URL) => Promise<string>;
}

function field(node: Cst, label: string): Cst {
  const found = bendArray(node.children).find((child) => child.field === label);
  if (!found) throw new Error(`Missing parser field ${node.kind}.${label}`);
  return found;
}

// Parsed trees are retained across loads. Freeze them once when parsed so a
// caller editing a returned project cannot change the loader's cached syntax.
function freezeParsed(root: Cst): void {
  const pending = [root];
  for (let node = pending.pop(); node; node = pending.pop()) {
    let list = node.children;
    while (list.$ === "Con") {
      pending.push(list.head);
      Object.freeze(list);
      list = list.tail;
    }
    Object.freeze(list);
    Object.freeze(node);
  }
}

function localFileUrl(url: URL): URL {
  if (url.protocol !== "file:" || url.search || url.hash) {
    throw new Error(
      "Source imports require local file URLs without queries or fragments",
    );
  }
  // Equivalent URL escapes must share cache keys and nominal module identities.
  return pathToFileURL(fileURLToPath(url));
}

function dependency(
  specifier: string,
  parent: URL,
  options: ProjectOptions,
): URL {
  let url: URL;
  if (specifier.startsWith("./") || specifier.startsWith("../")) {
    url = new URL(specifier, parent);
  } else {
    const prefix = Object.keys(options.imports ?? {}).sort((a, b) =>
      b.length - a.length
    )
      .find((prefix) => prefix.endsWith("/") && specifier.startsWith(prefix));
    if (!prefix) throw new Error(`No source import mapping for ${specifier}`);
    url = new URL(specifier.slice(prefix.length), options.imports![prefix]);
  }
  const filename = fileURLToPath(localFileUrl(url));
  return pathToFileURL(
    filename.endsWith(".blot") ? filename : filename + ".blot",
  );
}

async function loadProject(
  entry: string | URL,
  options: ProjectOptions,
  parse: (
    url: URL,
    source: string,
  ) => ReturnType<Awaited<ReturnType<typeof createFrontend>>["parse"]>,
): Promise<SourceProject> {
  const entryUrl = localFileUrl(
    entry instanceof URL ? entry : pathToFileURL(resolve(entry)),
  );
  const directory = dirname(fileURLToPath(entryUrl));
  const readSource = options.readSource ?? Deno.readTextFile;
  const modules = new Map<string, SourceModule>();
  const visiting: string[] = [];
  const reads = new Map<string, Promise<PromiseSettledResult<string>>>();
  const waiting = new Fifo<() => void>();
  let activeReads = 0;
  function prefetch(url: URL): Promise<PromiseSettledResult<string>> {
    const existing = reads.get(url.href);
    if (existing) return existing;
    const result = (async () => {
      if (activeReads >= 4) {
        await new Promise<void>((resolve) => waiting.push(resolve));
      } else activeReads++;
      try {
        return { status: "fulfilled", value: await readSource(url) } as const;
      } catch (reason) {
        return { status: "rejected", reason } as const;
      } finally {
        const next = waiting.shift();
        if (next) next();
        else activeReads--;
      }
    })();
    reads.set(url.href, result);
    return result;
  }

  const moduleName = (url: URL) =>
    relative(directory, fileURLToPath(url)).split(sep).join("/");

  async function visit(url: URL): Promise<SourceModule> {
    const ready = modules.get(url.href);
    if (ready) return ready;
    const filename = fileURLToPath(url);
    const read = await prefetch(url);
    if (read.status === "rejected") throw read.reason;
    const source = read.value;
    visiting.push(url.href);
    try {
      const parsed = parse(url, source);
      const imports = bendArray(parsed.root.children).filter((node) =>
        node.field === "imports"
      );
      // Resolve and read siblings ahead; consume failures in depth-first order.
      const targets = imports.map((node): PromiseSettledResult<URL> => {
        const path = field(node, "path");
        const specifier: unknown = JSON.parse(path.text);
        if (typeof specifier !== "string") {
          throw new Error("Parser produced a non-string import path");
        }
        try {
          const target = dependency(specifier, url, options);
          prefetch(target);
          return { status: "fulfilled", value: target };
        } catch (error) {
          return {
            status: "rejected",
            reason: new SourceError(
              "import_path",
              String(error),
              Number(path.offset),
            ),
          };
        }
      });
      const linked: Cst[] = [];
      for (const [index, node] of imports.entries()) {
        const resolved = targets[index];
        if (resolved.status === "rejected") throw resolved.reason;
        const target = resolved.value;
        const path = field(node, "path");
        if (visiting.includes(target.href)) {
          throw new SourceError(
            "import_cycle",
            `Source import cycle: ${
              [...visiting, target.href].map((path) =>
                moduleName(new URL(path))
              ).join(" -> ")
            }`,
            Number(path.offset),
          );
        }
        const imported = await visit(target);
        const binding = field(node, "binding");
        linked.push({
          ...node,
          kind: "linked_import",
          text: imported.name,
          children: bendList([binding]),
        });
      }
      const module: SourceModule = {
        name: moduleName(url),
        filename,
        source,
        nodeCount: parsed.nodeCount,
        root: {
          ...parsed.root,
          children: bendList([
            ...linked,
            ...bendArray(parsed.root.children).filter((node) =>
              node.field !== "imports"
            ),
          ]),
        },
      };
      modules.set(url.href, module);
      return module;
    } catch (error) {
      if (error instanceof SourceError && !error.origin) {
        throw new SourceError(
          error.code,
          error.message,
          error.start,
          error.end,
          { filename, source },
        );
      }
      throw error;
    } finally {
      visiting.pop();
    }
  }

  try {
    const root = await visit(entryUrl);
    return {
      kind: "source_project",
      entry: root.name,
      modules: [...modules.values()],
    };
  } finally {
    await Promise.all(reads.values());
  }
}

/** Retain validated per-file syntax while re-reading the import graph each load. */
export async function createSourceProjectLoader(options: ProjectOptions = {}) {
  const configured: ProjectOptions = {
    ...options,
    imports: options.imports && Object.fromEntries(
      Object.entries(options.imports).map(([prefix, url]) => [
        prefix,
        new URL(url),
      ]),
    ),
  };
  const frontend = await createFrontend();
  type Parsed = ReturnType<typeof frontend.parse>;
  let cached = new Map<string, { source: string; parsed: Parsed }>();
  let closed = false;
  return {
    async load(entry: string | URL): Promise<SourceProject> {
      if (closed) throw new Error("Source project loader is disposed");
      const next = new Map<string, { source: string; parsed: Parsed }>();
      const project = await loadProject(entry, configured, (url, source) => {
        if (closed) throw new Error("Source project loader is disposed");
        const previous = cached.get(url.href);
        const value = previous?.source === source
          ? previous
          : { source, parsed: frontend.parse(source) };
        if (value !== previous) freezeParsed(value.parsed.root);
        next.set(url.href, value);
        return value.parsed;
      });
      if (closed) throw new Error("Source project loader is disposed");
      cached = next;
      return project;
    },
    dispose() {
      if (closed) return;
      closed = true;
      cached.clear();
      frontend.dispose();
    },
  };
}

export async function loadSourceProject(
  entry: string | URL,
  options: ProjectOptions = {},
): Promise<SourceProject> {
  const loader = await createSourceProjectLoader(options);
  try {
    return await loader.load(entry);
  } finally {
    loader.dispose();
  }
}
