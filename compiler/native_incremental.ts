import { includesAnalysis } from "./artifact_options.ts";
import type {
  AnalyzedArtifact,
  AnalyzedArtifactOptions,
  Artifact,
  ArtifactOptions,
  CompileOptions,
} from "./host.ts";
import { bendArray } from "./bend_list.ts";
import {
  createIncrementalFrontend,
  type IncrementalSyntaxStats,
} from "./incremental_frontend.ts";
import type { NativeCompilerOptions } from "./native.ts";
import { NativeProcess } from "./native_process.ts";
import {
  decodeNativeSessionResponse,
  encodeNativeSessionRequest,
  type NativeCacheStats,
  type NativeDeclaration,
  type NativeOperation,
  NativeProtocolError,
  type NativeResponse,
} from "./native_protocol.ts";
import type { Cst } from "./syntax.ts";

export interface NativeIncrementalStats
  extends NativeCacheStats, IncrementalSyntaxStats {
  readonly parsed_ms: number;
  readonly result_reused: boolean;
  /** Frontend, IPC, native compiler, and decoding; excludes process startup. */
  readonly total_ms: number;
}

export function sameDeclaration(left: Cst, right: Cst): boolean {
  if (left === right) return true;
  const pending: [Cst, Cst][] = [[left, right]];
  for (let pair = pending.pop(); pair; pair = pending.pop()) {
    const [a, b] = pair;
    if (a === b) continue;
    if (
      a.kind !== b.kind || a.field !== b.field || a.text !== b.text ||
      a.offset !== b.offset
    ) return false;
    let xs = a.children;
    let ys = b.children;
    while (xs.$ === "Con" && ys.$ === "Con") {
      pending.push([xs.head, ys.head]);
      xs = xs.tail;
      ys = ys.tail;
    }
    if (xs.$ !== ys.$) return false;
  }
  return true;
}

/** One native process retains one transactional lowering/type/const/code cache. */
export async function createNativeIncrementalCompiler(
  options: NativeCompilerOptions = {},
) {
  const configured: NativeCompilerOptions = {
    ...options,
    executable: options.executable instanceof URL
      ? new URL(options.executable)
      : options.executable,
  };
  const frontend = await createIncrementalFrontend(configured);
  let process: NativeProcess | undefined;
  try {
    process = await NativeProcess.start(configured);
    const response = decodeNativeSessionResponse(
      await process.request(encodeNativeSessionRequest({
        operation: "open",
        prelude: frontend.prelude,
        fuel: frontend.preludeCount,
      })),
    );
    if (!("operation" in response) || response.operation !== "open") {
      throw new NativeProtocolError("Native compiler did not open a session");
    }
  } catch (error) {
    frontend.dispose();
    await process?.dispose();
    return frontend.translatePrelude(error);
  }
  const native = process;
  let closed = false;
  let acknowledged = new Map<bigint, Cst>();
  let queue: Promise<void> = Promise.resolve();
  let stopping: Promise<void> | undefined;
  let previous: {
    readonly operation: NativeOperation;
    readonly source: string;
    readonly steps: bigint;
    readonly root: Cst;
    readonly result: NativeResponse;
    readonly stats: NativeCacheStats;
  } | undefined;

  function stop() {
    if (stopping) return stopping;
    closed = true;
    acknowledged.clear();
    previous = undefined;
    frontend.dispose();
    stopping = native.dispose();
    return stopping;
  }

  async function dispose() {
    await stop();
    await queue;
  }

  function run(
    operation: NativeOperation,
    source: string,
    options: CompileOptions,
  ) {
    if (closed) throw new Error("Native incremental compiler is disposed");
    const steps = options.const_steps ?? 10_000n;
    if (typeof steps !== "bigint" || steps < 0n || steps > 0xFFFFFFFFFFFFn) {
      throw new RangeError("const_steps must be a Nat (0..2^48-1)");
    }
    const started = performance.now();
    // Diff against the last successful reply, never a merely attempted or
    // queued edit. Snapshot options before waiting so caller mutation is inert.
    const task = queue.then(async () => {
      if (closed) throw new Error("Native incremental compiler is disposed");
      const reusable = previous?.operation === operation &&
          previous.steps === steps
        ? previous
        : undefined;
      const reuse = (
        syntax: IncrementalSyntaxStats,
        parsed_ms: number,
      ) => {
        const prior = reusable!.stats;
        const result = structuredClone(reusable!.result);
        const stats: NativeIncrementalStats = {
          declarations_lowered: 0,
          declarations_reused: prior.declarations_lowered +
            prior.declarations_reused,
          groups_checked: 0,
          groups_reused: prior.groups_checked + prior.groups_reused,
          constants_evaluated: 0,
          constants_reused: prior.constants_evaluated + prior.constants_reused,
          entries_compiled: 0,
          entries_reused: prior.entries_compiled + prior.entries_reused,
          ...syntax,
          parsed_ms,
          result_reused: true,
          total_ms: performance.now() - started,
        };
        previous = { ...reusable!, source };
        return { result, stats };
      };
      if (reusable?.source === source) {
        return reuse({
          source_reused: true,
          islands_parsed: 0,
          islands_reused: bendArray(reusable.root.children).length,
          full_parses: 0,
          characters_lexed: 0,
          characters_reused: source.length,
        }, 0);
      }
      const prepared = frontend.prepare(source);
      try {
        if (reusable && sameDeclaration(reusable.root, prepared.root)) {
          return reuse(prepared.syntax, prepared.parsed_ms);
        }
        const next = new Map<bigint, Cst>();
        const declarations = bendArray(prepared.root.children).map(
          (node): NativeDeclaration => {
            next.set(node.offset, node);
            const previous = acknowledged.get(node.offset);
            return previous && sameDeclaration(previous, node)
              ? { kind: "retained", identity: node.offset }
              : { kind: "replaced", node };
          },
        );
        const response = decodeNativeSessionResponse(
          await native.request(encodeNativeSessionRequest({
            operation,
            declarations,
            fuel: prepared.nodeCount,
            const_steps: steps,
          })),
        );
        if (
          !("result" in response) || response.result.operation !== operation
        ) {
          throw new NativeProtocolError(
            "Native session returned a different operation",
          );
        }
        if (closed) throw new Error("Native incremental compiler is disposed");
        acknowledged = next;
        previous = {
          operation,
          source,
          steps,
          root: prepared.root,
          result: response.result,
          stats: response.stats,
        };
        // Cache only successful, privately owned replies. No returned array or
        // expression tree can mutate a later cache hit.
        const result = structuredClone(response.result);
        const stats: NativeIncrementalStats = {
          ...response.stats,
          ...prepared.syntax,
          parsed_ms: prepared.parsed_ms,
          result_reused: false,
          total_ms: performance.now() - started,
        };
        return { result, stats };
      } catch (error) {
        if (error instanceof NativeProtocolError) await stop();
        return prepared.translate(error);
      }
    });
    queue = task.then(() => {}, () => {});
    return task;
  }

  /** With `analysis: false` the artifact carries only the Wasm bytes. */
  function compile(
    source: string,
    options?: AnalyzedArtifactOptions,
  ): Promise<{ artifact: AnalyzedArtifact; stats: NativeIncrementalStats }>;
  function compile(
    source: string,
    options?: ArtifactOptions,
  ): Promise<{ artifact: Artifact; stats: NativeIncrementalStats }>;
  async function compile(
    source: string,
    options: ArtifactOptions = {},
  ): Promise<{ artifact: Artifact; stats: NativeIncrementalStats }> {
    const operation = includesAnalysis(options) ? "compile" : "emit";
    const { result, stats } = await run(operation, source, options);
    switch (result.operation) {
      case "compile":
        return { artifact: result.artifact, stats };
      case "emit":
        return { artifact: { bytes: result.bytes }, stats };
      default:
        throw new Error("Expected native artifact");
    }
  }
  return {
    async analyze(source: string, options: CompileOptions = {}) {
      const { result, stats } = await run("analyze", source, options);
      if (result.operation !== "analyze") {
        throw new Error("Expected native analysis");
      }
      return { analysis: result.analysis, stats };
    },
    compile,
    dispose,
  };
}
