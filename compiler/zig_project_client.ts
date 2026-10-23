import {
  captureCompletion,
  readCompletion,
  type ZigProjectCompletionOptions,
  type ZigProjectCompletionResult,
} from "./editor_completion.ts";
export type {
  ZigProjectCompletionItem,
  ZigProjectCompletionOptions,
  ZigProjectCompletionResult,
} from "./editor_completion.ts";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  type DispatchExplanation,
  readDispatchExplanation,
  readTypedHole,
  type TypedHoleDiagnostic,
} from "./type_diagnostics.ts";
import {
  type AssetBuildStats,
  type AssetDependency,
  type AssetImports,
  captureAssetImports,
  type CompiledAsset,
  withAssetImports,
} from "./assets.ts";

import {
  captureNativeAssets,
  type NativeAssetOptions,
  readNativeAssetReply,
} from "./native_assets.ts";
export type {
  NativeAssetImport,
  NativeAssetKind,
  NativeAssetOptions,
} from "./native_assets.ts";

export const maxFrameBytes = 64 * 1024 * 1024;
const maxMetadataBytes = 1024 * 1024;
type Json = null | boolean | number | string | Json[] | { [key: string]: Json };
export type ZigProjectStats = { [key: string]: Json };
export interface ZigProjectBuildStats extends ZigProjectStats {
  nativeWorkSteps: number;
  frontend: ZigProjectStats;
  sourceBytes: number;
  freshModules: number;
  cachedModules: number;
  attemptStats: ZigProjectStats;
}
export interface ZigProjectSourceLocation {
  filename: string;
  start: number;
  end: number;
  offset_encoding: "utf8_bytes";
}
export interface ZigProjectDiagnosticContext extends ZigProjectSourceLocation {
  kind: "callee" | "argument" | "left_operand" | "right_operand";
}
export interface ZigProjectDiagnostic {
  filename: string;
  stage: string;
  code: string;
  start: number;
  end: number;
  message: string;
  offset_encoding: "utf8_bytes";
  utf16?: { start: number; end: number } | null;
  /** Present for @hole on compiler versions publishing semantic snapshots. */
  hole?: TypedHoleDiagnostic;
  /** Present when dispatch failed: the candidates it considered and why. */
  explanation?: DispatchExplanation;
  /** Original callee location for a caller-dependent specialization failure. */
  related?: ZigProjectSourceLocation | null;
  /** Source expressions involved in a type, effect, or dispatch mismatch. */
  contexts?: ZigProjectDiagnosticContext[];
  origins?: Array<
    ZigProjectSourceLocation & {
      kind: "quote" | "generator" | "splice" | "invocation";
    }
  >;
  details?: unknown;
}
export type ZigProjectBuildResult =
  | {
    success: true;
    revision: number;
    bytes: Uint8Array<ArrayBuffer>;
    stats: ZigProjectBuildStats;
    /** Content snapshots addressed by the guest's nominal asset handles. */
    assets?: readonly CompiledAsset[];
    assetStats?: AssetBuildStats;
    assetDependencies?: readonly AssetDependency[];
  }
  | {
    success: false;
    revision: number;
    diagnostics: ZigProjectDiagnostic[];
    attemptStats: ZigProjectStats | null;
  };
export interface ZigProjectCompilerOptions {
  executable: string | URL;
  entry: string | URL;
  prelude?: string | URL | null;
  stdRoot?: string | URL | null;
  imports?: Readonly<Record<string, string | URL>>;
  dependencies?: string | URL | null;
  /** Collect detailed backend phase and slow inference-region timings. */
  profileBackend?: boolean;
  /** Collect bounded source-site demand lowering decisions. */
  explainDemands?: boolean;
  /** Development skips optional scalar/vector passes; checking and cleanup remain. */
  codegenTier?: "optimized" | "development";
  /** Prototype: share identical internal machine bodies while keeping table slots. */
  shareMachineCode?: boolean;
  /** Upper bound for coarse optimizer workers (1..16; default 4). */
  codegenWorkers?: number;
  /** Opt-in private semantic components with 1..16 workers; default stays serial. */
  semanticWorkers?: number;
  /** Process-local inference limit, included in compiler identity. */
  inferenceBudget?: number;
  /** Optional backend checkpoint from exportCheckpoint; copied at startup. */
  checkpoint?: Uint8Array<ArrayBuffer>;
  /** Native restart cache root. Defaults to the platform cache directory when
   * its environment is readable; false disables automatic persistence. */
  cacheDirectory?: string | URL | false;
  startupTimeoutMs?: number;
  expectedCompilerIdentity?: string;
  assets?: AssetImports;
  /** Parse captured external inputs directly in the native compiler. */
  nativeAssets?: NativeAssetOptions;
}
export interface ZigProjectCompiler {
  readonly pid: number;
  readonly compilerIdentity: string;
  build(options?: ZigProjectBuildOptions): Promise<ZigProjectBuildResult>;
  complete(
    options: ZigProjectCompletionOptions,
  ): Promise<ZigProjectCompletionResult>;
  /** Portable candidates from the last successful revision; does not advance it. */
  exportCheckpoint(): Promise<Uint8Array<ArrayBuffer>>;
  close(): Promise<void>;
  dispose(): Promise<void>;
}
export interface ZigProjectBuildOptions {
  signal?: AbortSignal;
  /** Complete overrides for this build. Missing keys read disk; null hides a file.
   * Paths may name new virtual files. Contents are copied before queueing. */
  sources?: Readonly<Record<string, string | null>>;
  /** External file overrides for configured parsers, relative to the entry. */
  assetSources?: Readonly<
    Record<string, string | Uint8Array<ArrayBuffer> | null>
  >;
}
export class ZigProjectProtocolError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ZigProjectProtocolError";
  }
}
function record(value: unknown, label: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ZigProjectProtocolError(`${label} must be an object`);
  }
  return value as Record<string, unknown>;
}
function keys(
  value: Record<string, unknown>,
  allowed: readonly string[],
  label: string,
) {
  for (const key of Object.keys(value)) {
    if (!allowed.includes(key)) {
      throw new TypeError(`Unsupported ${label} option/field: ${key}`);
    }
  }
}
function natural(value: unknown, label: string): number {
  if (!Number.isSafeInteger(value) || (value as number) < 0) {
    throw new ZigProjectProtocolError(`Invalid ${label}`);
  }
  return value as number;
}
function path(value: unknown, label: string): string {
  const text = value instanceof URL
    ? fileURLToPath(new URL(value.href))
    : value;
  if (
    typeof text !== "string" || !text.length || text.includes("\0") ||
    !text.isWellFormed()
  ) throw new TypeError(`${label} must be a nonempty path`);
  return resolve(text);
}
function stats(value: unknown, label: string): ZigProjectStats {
  const object = record(value, label);
  const inspect = (item: unknown): void => {
    if (Array.isArray(item)) {
      for (const child of item) inspect(child);
      return;
    }
    if (item && typeof item === "object") {
      for (const [key, child] of Object.entries(item)) {
        if (key === "const_steps" || key === "remaining_steps") {
          throw new ZigProjectProtocolError(
            "Source fuel is unsupported by the Zig project protocol",
          );
        }
        inspect(child);
      }
    }
  };
  inspect(object);
  return object as ZigProjectStats;
}
function buildStats(value: unknown): ZigProjectBuildStats {
  const object = stats(value, "stats");
  for (
    const field of [
      "nativeWorkSteps",
      "sourceBytes",
      "freshModules",
      "cachedModules",
    ]
  ) {
    natural(object[field], `stats ${field}`);
  }
  for (
    const field of [
      "frontend",
      "backend",
      "optimization",
      "runtimeOptimization",
      "backendTiming",
      "workCounters",
      "principals",
      "refinements",
      "selectedQueries",
      "attemptStats",
    ]
  ) stats(object[field], `stats ${field}`);
  if (typeof object.restartCacheLoaded !== "boolean") {
    throw new ZigProjectProtocolError("Invalid stats restartCacheLoaded");
  }
  return object as ZigProjectBuildStats;
}
function diagnostic(value: unknown): ZigProjectDiagnostic {
  const object = record(value, "diagnostic");
  for (const name of ["filename", "stage", "code", "message"]) {
    if (typeof object[name] !== "string") {
      throw new ZigProjectProtocolError(`Invalid diagnostic ${name}`);
    }
  }
  const start = natural(object.start, "diagnostic start");
  const end = natural(object.end, "diagnostic end");
  if (start > end || object.offset_encoding !== "utf8_bytes") {
    throw new ZigProjectProtocolError("Invalid diagnostic offsets");
  }
  if (object.utf16 != null) {
    const utf16 = record(object.utf16, "UTF-16 offsets");
    if (
      natural(utf16.start, "UTF-16 start") > natural(utf16.end, "UTF-16 end")
    ) throw new ZigProjectProtocolError("Invalid UTF-16 range");
  }
  if (object.related != null) {
    const location = record(object.related, "related location");
    const filename = location.filename;
    if (
      typeof filename !== "string" || !filename.length ||
      filename.includes("\0") || !filename.isWellFormed()
    ) throw new ZigProjectProtocolError("Invalid related filename");
    const start = natural(location.start, "related start");
    const end = natural(location.end, "related end");
    if (start > end || location.offset_encoding !== "utf8_bytes") {
      throw new ZigProjectProtocolError("Invalid related offsets");
    }
    object.related = { filename, start, end, offset_encoding: "utf8_bytes" };
  }
  if (object.origins !== undefined) {
    if (!Array.isArray(object.origins) || object.origins.length > 8) {
      throw new ZigProjectProtocolError("Invalid generated origins");
    }
    object.origins = object.origins.map((item) => {
      const location = record(item, "generated origin");
      const kind = location.kind;
      if (
        typeof kind !== "string" ||
        !["quote", "generator", "splice", "invocation"].includes(kind)
      ) {
        throw new ZigProjectProtocolError("Invalid generated origin kind");
      }
      const filename = location.filename;
      if (
        typeof filename !== "string" || !filename.length ||
        filename.includes("\0") || !filename.isWellFormed()
      ) {
        throw new ZigProjectProtocolError("Invalid generated origin filename");
      }
      const start = natural(location.start, "generated origin start");
      const end = natural(location.end, "generated origin end");
      if (start > end || location.offset_encoding !== "utf8_bytes") {
        throw new ZigProjectProtocolError("Invalid generated origin offsets");
      }
      return { kind, filename, start, end, offset_encoding: "utf8_bytes" };
    });
  }
  // These convenience fields are derived only from the validated wire payload.
  delete object.hole;
  delete object.explanation;
  delete object.contexts;
  if (object.code === "typed_hole" && object.details != null) {
    try {
      object.hole = readTypedHole(record(object.details, "hole details").hole);
    } catch {
      throw new ZigProjectProtocolError("Invalid typed-hole diagnostic");
    }
  }
  if (
    object.details != null && typeof object.details === "object" &&
    "explanation" in object.details
  ) {
    try {
      object.explanation = readDispatchExplanation(
        (object.details as Record<string, unknown>).explanation,
      );
    } catch {
      throw new ZigProjectProtocolError("Invalid dispatch explanation");
    }
  }
  if (
    object.details != null && typeof object.details === "object" &&
    "contexts" in object.details
  ) {
    const contexts = (object.details as Record<string, unknown>).contexts;
    if (!Array.isArray(contexts) || contexts.length > 2) {
      throw new ZigProjectProtocolError("Invalid diagnostic contexts");
    }
    object.contexts = contexts.map((item) => {
      const context = record(item, "diagnostic context");
      const kind = context.kind;
      if (
        kind !== "callee" && kind !== "argument" &&
        kind !== "left_operand" && kind !== "right_operand"
      ) throw new ZigProjectProtocolError("Invalid diagnostic context kind");
      const start = natural(
        context.span && record(context.span, "context span").start,
        "context start",
      );
      const end = natural(
        context.span && record(context.span, "context span").end,
        "context end",
      );
      if (start > end) {
        throw new ZigProjectProtocolError("Invalid diagnostic context offsets");
      }
      return {
        kind,
        filename: object.filename,
        start,
        end,
        offset_encoding: "utf8_bytes",
      };
    });
  }
  return object as unknown as ZigProjectDiagnostic;
}
function abortError(): DOMException {
  return new DOMException("Zig project build aborted", "AbortError");
}
interface Job {
  cancelled: boolean;
  active: boolean;
  reject(error: unknown): void;
  cleanup(): void;
}
interface Frame {
  metadata: Record<string, unknown>;
  payload: Uint8Array<ArrayBuffer>;
}

class ProjectProcess implements ZigProjectCompiler {
  readonly #child: Deno.ChildProcess;
  readonly #reader: ReadableStreamDefaultReader<Uint8Array<ArrayBuffer>>;
  readonly #writer: WritableStreamDefaultWriter<Uint8Array<ArrayBuffer>>;
  readonly #status: Promise<Deno.CommandStatus>;
  readonly #stderrDone: Promise<void>;
  readonly #jobs = new Set<Job>();
  #stderr = "";
  #buffer = new Uint8Array(0);
  #position = 0;
  #queue: Promise<void> = Promise.resolve();
  #terminal: Error | undefined;
  #accepting = true;
  #stopping: Promise<void> | undefined;
  #closing: Promise<void> | undefined;
  #identity = "";
  #sourceOverlays = false;
  #editorCompletion = false;
  #nativeAssets = false;
  #entry = "";
  #checkpoints = false;
  #epoch = "";
  #revision = 0;
  #nextId = 1;
  #exit: Deno.CommandStatus | undefined;

  constructor(
    executable: string,
    cacheEnvironment: Record<string, string>,
    semanticWorkers?: number,
    inferenceBudget?: number,
  ) {
    const args = ["serve-project"];
    if (semanticWorkers !== undefined) {
      args.push("--semantic-workers", String(semanticWorkers));
    }
    if (inferenceBudget !== undefined) {
      args.push("--inference-budget", String(inferenceBudget));
    }
    this.#child = new Deno.Command(executable, {
      args,
      clearEnv: true,
      env: cacheEnvironment,
      stdin: "piped",
      stdout: "piped",
      stderr: "piped",
    }).spawn();
    this.#reader = this.#child.stdout.getReader();
    this.#writer = this.#child.stdin.getWriter();
    this.#status = this.#child.status.then((status) => {
      this.#exit = status;
      return status;
    });
    this.#stderrDone = this.#collectStderr();
  }
  get pid() {
    return this.#child.pid;
  }
  get compilerIdentity() {
    return this.#identity;
  }
  async #collectStderr() {
    const decoder = new TextDecoder();
    try {
      for await (const bytes of this.#child.stderr) {
        this.#stderr = (this.#stderr + decoder.decode(bytes, { stream: true }))
          .slice(-65_536);
      }
    } finally {
      this.#stderr = (this.#stderr + decoder.decode()).slice(-65_536);
    }
  }
  #failure(error: unknown): Error {
    const text = error instanceof Error ? error.message : String(error);
    return new Error(
      `Zig project compiler${
        this.#exit ? ` (exit ${this.#exit.code})` : ""
      }: ${text}${this.#stderr ? `\n${this.#stderr.trimEnd()}` : ""}`,
      { cause: error },
    );
  }
  async #readExact(length: number): Promise<Uint8Array<ArrayBuffer>> {
    const result = new Uint8Array(length);
    let written = 0;
    while (written < length) {
      if (this.#position === this.#buffer.length) {
        const next = await this.#reader.read();
        if (next.done) {
          throw new ZigProjectProtocolError(
            "Unexpected EOF or truncated response frame",
          );
        }
        this.#buffer = next.value;
        this.#position = 0;
      }
      const count = Math.min(
        length - written,
        this.#buffer.length - this.#position,
      );
      result.set(
        this.#buffer.subarray(this.#position, this.#position + count),
        written,
      );
      written += count;
      this.#position += count;
    }
    return result;
  }
  async #readFrame(): Promise<Frame> {
    const header = await this.#readExact(8);
    const view = new DataView(header.buffer);
    const metadataLength = view.getUint32(0, true),
      payloadLength = view.getUint32(4, true);
    if (
      !metadataLength || metadataLength > maxMetadataBytes ||
      8 + metadataLength + payloadLength > maxFrameBytes
    ) {
      throw new ZigProjectProtocolError(
        "Response frame exceeds metadata/64 MiB limits",
      );
    }
    const text = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true })
      .decode(await this.#readExact(metadataLength));
    const metadata = record(JSON.parse(text), "response metadata");
    return { metadata, payload: await this.#readExact(payloadLength) };
  }
  #id(): number {
    if (this.#nextId > 0xffff_ffff) {
      throw new ZigProjectProtocolError("Request ID space exhausted");
    }
    return this.#nextId++;
  }
  async #exchange(
    metadata: Record<string, unknown>,
    payload: readonly Uint8Array<ArrayBuffer>[] = [],
  ): Promise<Frame> {
    const bytes = new TextEncoder().encode(JSON.stringify(metadata));
    const payloadLength = payload.reduce(
      (length, part) => length + part.length,
      0,
    );
    if (
      bytes.length > maxMetadataBytes ||
      bytes.length + payloadLength + 8 > maxFrameBytes
    ) {
      throw new RangeError("Request metadata exceeds protocol limit");
    }
    const header = new Uint8Array(8);
    new DataView(header.buffer).setUint32(0, bytes.length, true);
    new DataView(header.buffer).setUint32(4, payloadLength, true);
    await this.#writer.write(header);
    await this.#writer.write(bytes);
    for (const part of payload) await this.#writer.write(part);
    const frame = await this.#readFrame();
    if (
      frame.metadata.kind !== metadata.kind || frame.metadata.id !== metadata.id
    ) {
      throw new ZigProjectProtocolError(
        "Response operation or request ID mismatch",
      );
    }
    return frame;
  }
  async initialize(
    open: Record<string, unknown>,
    timeout: number,
    expectedIdentity?: string,
    checkpoint?: Uint8Array<ArrayBuffer>,
  ) {
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      await Promise.race([
        (async () => {
          const greeting = await this.#readFrame(), hello = greeting.metadata;
          if (
            greeting.payload.length || hello.kind !== "hello" ||
            hello.protocol !== "blot-zig-project" || hello.version !== 1 ||
            hello.maxFrameBytes !== maxFrameBytes ||
            typeof hello.compilerIdentity !== "string" ||
            !/^[0-9a-f]{64}$/.test(hello.compilerIdentity)
          ) throw new ZigProjectProtocolError("Zig project hello mismatch");
          const capabilities = hello.capabilities;
          if (
            !Array.isArray(capabilities) ||
            !["project-build", "utf8_bytes", "abort-disposes-process"].every(
              (capability) => capabilities.includes(capability),
            )
          ) {
            throw new ZigProjectProtocolError(
              "Unsupported Zig project capabilities",
            );
          }
          if (
            expectedIdentity && hello.compilerIdentity !== expectedIdentity
          ) throw new ZigProjectProtocolError("Compiler identity mismatch");
          this.#identity = hello.compilerIdentity;
          this.#sourceOverlays = capabilities.includes("source-overlays");
          this.#editorCompletion = capabilities.includes(
            "editor-completion-v1",
          );
          this.#checkpoints = capabilities.includes("backend-checkpoints");
          this.#nativeAssets = open.nativeAssets !== undefined;
          this.#entry = open.entry as string;
          if (
            this.#nativeAssets && !capabilities.includes("native-assets-v1")
          ) {
            throw new ZigProjectProtocolError(
              "Compiler does not support native assets",
            );
          }
          if (checkpoint && !this.#checkpoints) {
            throw new ZigProjectProtocolError(
              "Compiler does not support checkpoints",
            );
          }
          const response = await this.#exchange({
            kind: "open",
            id: this.#id(),
            version: 1,
            ...open,
          }, checkpoint ? [checkpoint] : []);
          if (
            response.payload.length ||
            typeof response.metadata.epoch !== "string" ||
            !response.metadata.epoch.length || response.metadata.revision !== 0
          ) {
            throw new ZigProjectProtocolError(
              "Invalid project open acknowledgement",
            );
          }
          this.#epoch = response.metadata.epoch;
        })(),
        new Promise<never>((_, reject) => {
          timer = setTimeout(
            () => reject(new Error("Zig project startup timed out")),
            timeout,
          );
        }),
      ]);
    } catch (error) {
      await this.dispose();
      throw this.#failure(error);
    } finally {
      clearTimeout(timer);
    }
  }
  #break(error: Error, cancelActive: boolean): void {
    this.#terminal ??= error;
    this.#accepting = false;
    for (const job of this.#jobs) {
      if (cancelActive || !job.active) {
        job.cancelled = true;
        job.reject(error);
        job.cleanup();
      }
    }
  }
  #shutdown(kill: boolean): Promise<void> {
    if (this.#stopping) return this.#stopping;
    return this.#stopping = (async () => {
      let timer: ReturnType<typeof setTimeout> | undefined;
      const stop = () => {
        if (!this.#exit) {
          try {
            this.#child.kill("SIGKILL");
          } catch (error) {
            // Deno can observe exit before our status callback runs. Its
            // ChildProcess then rejects kill with TypeError instead of ESRCH.
            const terminated = error instanceof TypeError &&
              /^Child process has already terminated\.?$/.test(error.message);
            if (!(error instanceof Deno.errors.NotFound) && !terminated) {
              throw error;
            }
          }
        }
      };
      if (kill) stop();
      else timer = setTimeout(stop, 1000);
      try {
        await Promise.allSettled([this.#writer.abort(), this.#reader.cancel()]);
        await this.#status;
        await this.#stderrDone;
      } finally {
        clearTimeout(timer);
        this.#writer.releaseLock();
        this.#reader.releaseLock();
      }
    })();
  }
  build(
    options: ZigProjectBuildOptions = {},
  ): Promise<ZigProjectBuildResult> {
    type Range = {
      path: string;
      start: number;
      length: number;
      deleted: boolean;
    };
    const sources: Range[] = [];
    const assetSources: Range[] = [];
    const payload: Uint8Array<ArrayBuffer>[] = [];
    try {
      keys(record(options, "build options"), [
        "signal",
        "sources",
        "assetSources",
      ], "build");
      if (options.assetSources !== undefined && !this.#nativeAssets) {
        throw new TypeError(
          "assetSources requires a native asset session or parser wrapper",
        );
      }
      let start = 0;
      const capture = (value: unknown, ranges: Range[], rawAssets: boolean) => {
        if (value === undefined) return;
        const entries = Object.entries(record(value, "source overlays"));
        if (entries.length > 4096) {
          throw new RangeError("Too many source files");
        }
        if (!rawAssets && entries.length && !this.#sourceOverlays) {
          throw new TypeError("Compiler does not support source overlays");
        }
        const names = new Set<string>();
        for (const [raw, contents] of entries) {
          let name = path(raw, "source path");
          if (rawAssets) name = resolve(dirname(this.#entry), raw);
          if (names.has(name)) throw new TypeError("Duplicate source path");
          names.add(name);
          let bytes = new Uint8Array(0);
          if (contents !== null) {
            if (typeof contents === "string") {
              if (!rawAssets && !contents.isWellFormed()) {
                throw new TypeError(
                  "Source contents must be a well-formed string or null",
                );
              }
              bytes = new TextEncoder().encode(contents);
            } else if (rawAssets && contents instanceof Uint8Array) {
              bytes = new Uint8Array(contents);
            } else {
              throw new TypeError("Invalid source overlay contents");
            }
          }
          if (bytes.length > 16 * 1024 * 1024) {
            throw new RangeError("Source exceeds 16 MiB limit");
          }
          ranges.push({
            path: name,
            start,
            length: bytes.length,
            deleted: contents === null,
          });
          start += bytes.length;
          if (start + 8 > maxFrameBytes) {
            throw new RangeError("Source payload exceeds protocol limit");
          }
          if (bytes.length) payload.push(bytes);
        }
      };
      capture(options.sources, sources, false);
      capture(options.assetSources, assetSources, true);
      // Reserve maximum ID/revision spelling before queueing. Invalid input
      // cannot consume an ID or terminate the healthy process.
      const worstRequest: Record<string, unknown> = {
        kind: "build",
        id: 0xffff_ffff,
        epoch: this.#epoch,
        revision: Number.MAX_SAFE_INTEGER,
      };
      if (sources.length) worstRequest.sources = sources;
      if (assetSources.length) worstRequest.assetSources = assetSources;
      const metadata = new TextEncoder().encode(JSON.stringify(worstRequest));
      if (
        metadata.length > maxMetadataBytes ||
        metadata.length + start + 8 > maxFrameBytes
      ) {
        throw new RangeError("Source request exceeds protocol limit");
      }
    } catch (error) {
      return Promise.reject(error);
    }
    return this.#enqueue(options.signal, async (job) => {
      // The acknowledged revision is read here, after all prior replies.
      const request: Record<string, unknown> = {
        kind: "build",
        id: this.#id(),
        epoch: this.#epoch,
        revision: this.#revision,
      };
      if (sources.length) request.sources = sources;
      if (assetSources.length) request.assetSources = assetSources;
      const frame = await this.#exchange(request, payload);
      const metadata = frame.metadata,
        revision = natural(metadata.revision, "revision");
      if (
        metadata.epoch !== this.#epoch ||
        typeof metadata.success !== "boolean"
      ) {
        throw new ZigProjectProtocolError(
          "Response epoch or success mismatch",
        );
      }
      let value: ZigProjectBuildResult;
      if (metadata.success) {
        let nativeReply:
          | Awaited<ReturnType<typeof readNativeAssetReply>>
          | undefined;
        let wasm = frame.payload;
        if (this.#nativeAssets) {
          try {
            nativeReply = await readNativeAssetReply(
              metadata,
              frame.payload,
              (message) => {
                throw new ZigProjectProtocolError(message);
              },
            );
          } catch (error) {
            if (error instanceof Error) {
              throw new ZigProjectProtocolError(error.message);
            }
            throw error;
          }
          wasm = nativeReply.bytes;
        } else if (
          ["wasmBytes", "assets", "assetStats", "assetDependencies"].some((
            name,
          ) => metadata[name] !== undefined)
        ) {
          throw new ZigProjectProtocolError(
            "Unexpected native asset response",
          );
        }
        if (
          this.#revision === Number.MAX_SAFE_INTEGER ||
          revision !== this.#revision + 1 || !wasm.length ||
          !WebAssembly.validate(wasm)
        ) {
          throw new ZigProjectProtocolError(
            "Invalid successful revision or Wasm payload",
          );
        }
        value = {
          success: true,
          revision,
          bytes: wasm,
          stats: buildStats(metadata.stats),
          ...nativeReply,
        };
      } else {
        if (
          revision !== this.#revision || frame.payload.length ||
          !Array.isArray(metadata.diagnostics) ||
          !metadata.diagnostics.length
        ) {
          throw new ZigProjectProtocolError(
            "Invalid rejected build response",
          );
        }
        value = {
          success: false,
          revision,
          diagnostics: metadata.diagnostics.map(diagnostic),
          attemptStats: metadata.attemptStats === null
            ? null
            : stats(metadata.attemptStats, "attemptStats"),
        };
      }
      if (!job.cancelled) this.#revision = revision;
      return value;
    });
  }
  #enqueue<Result>(
    signal: AbortSignal | undefined,
    operation: (job: Job) => Promise<Result>,
  ): Promise<Result> {
    if (signal !== undefined && !(signal instanceof AbortSignal)) {
      return Promise.reject(new TypeError("signal must be an AbortSignal"));
    }
    if (signal?.aborted) return Promise.reject(abortError());
    if (!this.#accepting) {
      return Promise.reject(
        this.#terminal ?? new Error("Zig project compiler is closing"),
      );
    }
    let job!: Job;
    return new Promise<Result>((resolve, reject) => {
      const onAbort = () => {
        job.cancelled = true;
        reject(abortError());
        job.cleanup();
        if (job.active) {
          this.#break(abortError(), true);
          void this.#shutdown(true);
        }
      };
      job = {
        cancelled: false,
        active: false,
        reject,
        cleanup: () => {
          signal?.removeEventListener("abort", onAbort);
          this.#jobs.delete(job);
        },
      };
      this.#jobs.add(job);
      signal?.addEventListener("abort", onAbort, { once: true });
      const task = this.#queue.then(async () => {
        if (job.cancelled) return;
        if (this.#terminal) {
          reject(this.#terminal);
          job.cleanup();
          return;
        }
        job.active = true;
        try {
          const value = await operation(job);
          if (!job.cancelled) resolve(value);
        } catch (error) {
          let failure = error;
          if (!(failure instanceof Error)) failure = new Error(String(failure));
          this.#break(failure as Error, false);
          await this.#shutdown(true);
          if (!job.cancelled) reject(this.#failure(error));
        } finally {
          job.active = false;
          job.cleanup();
        }
      });
      this.#queue = task.then(() => {}, () => {});
    });
  }
  complete(
    options: ZigProjectCompletionOptions,
  ): Promise<ZigProjectCompletionResult> {
    let filename: string;
    const ranges: {
      path: string;
      start: number;
      length: number;
      deleted: boolean;
    }[] = [];
    const payload: Uint8Array<ArrayBuffer>[] = [];
    const captured = new Map<string, Uint8Array<ArrayBuffer>>();
    try {
      if (!this.#editorCompletion) {
        throw new TypeError("Compiler does not support editor completion");
      }
      options = captureCompletion(
        options,
        (value) => path(value, "completion path"),
      );
      filename = options.filename as string;
      let length = 0;
      if (options.sources !== undefined) {
        const entries = Object.entries(
          record(options.sources, "completion sources"),
        );
        if (entries.length > 4096) {
          throw new RangeError("Too many source files");
        }
        const names = new Set<string>();
        for (const [raw, text] of entries) {
          const name = path(raw, "source path");
          if (names.has(name)) throw new TypeError("Duplicate source path");
          names.add(name);
          let bytes = new Uint8Array(0);
          if (text !== null) {
            if (typeof text !== "string" || !text.isWellFormed()) {
              throw new TypeError("Invalid completion source");
            }
            bytes = new TextEncoder().encode(text);
            captured.set(name, bytes);
          }
          if (bytes.length > 16 * 1024 * 1024) {
            throw new RangeError("Source exceeds 16 MiB");
          }
          ranges.push({
            path: name,
            start: length,
            length: bytes.length,
            deleted: text === null,
          });
          length += bytes.length;
          if (bytes.length) payload.push(bytes);
        }
      }
      const source = captured.get(filename);
      if (
        source &&
        (options.position > source.length ||
          (options.position < source.length &&
            (source[options.position] & 0xc0) === 0x80))
      ) throw new RangeError("Invalid captured completion position");
      const metadata = new TextEncoder().encode(
        JSON.stringify({
          kind: "complete",
          id: 0xffff_ffff,
          epoch: this.#epoch,
          revision: Number.MAX_SAFE_INTEGER,
          snapshot: options.snapshot,
          filename,
          position: options.position,
          sources: ranges,
        }),
      );
      if (
        metadata.length > maxMetadataBytes ||
        metadata.length + length + 8 > maxFrameBytes
      ) throw new RangeError("Completion request exceeds protocol limit");
    } catch (error) {
      return Promise.reject(error);
    }
    // Capture primitive fields with the buffers; caller mutation cannot steer a queued query.
    const snapshot = options.snapshot, position = options.position;
    return this.#enqueue(options.signal, async () => {
      const echo = { revision: this.#revision, snapshot, filename, position };
      const frame = await this.#exchange({
        kind: "complete",
        id: this.#id(),
        epoch: this.#epoch,
        ...echo,
        sources: ranges,
      }, payload);
      return readCompletion(
        frame.metadata,
        echo,
        this.#epoch,
        frame.payload,
        captured.get(filename),
        diagnostic,
        (message) => {
          throw new ZigProjectProtocolError(message);
        },
      );
    });
  }
  exportCheckpoint(): Promise<Uint8Array<ArrayBuffer>> {
    if (!this.#checkpoints) {
      return Promise.reject(new Error("Compiler does not support checkpoints"));
    }
    if (!this.#accepting) {
      return Promise.reject(this.#terminal ?? new Error("Compiler is closing"));
    }
    const task = this.#queue.then(async () => {
      if (this.#terminal) throw this.#terminal;
      let frame: Frame;
      try {
        frame = await this.#exchange({
          kind: "checkpoint",
          id: this.#id(),
          epoch: this.#epoch,
          revision: this.#revision,
        });
        const metadata = frame.metadata;
        if (
          metadata.epoch !== this.#epoch ||
          metadata.revision !== this.#revision ||
          typeof metadata.success !== "boolean" ||
          (metadata.success
            ? frame.payload.length === 0
            : frame.payload.length !== 0 || typeof metadata.code !== "string")
        ) {
          throw new ZigProjectProtocolError(
            "Invalid checkpoint acknowledgement",
          );
        }
      } catch (error) {
        this.#break(
          error instanceof Error ? error : new Error(String(error)),
          true,
        );
        await this.#shutdown(true);
        throw this.#failure(error);
      }
      if (!frame.metadata.success) {
        throw new Error(`Unable to export checkpoint: ${frame.metadata.code}`);
      }
      return frame.payload;
    });
    this.#queue = task.then(() => {}, () => {});
    return task;
  }
  close(): Promise<void> {
    if (this.#closing) return this.#closing;
    if (this.#terminal) return this.dispose();
    this.#accepting = false;
    return this.#closing = this.#queue.then(async () => {
      if (this.#terminal) {
        await this.#shutdown(true);
        return;
      }
      try {
        const response = await this.#exchange({
          kind: "close",
          id: this.#id(),
          epoch: this.#epoch,
          revision: this.#revision,
        });
        if (
          response.payload.length || response.metadata.epoch !== this.#epoch ||
          response.metadata.revision !== this.#revision
        ) throw new ZigProjectProtocolError("Invalid close acknowledgement");
        await this.#writer.close();
        this.#terminal = new Error("Zig project compiler is closed");
        await this.#shutdown(false);
        if (!this.#exit?.success) {
          throw new Error("Zig project compiler failed during close");
        }
      } catch (error) {
        this.#break(
          error instanceof Error ? error : new Error(String(error)),
          true,
        );
        await this.#shutdown(true);
        throw this.#failure(error);
      }
    });
  }
  dispose(): Promise<void> {
    this.#break(new Error("Zig project compiler is disposed"), true);
    return this.#shutdown(true);
  }
}

export async function createZigProjectCompiler(
  options: ZigProjectCompilerOptions,
): Promise<ZigProjectCompiler> {
  const object = record(options, "compiler options");
  keys(object, [
    "executable",
    "entry",
    "prelude",
    "stdRoot",
    "imports",
    "dependencies",
    "profileBackend",
    "explainDemands",
    "codegenTier",
    "shareMachineCode",
    "codegenWorkers",
    "semanticWorkers",
    "inferenceBudget",
    "checkpoint",
    "cacheDirectory",
    "startupTimeoutMs",
    "expectedCompilerIdentity",
    "assets",
    "nativeAssets",
  ], "compiler");
  const executable = path(options.executable, "executable"),
    entry = path(options.entry, "entry");
  const assets = captureAssetImports(options.assets);
  if (options.assets !== undefined && options.nativeAssets !== undefined) {
    throw new TypeError("assets and nativeAssets cannot be used together");
  }
  const nativeAssets = captureNativeAssets(options.nativeAssets, entry);
  if (
    options.checkpoint !== undefined &&
    !(options.checkpoint instanceof Uint8Array)
  ) {
    throw new TypeError("checkpoint must contain bytes from exportCheckpoint");
  }
  if (
    options.checkpoint !== undefined &&
    (options.checkpoint.length === 0 ||
      options.checkpoint.length > maxFrameBytes - maxMetadataBytes - 8)
  ) {
    throw new RangeError("Checkpoint payload exceeds protocol limits");
  }
  const checkpoint = options.checkpoint && new Uint8Array(options.checkpoint);
  if (
    options.profileBackend !== undefined &&
    typeof options.profileBackend !== "boolean"
  ) {
    throw new TypeError("profileBackend must be a boolean");
  }
  if (
    options.explainDemands !== undefined &&
    typeof options.explainDemands !== "boolean"
  ) {
    throw new TypeError("explainDemands must be a boolean");
  }
  if (
    options.codegenTier !== undefined &&
    options.codegenTier !== "optimized" && options.codegenTier !== "development"
  ) {
    throw new TypeError("codegenTier must be optimized or development");
  }
  if (
    options.shareMachineCode !== undefined &&
    typeof options.shareMachineCode !== "boolean"
  ) {
    throw new TypeError("shareMachineCode must be a boolean");
  }
  if (
    options.codegenWorkers !== undefined &&
    (!Number.isInteger(options.codegenWorkers) || options.codegenWorkers < 1 ||
      options.codegenWorkers > 16)
  ) {
    throw new RangeError("codegenWorkers must be an integer in 1..16");
  }
  if (
    options.semanticWorkers !== undefined &&
    (!Number.isInteger(options.semanticWorkers) ||
      options.semanticWorkers < 1 || options.semanticWorkers > 16)
  ) {
    throw new RangeError("semanticWorkers must be an integer in 1..16");
  }
  const nullablePath = (value: unknown, name: string) =>
    value == null ? null : path(value, name);
  const imports = options.imports === undefined
    ? []
    : Object.entries(record(options.imports, "imports")).map(
      ([prefix, root]) => {
        if (
          !prefix.length || !prefix.endsWith("/") || prefix.includes("\0") ||
          !prefix.isWellFormed()
        ) throw new TypeError("Import prefix must end in /");
        return { prefix, root: path(root, "import root") };
      },
    );
  const open: Record<string, unknown> = {
    entry,
    prelude: nullablePath(options.prelude, "prelude"),
    stdRoot: nullablePath(options.stdRoot, "stdRoot"),
    imports,
    dependencies: nullablePath(options.dependencies, "dependencies"),
    ...(checkpoint ? { checkpoint: true } : {}),
    ...(options.profileBackend ? { profileBackend: true } : {}),
    ...(options.explainDemands ? { explainDemands: true } : {}),
    ...(options.codegenTier ? { codegenTier: options.codegenTier } : {}),
    ...(options.shareMachineCode ? { shareMachineCode: true } : {}),
    ...(options.codegenWorkers
      ? { codegenWorkers: options.codegenWorkers }
      : {}),
  };
  if (nativeAssets !== undefined) open.nativeAssets = nativeAssets;
  const timeout = options.startupTimeoutMs ?? 30_000;
  if (!Number.isInteger(timeout) || timeout < 1 || timeout > 300_000) {
    throw new RangeError("startupTimeoutMs must be 1..300000");
  }
  const identity = options.expectedCompilerIdentity;
  if (
    identity !== undefined &&
    (typeof identity !== "string" || !/^[0-9a-f]{64}$/.test(identity))
  ) {
    throw new TypeError(
      "expectedCompilerIdentity must be 64 lowercase hex characters",
    );
  }
  if (
    new TextEncoder().encode(
      JSON.stringify({ kind: "open", id: 1, version: 1, ...open }),
    )
      .length > maxMetadataBytes
  ) throw new RangeError("Open metadata exceeds 1 MiB");
  const cacheEnvironment: Record<string, string> = {};
  if (options.cacheDirectory !== undefined) {
    cacheEnvironment.BLOT_CACHE_DIR = options.cacheDirectory === false
      ? ""
      : path(options.cacheDirectory, "cache directory");
  } else {
    // Preserve the isolated child environment. Only cache-location variables
    // that the caller can already read are forwarded; never prompt for access.
    for (
      const variable of [
        "BLOT_CACHE_DIR",
        "XDG_CACHE_HOME",
        "HOME",
        "LOCALAPPDATA",
      ]
    ) {
      if (
        Deno.permissions.querySync({ name: "env", variable }).state !==
          "granted"
      ) continue;
      const value = Deno.env.get(variable);
      if (value !== undefined) cacheEnvironment[variable] = value;
    }
  }
  if (
    options.inferenceBudget !== undefined &&
    (!Number.isSafeInteger(options.inferenceBudget) ||
      options.inferenceBudget < 1)
  ) {
    throw new RangeError("inferenceBudget must be a positive safe integer");
  }
  const process = new ProjectProcess(
    executable,
    cacheEnvironment,
    options.semanticWorkers,
    options.inferenceBudget,
  );
  await process.initialize(open, timeout, identity, checkpoint);
  if (assets !== undefined) {
    try {
      return await withAssetImports(process, entry, assets);
    } catch (error) {
      await process.dispose();
      throw error;
    }
  }
  return process;
}
