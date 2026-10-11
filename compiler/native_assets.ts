import { dirname, isAbsolute, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import type {
  AssetBuildStats,
  AssetDependency,
  CompiledAsset,
} from "./assets.ts";

export type NativeAssetKind =
  | "json"
  | "catalog"
  | "text"
  | "tunables"
  | "wgsl"
  | "reference";
export interface NativeAssetImport {
  /** Virtual import path; relative paths resolve beside the entry. */
  readonly module: string | URL;
  readonly path: string | URL;
  readonly kind: NativeAssetKind;
  /** Required for references, together with export. */
  readonly type?: string;
  readonly export?: string;
  readonly mediaType?: string;
}
export interface NativeAssetOptions {
  readonly imports?: readonly NativeAssetImport[];
  /** Discover catalog, text, tunables and direct assets/*.wgsl modules. */
  readonly roots?: readonly (string | URL)[];
}
interface CapturedImport {
  module: string;
  path: string;
  kind: NativeAssetKind;
  type?: string;
  export?: string;
  mediaType?: string;
}
export interface CapturedNativeAssets {
  imports: CapturedImport[];
  roots: string[];
}
const fileLimit = 16 * 1024 * 1024;
const totalLimit = 64 * 1024 * 1024;
function object(value: unknown, label: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new TypeError(`${label} must be an object`);
  }
  return value as Record<string, unknown>;
}
function fields(value: Record<string, unknown>, allowed: string[]) {
  for (const name of Object.keys(value)) {
    if (!allowed.includes(name)) {
      throw new TypeError(`Invalid asset field: ${name}`);
    }
  }
}
function localPath(value: unknown, base: string): string {
  let text = value;
  if (value instanceof URL) text = fileURLToPath(new URL(value.href));
  if (
    typeof text !== "string" || !text || text.includes("\0") ||
    !text.isWellFormed()
  ) throw new TypeError("Asset paths must be nonempty local paths");
  return resolve(base, text);
}
function identifier(value: unknown, upper: boolean): string {
  let valid = typeof value === "string";
  if (valid) {
    const name = value as string;
    if (upper) {
      valid = /^[A-Z][A-Za-z0-9_]*$/.test(name) &&
        !["Unit", "Bool", "U32", "F32", "Array", "List"].includes(name);
    } else {
      valid = /^[a-z_][A-Za-z0-9_]*$/.test(name) && name !== "_" &&
        !"const let type data effect is fn do use return yield break for ever in case of if then else as import infix infixl infixr self where"
          .split(" ").includes(name);
    }
  }
  if (!valid) throw new TypeError("Invalid Blot asset identifier");
  return value as string;
}
export function captureNativeAssets(
  value: NativeAssetOptions | undefined,
  entry: string,
): CapturedNativeAssets | undefined {
  if (value === undefined) return undefined;
  const options = object(value, "nativeAssets");
  fields(options, ["imports", "roots"]);
  let definitions = options.imports;
  let roots = options.roots;
  if (definitions === undefined) definitions = [];
  if (roots === undefined) roots = [];
  if (!Array.isArray(definitions) || !Array.isArray(roots)) {
    throw new TypeError("Native asset imports and roots must be arrays");
  }
  if (definitions.length + roots.length > 4096) {
    throw new RangeError("Too many native asset definitions");
  }
  const base = dirname(entry);
  const modules = new Set<string>();
  const imports = definitions.map((definition): CapturedImport => {
    const item = object(definition, "native asset import");
    fields(item, ["module", "path", "kind", "type", "export", "mediaType"]);
    let module = localPath(item.module, base);
    if (!module.endsWith(".blot")) module += ".blot";
    if (module === entry || modules.has(module)) {
      throw new TypeError(
        "Native asset modules must be distinct from the entry",
      );
    }
    modules.add(module);
    if (
      typeof item.kind !== "string" ||
      !["json", "catalog", "text", "tunables", "wgsl", "reference"].includes(
        item.kind,
      )
    ) {
      throw new TypeError("Invalid native asset reader kind");
    }
    const captured: CapturedImport = {
      module,
      path: localPath(item.path, base),
      kind: item.kind as NativeAssetKind,
    };
    if (captured.kind === "reference") {
      captured.type = identifier(item.type, true);
      captured.export = identifier(item.export, false);
      const mediaType = item.mediaType ?? "application/octet-stream";
      if (
        typeof mediaType !== "string" || !mediaType || mediaType.length > 256 ||
        !mediaType.isWellFormed() || /[\r\n\0]/.test(mediaType)
      ) throw new TypeError("Invalid asset media type");
      captured.mediaType = mediaType;
    } else if (
      item.type !== undefined || item.export !== undefined ||
      item.mediaType !== undefined
    ) {
      throw new TypeError("Reference fields require the reference reader");
    }
    return captured;
  });
  const capturedRoots = roots.map((root) => localPath(root, base));
  if (new Set(capturedRoots).size !== capturedRoots.length) {
    throw new TypeError("Duplicate native asset root");
  }
  return { imports, roots: capturedRoots };
}

/** Decode a complete partition and authenticate the immutable content snapshots. */
export async function readNativeAssetReply(
  metadata: Record<string, unknown>,
  payload: Uint8Array<ArrayBuffer>,
  reject: (message: string) => never,
): Promise<{
  bytes: Uint8Array<ArrayBuffer>;
  assets: CompiledAsset[];
  assetDependencies: AssetDependency[];
  assetStats: AssetBuildStats;
}> {
  function natural(
    value: unknown,
    label: string,
    maximum = Number.MAX_SAFE_INTEGER,
  ): number {
    if (
      !Number.isSafeInteger(value) || (value as number) < 0 ||
      (value as number) > maximum
    ) {
      reject(`Invalid native asset ${label}`);
    }
    return value as number;
  }
  function path(value: unknown): string {
    if (
      typeof value !== "string" || !value || !isAbsolute(value) ||
      !value.isWellFormed() || value.includes("\0")
    ) {
      reject("Invalid native asset path");
    }
    return value as string;
  }
  function digest(value: unknown): string {
    if (typeof value !== "string" || !/^[0-9a-f]{64}$/.test(value)) {
      reject("Invalid native asset SHA256");
    }
    return value as string;
  }
  const wasmBytes = natural(metadata.wasmBytes, "Wasm length", payload.length);
  if (!wasmBytes) reject("Native asset response has no Wasm");
  if (
    !Array.isArray(metadata.assets) || metadata.assets.length > 4096 ||
    !Array.isArray(metadata.assetDependencies) ||
    metadata.assetDependencies.length > 4096
  ) {
    reject("Invalid native asset manifest");
  }
  const assets: CompiledAsset[] = [];
  const identities = new Set<string>();
  let offset = wasmBytes;
  for (const value of metadata.assets as unknown[]) {
    const item = object(value, "asset");
    fields(item, ["id", "path", "mediaType", "sha256", "start", "length"]);
    const id = natural(item.id, "id", 0xffff_ffff);
    if (id !== assets.length + 1) {
      reject("Native asset IDs must be consecutive and positive");
    }
    const start = natural(item.start, "start", payload.length);
    const length = natural(item.length, "length", fileLimit);
    if (start !== offset || length > payload.length - start) {
      reject("Invalid native asset payload partition");
    }
    const resourcePath = path(item.path);
    const sha256 = digest(item.sha256);
    const mediaType = item.mediaType;
    if (
      typeof mediaType !== "string" || !mediaType || mediaType.length > 256 ||
      !mediaType.isWellFormed() || /[\r\n\0]/.test(mediaType)
    ) reject("Invalid native asset media type");
    const identity = JSON.stringify([resourcePath, mediaType, sha256]);
    if (identities.has(identity)) reject("Duplicate native asset resource");
    identities.add(identity);
    const bytes = payload.slice(start, start + length);
    const hash = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
    const actual = Array.from(
      hash,
      (byte) => byte.toString(16).padStart(2, "0"),
    ).join("");
    if (actual !== sha256) {
      reject("Native asset SHA256 does not match its bytes");
    }
    assets.push({
      id,
      path: resourcePath,
      mediaType: mediaType as string,
      sha256,
      bytes,
    });
    offset += length;
  }
  if (offset !== payload.length) {
    reject("Native asset payload has unclaimed bytes");
  }
  const paths = new Set<string>();
  const assetDependencies = (metadata.assetDependencies as unknown[]).map(
    (value): AssetDependency => {
      const item = object(value, "asset dependency");
      fields(item, ["path", "sha256"]);
      const name = path(item.path);
      if (paths.has(name)) reject("Duplicate native asset dependency");
      paths.add(name);
      let sha256: string | null = null;
      if (item.sha256 !== null) sha256 = digest(item.sha256);
      return { path: name, sha256 };
    },
  );
  const wireStats = object(metadata.assetStats, "assetStats");
  fields(wireStats, ["parsed", "reused", "inputBytes", "generatedBytes"]);
  const assetStats = {
    parsed: natural(wireStats.parsed, "parsed count", 4096),
    reused: natural(wireStats.reused, "reused count", 4096),
    inputBytes: natural(wireStats.inputBytes, "input bytes", totalLimit),
    generatedBytes: natural(
      wireStats.generatedBytes,
      "generated bytes",
      totalLimit,
    ),
  };
  if (assetStats.parsed + assetStats.reused > 4096) {
    reject("Invalid native asset module count");
  }
  return {
    bytes: payload.slice(0, wasmBytes),
    assets,
    assetDependencies,
    assetStats,
  };
}
