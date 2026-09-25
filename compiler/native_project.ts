import { bendArray, bendList } from "./bend_list.ts";
import {
  type AnalyzedArtifact,
  type AnalyzedArtifactOptions,
  type Artifact,
  type ArtifactOptions,
  type CompileOptions,
  includesAnalysis,
} from "./host.ts";
import { sameDeclaration } from "./native_incremental.ts";
import type { NativeCompilerOptions } from "./native.ts";
import { NativeProcess } from "./native_process.ts";
import {
  decodeNativeSessionResponse,
  encodeNativeSessionRequest,
  type NativeCacheStats,
  type NativeOperation,
  NativeProtocolError,
  type NativeResponse,
} from "./native_protocol.ts";
import { createProjectFrontend } from "./project_frontend.ts";
import {
  createSourceProjectLoader,
  type ProjectOptions,
  type SourceProject,
} from "./source_project.ts";
import type { Cst } from "./syntax.ts";

export interface NativeProjectOptions
  extends NativeCompilerOptions, ProjectOptions {
  /** Maximum native analyze/compile requests per process before recycling. */
  readonly maxRevisions?: number;
}
export interface NativeProjectStats extends NativeCacheStats {
  readonly result_reused: boolean;
  readonly session_restarted: boolean;
  readonly total_ms: number;
  readonly project_ms: number;
  readonly declarations_sent: number;
  readonly declarations_retained: number;
}

/** One transaction retains a project's syntax, specialization, checks and code. */
export async function createNativeProjectCompiler(
  options: NativeProjectOptions = {},
) {
  const maxRevisions = options.maxRevisions ?? 16;
  if (!Number.isInteger(maxRevisions) || maxRevisions < 1) {
    throw new RangeError("maxRevisions must be a positive integer");
  }
  const processOptions = {
    executable: options.executable instanceof URL
      ? new URL(options.executable)
      : options.executable,
    threads: options.threads,
    priority: options.priority,
  };
  const frontend = await createProjectFrontend(options);
  let loader: Awaited<ReturnType<typeof createSourceProjectLoader>>;
  try {
    loader = await createSourceProjectLoader({
      ...options,
      imports: options.imports && Object.fromEntries(
        Object.entries(options.imports).map((
          [key, value],
        ) => [key, new URL(value)]),
      ),
    });
  } catch (error) {
    frontend.dispose();
    throw error;
  }
  async function startSession(): Promise<NativeProcess> {
    const process = await NativeProcess.start(processOptions);
    try {
      const response = decodeNativeSessionResponse(
        await process.request(encodeNativeSessionRequest({
          operation: "open",
          prelude: frontend.prelude,
          fuel: frontend.preludeCount,
        })),
      );
      if (!("operation" in response) || response.operation !== "open") {
        throw new NativeProtocolError(
          "Native compiler did not open a project session",
        );
      }
      return process;
    } catch (error) {
      await process.dispose();
      throw error;
    }
  }
  let native: NativeProcess;
  try {
    native = await startSession();
  } catch (error) {
    frontend.dispose();
    loader.dispose();
    return frontend.translatePrelude(error);
  }
  let closed = false;
  let queue: Promise<void> = Promise.resolve();
  let stopping: Promise<void> | undefined;
  let acknowledged = new Map<bigint, Cst>();
  let nativeRevisions = 0;
  let previous: {
    root: Cst;
    operation: NativeOperation;
    steps: bigint;
    result: NativeResponse;
    stats: NativeCacheStats;
  } | undefined;
  function stop() {
    if (stopping) return stopping;
    closed = true;
    acknowledged.clear();
    previous = undefined;
    loader.dispose();
    frontend.dispose();
    stopping = native.dispose();
    return stopping;
  }
  async function recycle(): Promise<void> {
    try {
      await native.dispose();
      if (closed) throw new Error("Native project compiler is disposed");
      const replacement = await startSession();
      if (closed) {
        await replacement.dispose();
        throw new Error("Native project compiler is disposed");
      }
      native = replacement;
      acknowledged.clear();
      nativeRevisions = 0;
    } catch (error) {
      await stop();
      throw error;
    }
  }
  function run(
    operation: NativeOperation,
    input: SourceProject | string | URL,
    options: CompileOptions,
  ) {
    if (closed) throw new Error("Native project compiler is disposed");
    const steps = options.const_steps ?? 10_000n;
    if (typeof steps !== "bigint" || steps < 0n || steps > 0xFFFF_FFFF_FFFFn) {
      throw new RangeError("const_steps must be a Nat (0..2^48-1)");
    }
    // Snapshot caller-owned project trees and URLs before waiting for earlier work.
    const source = typeof input === "string"
      ? input
      : input instanceof URL
      ? new URL(input)
      : structuredClone(input);
    const started = performance.now();
    const task = queue.then(async () => {
      if (closed) throw new Error("Native project compiler is disposed");
      const projectStarted = performance.now();
      const project = typeof source === "string" || source instanceof URL
        ? await loader.load(source)
        : source;
      const prepared = frontend.prepare(project);
      const projectMs = performance.now() - projectStarted;
      try {
        if (
          previous?.operation === operation && previous.steps === steps &&
          sameDeclaration(previous.root, prepared.root)
        ) {
          const prior = previous.stats;
          return {
            result: structuredClone(previous.result),
            stats: {
              declarations_lowered: 0,
              declarations_reused: prior.declarations_lowered +
                prior.declarations_reused,
              groups_checked: 0,
              groups_reused: prior.groups_checked + prior.groups_reused,
              constants_evaluated: 0,
              constants_reused: prior.constants_evaluated +
                prior.constants_reused,
              entries_compiled: 0,
              entries_reused: prior.entries_compiled + prior.entries_reused,
              result_reused: true,
              session_restarted: false,
              project_ms: projectMs,
              total_ms: performance.now() - started,
              declarations_sent: 0,
              declarations_retained: prepared.declarations.length,
            } satisfies NativeProjectStats,
          };
        }
        const restarted = nativeRevisions >= maxRevisions;
        if (restarted) await recycle();
        if (closed) throw new Error("Native project compiler is disposed");
        let sent = 0;
        let retained = 0;
        const next = new Map(
          prepared.declarations.map((node) => [node.offset, node]),
        );
        const patched: Cst = {
          ...prepared.root,
          children: bendList(
            bendArray(prepared.root.children).map((module) => ({
              ...module,
              children: bendList(
                bendArray(module.children).map((body) => ({
                  ...body,
                  children: bendList(
                    bendArray(body.children).map((node) => {
                      if (node.field !== "declarations") return node;
                      const prior = acknowledged.get(node.offset);
                      if (prior && sameDeclaration(prior, node)) {
                        retained++;
                        return {
                          ...node,
                          kind: "retained_declaration",
                          text: "",
                          children: bendList([]),
                        };
                      }
                      sent++;
                      return node;
                    }),
                  ),
                })),
              ),
            })),
          ),
        };
        const request = encodeNativeSessionRequest({
          operation,
          root: patched,
          fuel: prepared.nodeCount,
          const_steps: steps,
        });
        nativeRevisions++;
        const response = decodeNativeSessionResponse(
          await native.request(request),
        );
        if (
          !("result" in response) || response.result.operation !== operation
        ) {
          throw new NativeProtocolError(
            "Native project session returned a different operation",
          );
        }
        if (closed) throw new Error("Native project compiler is disposed");
        acknowledged = next;
        previous = {
          root: prepared.root,
          operation,
          steps,
          result: response.result,
          stats: response.stats,
        };
        return {
          result: structuredClone(response.result),
          stats: {
            ...response.stats,
            result_reused: false,
            session_restarted: restarted,
            project_ms: projectMs,
            total_ms: performance.now() - started,
            declarations_sent: sent,
            declarations_retained: retained,
          } satisfies NativeProjectStats,
        };
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
    source: SourceProject | string | URL,
    options?: AnalyzedArtifactOptions,
  ): Promise<{ artifact: AnalyzedArtifact; stats: NativeProjectStats }>;
  function compile(
    source: SourceProject | string | URL,
    options?: ArtifactOptions,
  ): Promise<{ artifact: Artifact; stats: NativeProjectStats }>;
  async function compile(
    source: SourceProject | string | URL,
    options: ArtifactOptions = {},
  ): Promise<{ artifact: Artifact; stats: NativeProjectStats }> {
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
    compile,
    async analyze(
      source: SourceProject | string | URL,
      options: CompileOptions = {},
    ) {
      const { result, stats } = await run("analyze", source, options);
      if (result.operation !== "analyze") {
        throw new Error("Expected native analysis");
      }
      return { analysis: result.analysis, stats };
    },
    async dispose() {
      await stop();
      await queue;
    },
  };
}
