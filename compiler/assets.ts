/** Typed, dependency-tracked asset modules. No file format is privileged by Zig. */
import { dirname, isAbsolute, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import type {
  ZigProjectBuildOptions,
  ZigProjectBuildResult,
  ZigProjectCompiler,
} from "./zig_project_client.ts";

export type AssetType =
  | "Unit"
  | "Bool"
  | "U32"
  | "F32"
  | { readonly array: AssetType }
  | { readonly tuple: readonly AssetType[] }
  | AssetRecordType
  | { readonly reference: string };
export interface AssetRecordType {
  readonly name: string;
  readonly fields: Readonly<Record<string, AssetType>>;
}
declare const referenceBrand: unique symbol;
/** Obtain these from context.reference(); they are symbolic until assembly. */
export interface AssetReference {
  readonly [referenceBrand]: true;
}
export interface AssetModule {
  /** Transparent names for scalar, array, tuple, or other described types. */
  readonly aliases?: Readonly<Record<string, AssetType>>;
  /** Record and reference types can be exported without a value (shader inputs). */
  readonly types?:
    readonly (AssetRecordType | { readonly reference: string })[];
  readonly values?: Readonly<
    Record<string, { readonly type: AssetType; readonly value: unknown }>
  >;
}
export interface AssetContext {
  readonly path: string;
  readonly bytes: Uint8Array<ArrayBuffer>;
  readonly signal?: AbortSignal;
  /** Paths resolve relative to the input asset. Returned buffers are copies. */
  read(path: string | URL): Promise<Uint8Array<ArrayBuffer>>;
  /** Publishes a content snapshot, not permission to reopen an arbitrary path. */
  reference(path?: string | URL, mediaType?: string): Promise<AssetReference>;
}
export type AssetParser = (
  context: AssetContext,
) => AssetModule | Promise<AssetModule>;
export interface AssetImport {
  /** Relative to the entry module, or an absolute local path. */
  readonly path: string | URL;
  readonly parser: AssetParser;
}
/** Keys are virtual module paths relative to the entry. Normal imports use them. */
export type AssetImports = Readonly<Record<string, AssetImport>>;
/** Capture options before compiler extraction/process startup can yield. */
export function captureAssetImports(
  imports: AssetImports | undefined,
): AssetImports | undefined {
  if (imports === undefined) return undefined;
  if (!imports || typeof imports !== "object" || Array.isArray(imports)) {
    throw new TypeError("Asset imports must be an object");
  }
  if (Object.keys(imports).length > 4096) {
    throw new RangeError("Too many asset modules");
  }
  return Object.fromEntries(
    Object.entries(imports).map(([name, definition]) => {
      if (!definition || typeof definition.parser !== "function") {
        throw new TypeError("Asset import requires a parser function");
      }
      return [name, {
        path: definition.path instanceof URL
          ? fileURLToPath(definition.path)
          : definition.path,
        parser: definition.parser,
      }];
    }),
  );
}
export interface AssetDependency {
  readonly path: string;
  /** Null records an absent file, including a caught optional-include failure. */
  readonly sha256: string | null;
}
export interface CompiledAsset {
  readonly id: number;
  readonly path: string;
  readonly mediaType: string;
  readonly sha256: string;
  readonly bytes: Uint8Array<ArrayBuffer>;
}
export interface AssetBuildStats {
  parsed: number;
  reused: number;
  inputBytes: number;
  generatedBytes: number;
}

const encoder = new TextEncoder();
const limit = 16 * 1024 * 1024;
const totalLimit = 64 * 1024 * 1024;
const keywords = new Set(
  "const let type data effect is fn do use return yield break for ever in case of if then else as import infix infixl infixr self where"
    .split(" "),
);
function identifier(name: string, upper: boolean): string {
  if (
    typeof name !== "string" ||
    !(upper ? /^[A-Z][A-Za-z0-9_]*$/ : /^[a-z_][A-Za-z0-9_]*$/).test(name) ||
    keywords.has(name) || name === "_" ||
    (upper && ["Unit", "Bool", "U32", "F32", "Array", "List"].includes(name))
  ) {
    throw new TypeError(
      `Invalid Blot ${upper ? "type" : "value/field"} name: ${name}`,
    );
  }
  return name;
}
function localPath(value: string | URL, base: string): string {
  const path = value instanceof URL ? fileURLToPath(value) : value;
  if (
    typeof path !== "string" || !path || path.includes("\0") ||
    !path.isWellFormed()
  ) {
    throw new TypeError("Asset paths must be nonempty local paths");
  }
  return resolve(base, path);
}
async function canonical(path: string): Promise<string> {
  try {
    return await Deno.realPath(path);
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
    const parent = dirname(path);
    if (parent === path) throw error;
    return resolve(await canonical(parent), path.slice(parent.length + 1));
  }
}
function same(left: Uint8Array, right: Uint8Array): boolean {
  return left.length === right.length &&
    left.every((byte, i) => byte === right[i]);
}
async function digest(bytes: Uint8Array<ArrayBuffer>): Promise<string> {
  return Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}
interface Resource {
  path: string;
  mediaType: string;
  bytes: Uint8Array<ArrayBuffer>;
  sha256: string;
}
interface PreparedModule {
  path: string;
  source: (ids: ReadonlyMap<string, number>) => string;
  reads: ReadonlyMap<
    string,
    { path: string; bytes: Uint8Array<ArrayBuffer> | null }
  >;
  resources: ReadonlyMap<string, Resource>;
}
interface Definition {
  module: string;
  input: string;
  parser: AssetParser;
}
const resourceKey = (resource: Resource) =>
  JSON.stringify([resource.path, resource.mediaType, resource.sha256]);

/** Validate and lower descriptors once, retaining no caller-owned objects. */
function prepareModule(
  result: AssetModule,
  references: WeakMap<object, Resource>,
): Pick<PreparedModule, "source" | "resources"> {
  const declarations = new Map<string, string>();
  const active = new Set<object>();
  const resources = new Map<string, Resource>();
  let nodes = 0;
  const visit = (depth: number) => {
    if (++nodes > 1_000_000 || depth > 128) {
      throw new RangeError("Asset description exceeds the structural budget");
    }
  };
  function type(value: AssetType, depth = 0): string {
    visit(depth);
    if (typeof value === "string") {
      if (["Unit", "Bool", "U32", "F32"].includes(value)) return value;
      throw new TypeError(`Unsupported asset type: ${value}`);
    }
    if (!value || typeof value !== "object" || active.has(value)) {
      throw new TypeError("Invalid or recursive asset type");
    }
    active.add(value);
    try {
      if ("array" in value) return `(Array ${type(value.array, depth + 1)})`;
      if ("tuple" in value) {
        const fields = value.tuple.map((field) => type(field, depth + 1));
        return `(${fields.join(", ")}${fields.length === 1 ? "," : ""})`;
      }
      const name = identifier(
        "reference" in value ? value.reference : value.name,
        true,
      );
      const body = "reference" in value
        ? "U32"
        : `{ ${
          Object.entries(value.fields).map(([field, shape]) =>
            `${identifier(field, false)}: ${type(shape, depth + 1)}`
          ).join(", ")
        } }`;
      const declaration = `type ${name} is data = #${name} ${body}\n`;
      const previous = declarations.get(name);
      if (previous && previous !== declaration) {
        throw new TypeError(`Conflicting asset type: ${name}`);
      }
      declarations.set(name, declaration);
      return name;
    } finally {
      active.delete(value);
    }
  }
  // Keep one flat source template; large data arrays must not allocate a
  // closure for each scalar. Reference slots are filled after deterministic IDs.
  const chunks: (string | { key: string })[] = [];
  function value(shape: AssetType, data: unknown, depth = 0): void {
    visit(depth);
    if (shape === "Unit") {
      if (data !== null) throw new TypeError("Unit asset values must be null");
      chunks.push("()");
    } else if (shape === "Bool") {
      if (typeof data !== "boolean") {
        throw new TypeError("Expected a Bool asset value");
      }
      chunks.push(data ? "#True" : "#False");
    } else if (shape === "U32") {
      if (
        typeof data !== "number" || !Number.isInteger(data) || data < 0 ||
        data > 0xffff_ffff
      ) throw new TypeError("Asset number does not fit U32");
      chunks.push(String(data));
    } else if (shape === "F32") {
      if (
        typeof data !== "number" || !Number.isFinite(data) ||
        !Number.isFinite(Math.fround(data))
      ) throw new TypeError("Asset number does not fit finite F32");
      const number = Math.fround(data);
      const negative = number < 0 || Object.is(number, -0);
      let text = String(Math.abs(number));
      if (!/[.e]/i.test(text)) text += ".0";
      chunks.push(negative ? `(-${text})` : text);
    } else if (typeof shape === "string") {
      throw new TypeError("Unsupported asset value type");
    } else if ("reference" in shape) {
      const resource = data && typeof data === "object"
        ? references.get(data)
        : undefined;
      if (!resource) {
        throw new TypeError(
          "Asset references must come from context.reference()",
        );
      }
      const key = resourceKey(resource);
      resources.set(key, resource);
      chunks.push(`(#${shape.reference} `, { key }, ")");
    } else if ("array" in shape || "tuple" in shape) {
      if (!Array.isArray(data)) {
        throw new TypeError("Expected an asset array/tuple");
      }
      if ("tuple" in shape && shape.tuple.length !== data.length) {
        throw new TypeError("Asset tuple arity mismatch");
      }
      chunks.push("array" in shape ? "#[" : "(");
      data.forEach((item, index) => {
        if (index) chunks.push(", ");
        value(
          "array" in shape ? shape.array : shape.tuple[index],
          item,
          depth + 1,
        );
      });
      chunks.push("array" in shape ? "]" : data.length === 1 ? ",)" : ")");
    } else {
      if (!data || typeof data !== "object" || Array.isArray(data)) {
        throw new TypeError("Expected an asset record");
      }
      const fields = Object.entries(shape.fields);
      const object = data as Record<string, unknown>;
      if (
        Object.keys(object).length !== fields.length ||
        fields.some(([name]) => !Object.hasOwn(object, name))
      ) throw new TypeError(`Fields do not match asset type ${shape.name}`);
      chunks.push(`(#${shape.name} { `);
      fields.forEach(([name, ty], index) => {
        if (index) chunks.push(", ");
        chunks.push(`${name}: `);
        value(ty, object[name], depth + 1);
      });
      chunks.push(" })");
    }
  }
  if (!result || typeof result !== "object" || Array.isArray(result)) {
    throw new TypeError("Asset parser must return a typed module");
  }
  for (const shape of result.types ?? []) type(shape);
  const aliases = Object.entries(result.aliases ?? {}).map(([name, shape]) => {
    identifier(name, true);
    return [name, `type ${name} = ${type(shape)}\n`] as const;
  });
  for (const [name, item] of Object.entries(result.values ?? {})) {
    identifier(name, false);
    const annotation = type(item.type);
    chunks.push(`const ${name}: ${annotation} = `);
    value(item.type, item.value);
    chunks.push("\n");
  }
  for (const [name, declaration] of aliases) {
    if (declarations.has(name)) {
      throw new TypeError(`Conflicting asset type: ${name}`);
    }
    declarations.set(name, declaration);
  }
  // Coalesce static chunks before retaining a module across revisions.
  const template: (string | { key: string })[] = [];
  let first = 0;
  for (let index = 0; index < chunks.length; index++) {
    const chunk = chunks[index];
    if (typeof chunk === "string") continue;
    template.push(chunks.slice(first, index).join(""), chunk);
    first = index + 1;
  }
  template.push(chunks.slice(first).join(""));
  const header = [...declarations.values()].join("");
  const staticBytes = encoder.encode(header).length +
    template.reduce(
      (size, chunk) =>
        size + (typeof chunk === "string" ? encoder.encode(chunk).length : 10),
      0,
    );
  if (staticBytes > limit) {
    throw new RangeError("Generated asset module exceeds 16 MiB");
  }
  return {
    resources,
    source: (ids) =>
      header + template.map((chunk) => {
        if (typeof chunk === "string") return chunk;
        const id = ids.get(chunk.key);
        if (!id) throw new Error("Missing asset reference assignment");
        return String(id);
      }).join(""),
  };
}

/** Wrap the retained native compiler; each build owns an asset input snapshot. */
export async function withAssetImports(
  compiler: ZigProjectCompiler,
  entry: string,
  imports: AssetImports,
): Promise<ZigProjectCompiler> {
  const base = dirname(entry);
  const definitions: Definition[] = [];
  const names = new Set<string>();
  if (Object.keys(imports).length > 4096) {
    throw new RangeError("Too many asset modules");
  }
  for (const [name, definition] of Object.entries(imports)) {
    if (
      !isAbsolute(name) && !name.startsWith("./") && !name.startsWith("../")
    ) {
      throw new TypeError(
        "Asset module names must be relative or absolute paths",
      );
    }
    const path = localPath(
      name.endsWith(".blot") ? name : `${name}.blot`,
      base,
    );
    const module = await canonical(path);
    if (names.has(module) || module === await canonical(entry)) {
      throw new TypeError(
        "Asset modules must have distinct paths, separate from the entry",
      );
    }
    if (typeof definition?.parser !== "function") {
      throw new TypeError("Asset import requires a parser function");
    }
    names.add(module);
    definitions.push({
      module,
      input: localPath(definition.path, base),
      parser: definition.parser,
    });
  }
  definitions.sort((a, b) =>
    a.module < b.module ? -1 : a.module > b.module ? 1 : 0
  );
  let cache = new Map<string, PreparedModule>();
  const digests = new WeakMap<Uint8Array<ArrayBuffer>, Promise<string>>();
  const fingerprint = (bytes: Uint8Array<ArrayBuffer>) => {
    let hash = digests.get(bytes);
    if (!hash) {
      hash = digest(bytes);
      digests.set(bytes, hash);
    }
    return hash;
  };
  let revision = 0;
  let closed = false;
  const lifetime = new AbortController();
  let queue: Promise<unknown> = Promise.resolve();
  const enqueue = <T>(job: () => Promise<T>): Promise<T> => {
    const result = queue.then(job);
    queue = result.catch(() => {});
    return result;
  };
  async function build(
    options: ZigProjectBuildOptions,
  ): Promise<ZigProjectBuildResult> {
    if (closed) throw new Error("Asset compiler is closed");
    options.signal?.throwIfAborted();
    const snapshots = new Map<string, Uint8Array<ArrayBuffer>>();
    const overrides = new Map<string, Uint8Array<ArrayBuffer> | null>();
    for (const [name, contents] of Object.entries(options.assetSources ?? {})) {
      const path = await canonical(localPath(name, base));
      if (overrides.has(path)) {
        throw new TypeError("Duplicate asset source path");
      }
      overrides.set(
        path,
        contents === null
          ? null
          : typeof contents === "string"
          ? encoder.encode(contents)
          : contents,
      );
    }
    let inputBytes = 0;
    const paths = new Map<string, Promise<string>>();
    const resolvePath = (raw: string) => {
      let path = paths.get(raw);
      if (!path) {
        path = canonical(raw);
        paths.set(raw, path);
      }
      return path;
    };
    const loads = new Map<string, Promise<Uint8Array<ArrayBuffer>>>();
    const read = async (raw: string): Promise<Uint8Array<ArrayBuffer>> => {
      options.signal?.throwIfAborted();
      const path = await resolvePath(raw);
      const existing = loads.get(path);
      if (existing) return existing;
      const loading = load(path);
      loads.set(path, loading);
      return loading;
    };
    const load = async (path: string): Promise<Uint8Array<ArrayBuffer>> => {
      const override = overrides.get(path);
      if (override === null) {
        throw new Deno.errors.NotFound(`Asset hidden by overlay: ${path}`);
      }
      let bytes = override;
      if (!bytes) {
        const file = await Deno.open(path, { read: true });
        try {
          const size = (await file.stat()).size;
          if (size > limit) throw new RangeError("Asset input exceeds 16 MiB");
          bytes = new Uint8Array(size + 1);
          let count = 0;
          while (count < bytes.length) {
            options.signal?.throwIfAborted();
            const read = await file.read(bytes.subarray(count));
            if (read === null) break;
            count += read;
          }
          if (count > size) {
            throw new Error(`Asset changed while reading: ${path}`);
          }
          bytes = bytes.slice(0, count);
        } finally {
          file.close();
        }
      }
      inputBytes += bytes.length;
      if (
        bytes.length > limit || inputBytes > totalLimit ||
        snapshots.size >= 4096
      ) throw new RangeError("Asset input budget exceeded");
      snapshots.set(path, bytes);
      return bytes;
    };
    const candidate = new Map<string, PreparedModule>();
    const stats: AssetBuildStats = {
      parsed: 0,
      reused: 0,
      inputBytes: 0,
      generatedBytes: 0,
    };
    let current = entry;
    let nativeStarted = false;
    try {
      for (const definition of definitions) {
        current = definition.input;
        const previous = cache.get(definition.module);
        let reusable = !!previous;
        if (previous) {
          for (const [path, before] of previous.reads) {
            try {
              if (await resolvePath(path) !== before.path) {
                reusable = false;
              } else {
                const current = await read(path);
                if (before.bytes === null || !same(current, before.bytes)) {
                  reusable = false;
                }
              }
            } catch (error) {
              if (!(error instanceof Deno.errors.NotFound)) throw error;
              if (before.bytes !== null) reusable = false;
            }
            if (!reusable) break;
          }
        }
        if (reusable && previous) {
          candidate.set(definition.module, previous);
          stats.reused++;
          continue;
        }
        const dependencies = new Map<
          string,
          { path: string; bytes: Uint8Array<ArrayBuffer> | null }
        >();
        const input = await resolvePath(definition.input);
        const trackedRead = async (path: string | URL) => {
          const raw = localPath(path, dirname(input));
          const resolved = await resolvePath(raw);
          try {
            const bytes = await read(raw);
            dependencies.set(raw, { path: resolved, bytes });
            return bytes;
          } catch (error) {
            if (error instanceof Deno.errors.NotFound) {
              dependencies.set(raw, { path: resolved, bytes: null });
            }
            throw error;
          }
        };
        const bytes = await trackedRead(input);
        dependencies.set(definition.input, { path: input, bytes });
        const references = new WeakMap<object, Resource>();
        const result = await definition.parser({
          path: input,
          bytes: bytes.slice(),
          signal: options.signal,
          read: async (path) => (await trackedRead(path)).slice(),
          reference: async (
            path = input,
            mediaType = "application/octet-stream",
          ) => {
            if (
              typeof mediaType !== "string" || !mediaType ||
              mediaType.length > 256 || /[\r\n\0]/.test(mediaType)
            ) throw new TypeError("Invalid asset media type");
            const bytes = await trackedRead(path);
            const resource: Resource = {
              path: await resolvePath(localPath(path, dirname(input))),
              mediaType,
              bytes,
              sha256: await fingerprint(bytes),
            };
            const reference = Object.freeze({}) as AssetReference;
            references.set(reference, resource);
            return reference;
          },
        });
        options.signal?.throwIfAborted();
        candidate.set(definition.module, {
          path: input,
          reads: dependencies,
          ...prepareModule(result, references),
        });
        stats.parsed++;
      }
      const resources = new Map<string, Resource>();
      for (const module of candidate.values()) {
        for (const [key, resource] of module.resources) {
          resources.set(key, resource);
        }
      }
      const sorted = [...resources].sort(([a], [b]) =>
        a < b ? -1 : a > b ? 1 : 0
      );
      const ids = new Map(sorted.map(([key], i) => [key, i + 1]));
      const sources: Record<string, string | null> = Object.create(null);
      for (const [raw, contents] of Object.entries(options.sources ?? {})) {
        const path = await canonical(localPath(raw, Deno.cwd()));
        if (names.has(path)) {
          throw new TypeError(
            "Source overlay collides with a generated asset module",
          );
        }
        sources[raw] = contents;
      }
      for (const [path, module] of candidate) {
        const source = module.source(ids);
        sources[path] = source;
        stats.generatedBytes += encoder.encode(source).length;
      }
      if (stats.generatedBytes > totalLimit) {
        throw new RangeError("Generated asset sources exceed 64 MiB");
      }
      options.signal?.throwIfAborted();
      // Digests and manifest copies precede native publication. Callers can
      // watch every input, including optional files, using this same snapshot.
      const dependencies = new Map<string, Uint8Array<ArrayBuffer> | null>();
      for (const module of candidate.values()) {
        for (const [path, input] of module.reads) {
          dependencies.set(path, input.bytes);
        }
      }
      const assetDependencies = await Promise.all(
        [...dependencies].sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0).map(
          async ([path, bytes]) => ({
            path,
            sha256: bytes === null ? null : await fingerprint(bytes),
          }),
        ),
      );
      const assets = sorted.map(([, resource], i) => ({
        ...resource,
        id: i + 1,
        bytes: resource.bytes.slice(),
      }));
      nativeStarted = true;
      const built = await compiler.build({ signal: options.signal, sources });
      if (!built.success) return built;
      cache = candidate;
      revision = built.revision;
      stats.inputBytes = inputBytes;
      return {
        ...built,
        assets,
        assetDependencies,
        assetStats: stats,
      };
    } catch (error) {
      options.signal?.throwIfAborted();
      if (closed || nativeStarted) throw error;
      return {
        success: false,
        revision,
        attemptStats: null,
        diagnostics: [{
          filename: current,
          stage: "asset",
          code: "asset_import",
          start: 0,
          end: 0,
          message: error instanceof Error ? error.message : String(error),
          offset_encoding: "utf8_bytes",
        }],
      };
    }
  }
  return {
    get pid() {
      return compiler.pid;
    },
    get compilerIdentity() {
      return compiler.compilerIdentity;
    },
    exportCheckpoint() {
      if (closed) return Promise.reject(new Error("Asset compiler is closed"));
      return enqueue(() => compiler.exportCheckpoint());
    },
    build(options = {}) {
      // Capture caller buffers before queueing, matching the native client.
      try {
        if (closed) throw new Error("Asset compiler is closed");
        if (
          !options || typeof options !== "object" || Array.isArray(options) ||
          Object.keys(options).some((key) =>
            !["signal", "sources", "assetSources"].includes(key)
          )
        ) throw new TypeError("Invalid asset build options");
        if (
          options.signal !== undefined &&
          !(options.signal instanceof AbortSignal)
        ) {
          throw new TypeError("Build signal must be an AbortSignal");
        }
        const signal = options.signal === undefined
          ? lifetime.signal
          : AbortSignal.any([options.signal, lifetime.signal]);
        signal.throwIfAborted();
        for (const map of [options.sources, options.assetSources]) {
          if (
            map !== undefined &&
            (!map || typeof map !== "object" || Array.isArray(map))
          ) throw new TypeError("Source overlays must be objects");
        }
        let overlayBytes = 0;
        const assets = Object.entries(options.assetSources ?? {});
        if (assets.length > 4096) {
          throw new RangeError("Too many asset overlays");
        }
        const copied: ZigProjectBuildOptions = {
          ...options,
          signal,
          sources: options.sources &&
            Object.fromEntries(
              Object.entries(options.sources).map(([path, contents]) => {
                if (contents !== null && typeof contents !== "string") {
                  throw new TypeError(
                    "Source overlays must contain strings or null",
                  );
                }
                return [localPath(path, Deno.cwd()), contents];
              }),
            ),
          assetSources: Object.fromEntries(
            assets.map(([path, value]) => {
              if (
                value !== null && typeof value !== "string" &&
                !(value instanceof Uint8Array)
              ) {
                throw new TypeError(
                  "Asset overlays must contain bytes, strings, or null",
                );
              }
              const size = value === null
                ? 0
                : typeof value === "string"
                ? encoder.encode(value).length
                : value.byteLength;
              overlayBytes += size;
              if (size > limit || overlayBytes > totalLimit) {
                throw new RangeError("Asset overlay budget exceeded");
              }
              return [
                path,
                value instanceof Uint8Array ? new Uint8Array(value) : value,
              ];
            }),
          ),
        };
        // A parser can ignore cancellation. Reject the public request without
        // waiting for it; its eventual result still observes the aborted signal
        // and cannot publish a native revision or mutate the retained cache.
        return new Promise<ZigProjectBuildResult>((resolve, reject) => {
          const abort = () => reject(signal.reason);
          signal.addEventListener("abort", abort, { once: true });
          enqueue(() => build(copied)).then(
            (result) => {
              signal.removeEventListener("abort", abort);
              resolve(result);
            },
            (error) => {
              signal.removeEventListener("abort", abort);
              reject(error);
            },
          );
        });
      } catch (error) {
        return Promise.reject(error);
      }
    },
    close() {
      if (closed) return compiler.close();
      return enqueue(async () => {
        closed = true;
        cache.clear();
        await compiler.close();
      });
    },
    dispose() {
      closed = true;
      lifetime.abort(new Error("Asset compiler is closed"));
      cache.clear();
      return compiler.dispose();
    },
  };
}

/** JSON objects become nominal records; homogeneous arrays remain arrays.
 * Strings use an explicit Utf8 record of bytes until Blot has runtime Text.
 * Empty/heterogeneous arrays are exact tuples, avoiding guessed element types. */
export const jsonAssetParser: AssetParser = (context) => {
  const source = new TextDecoder("utf-8", { fatal: true }).decode(
    context.bytes,
  );
  const parsed: unknown = JSON.parse(source);
  let serial = 0, count = 0;
  const records = new Map<string, AssetRecordType>();
  function infer(
    data: unknown,
    depth = 0,
  ): { type: AssetType; value: unknown } {
    if (depth > 128 || ++count > 1_000_000) {
      throw new RangeError("JSON asset exceeds the structural budget");
    }
    if (data === null) return { type: "Unit", value: null };
    if (typeof data === "boolean") return { type: "Bool", value: data };
    if (typeof data === "number") {
      if (Number.isInteger(data) && !Number.isSafeInteger(data)) {
        throw new TypeError("JSON integer exceeds exact host representation");
      }
      return {
        type: Number.isInteger(data) && !Object.is(data, -0) && data >= 0 &&
            data <= 0xffff_ffff
          ? "U32"
          : "F32",
        value: data,
      };
    }
    if (typeof data === "string") {
      if (!data.isWellFormed()) {
        throw new TypeError("JSON strings must be well-formed Unicode");
      }
      return {
        type: { name: "Utf8", fields: { bytes: { array: "U32" } } },
        value: { bytes: [...encoder.encode(data)] },
      };
    }
    if (Array.isArray(data)) {
      const items = data.map((item) => infer(item, depth + 1));
      const first = items[0]?.type;
      const homogeneous = items.length > 0 &&
        items.every((item) =>
          JSON.stringify(item.type) === JSON.stringify(first)
        );
      return {
        type: homogeneous
          ? { array: first }
          : { tuple: items.map((item) => item.type) },
        value: items.map((item) => item.value),
      };
    }
    if (typeof data !== "object") throw new TypeError("Unsupported JSON value");
    const fields: Record<string, AssetType> = Object.create(null);
    const values: Record<string, unknown> = Object.create(null);
    for (
      const [key, item] of Object.entries(data).sort(([a], [b]) =>
        a < b ? -1 : a > b ? 1 : 0
      )
    ) {
      identifier(key, false);
      const result = infer(item, depth + 1);
      fields[key] = result.type;
      values[key] = result.value;
    }
    const key = JSON.stringify(fields);
    let shape = depth === 0 ? undefined : records.get(key);
    if (!shape) {
      shape = { name: depth === 0 ? "Data" : `JsonRecord${++serial}`, fields };
      if (depth !== 0) records.set(key, shape);
    }
    return { type: shape, value: values };
  }
  const value = infer(parsed);
  return {
    aliases: typeof value.type === "object" && "name" in value.type &&
        value.type.name === "Data"
      ? undefined
      : { Data: value.type },
    values: { value },
  };
};
