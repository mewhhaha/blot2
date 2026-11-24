// Unified Blot vNext Warm Work-Stealing `KernelPool` for Deno (§5.1).
//
// Guarantees:
// - Pre-instantiation private-copy `MemoryShape` & `CompiledModuleReceipt` admission
// - True 1x peak `runFixed` via single preallocated `outputBuf` + serialized BYOB reads
// - 1x peak `runVariableChunks` and <= 2x peak `runVariable` with `PendingFrontierGrant` drain
// - Worker-count-independent `transport_budget`-bounded chunking & unified `[0xffffffff]` transition
// - Same-`start_item` precedence (`RunTrap`/`SingleItemOutputOverflow`/`OutOfMemory` > `OutputBudgetExceeded` > `CleanupTrap`)
// - Used-`Store` physical fragmentation retire-and-retry-once-fresh via Page-0 offset 640 (`ARENA_OOM`)
// - Strict parser-vs-coordinator split, closed registration gate & kill-first 5-step `retireSubprocess`
// - Preemptible off-thread subprocess execution for ALL `deadlineMs !== undefined` paths
//   (`workers >= 1`, `workers == 0` direct, serial fallback, AND standalone `setContext`/`clearContext`)
// - Unified single-owner pool lifecycle (`#state`, `#poolEpoch`, `#activeOp`, `#closePromise`)

import {
  ARENA_OOM_OFFSET,
  type CompiledModuleReceipt,
  copyPrivateBytes,
  DEFAULT_TRANSPORT_BUDGET,
  type KernelManifest,
  resolveValidatedModule,
  type ValidatedModuleMeta,
} from "./guest.ts";

const CMD_INIT = 1;
const CMD_SET_CTX = 2;
const CMD_CLEAR_CTX = 3;
const CMD_RUN = 4;
const CMD_COPY_GRANT = 5;
const CMD_DISCARD = 6;

const TAG_INIT_OK = 1;
const TAG_INIT_FAIL = 2;
const TAG_CTX_OK = 3;
const TAG_READY = 4;
const TAG_OVERFLOW_OK = 5;
const TAG_OVERFLOW_CLEANUP_FAIL = 6;
const TAG_DISCARD_OK = 7;
const TAG_DATA_FRAME = 8;
const TAG_COMMIT_OK = 9;
const TAG_CLEANUP_FAIL = 10;
const TAG_ARENA_OOM = 11;
const TAG_RUN_TRAP = 12;

const MAX_DEADLINE_MS = 2_147_483_647;
const WORKER_SCRIPT_URL = new URL("./kernel_worker.ts", import.meta.url);

export type KernelErrorCode =
  | "invalid_config"
  | "unknown_kernel"
  | "memory_limit_unbounded"
  | "memory_limit_exceeded"
  | "pool_closed"
  | "batch_in_progress"
  | "context_operation_in_progress"
  | "context_not_prepared"
  | "revision_content_mismatch"
  | "invalid_input"
  | "input_snapshot_budget_exceeded"
  | "output_budget_exceeded"
  | "single_item_output_overflow"
  | "out_of_memory"
  | "run_trap"
  | "cleanup_trap"
  | "timeout"
  | "transport_fault"
  | "pool_exhausted";

export class KernelError extends Error {
  constructor(
    readonly code: KernelErrorCode,
    message: string,
    readonly startItem?: number,
    options?: ErrorOptions,
  ) {
    super(message, options);
    this.name = "KernelError";
  }
}

export interface KernelTestHooks {
  /** Override child worker module URL (e.g., fault-injection worker script). */
  workerScriptUrl?: URL;
  /** Async pause/hook right after a worker reports READY (before grant/discard). */
  onAfterReady?: (info: {
    start: number;
    end: number;
    resultBytes: number;
    workerIndex: number;
  }) => Promise<void> | void;
  /** Async pause/hook right after fixed grant is issued (outputBuf transferred). */
  onAfterFixedGrantIssued?: (info: {
    start: number;
    end: number;
    workerIndex: number;
  }) => Promise<void> | void;
  /** Async pause/hook right after variable grant is issued. */
  onAfterVariableGrantIssued?: (info: {
    start: number;
    end: number;
    resultBytes: number;
    workerIndex: number;
  }) => Promise<void> | void;
  /** Hook right before variable concatenation publishes final result. */
  onBeforeConcatPublish?: () => Promise<void> | void;
  /** Hook right before setContext/clearContext publishes new snapshot. */
  onBeforeContextPublish?: () => Promise<void> | void;
  /** Hook capturing a premature timer callback so tests can invoke it early. */
  onTimerArmed?: (info: {
    deadlineMs: number;
    fire: () => void;
  }) => void;
  /** Force a worker's BYOB read to reject (simulating stream/buffer detachment). */
  injectByobReadError?: boolean;
  /** Force serial fallback from a workers >= 1 pool. */
  forceFallback?: boolean;
  /** Expose per-subprocess parser/retirement trace for assertions. */
  onSubprocessRetired?: (info: {
    workerIndex: number;
    exitCode: number | null;
    signal: Deno.Signal | null;
    terminalKind: string;
  }) => void;
  /** Simulate post-READY cleanup failure on a specific start_item. */
  forceCleanupFailAtStart?: Set<number>;
  /** Inject a delay (ms) before emitting a frame / before parser delivers a frame. */
  delayFrameDeliveryMs?: number;
}

export interface KernelPoolConfig {
  readonly workers?: number;
  readonly deadlineMs?: number;
  readonly memory?: number;
  readonly maxTotalOutputBytes?: number;
  readonly maxPhysicalOutputBytes?: number;
  readonly maxInputSnapshotBytes?: number;
  readonly defaultChunkItems?: number;
  readonly retireMemoryThreshold?: number;
  readonly maxRetiredInFlight?: number;
  readonly _testHooks?: KernelTestHooks;
}

export interface KernelPoolStats {
  readonly peakChargedBytes: number;
  readonly currentChargedBytes: number;
  readonly inputSnapshotBytes: number;
  readonly contextSnapshotBytes: number;
  readonly fixedOutputBytes: number;
  readonly bufferedChunkBytes: number;
  readonly inFlightGrantBytes: number;
  readonly workerMemoryBytes: number;
  readonly freshRetries: number;
  readonly fallbacks: number;
  readonly activeSubprocesses: number;
  readonly retiredSubprocesses: number;
}

interface PreparedContextSnapshot {
  readonly snapshotId: number;
  readonly revision: bigint;
  readonly bytes: Uint8Array<ArrayBuffer>;
}

interface WorkRange {
  readonly start: number;
  readonly end: number;
  retriedFresh: boolean;
}

type FailureKind =
  | { kind: "run_trap"; message: string }
  | { kind: "single_item_output_overflow"; message: string }
  | { kind: "out_of_memory"; message: string }
  | { kind: "output_budget_exceeded"; message: string }
  | { kind: "cleanup_trap"; message: string; resultBytes: number };

function failurePriority(f: FailureKind): number {
  switch (f.kind) {
    case "run_trap":
    case "single_item_output_overflow":
    case "out_of_memory":
      return 3;
    case "output_budget_exceeded":
      return 2;
    case "cleanup_trap":
      return 1;
  }
}

function toKernelError(start: number, f: FailureKind): KernelError {
  return new KernelError(f.kind, f.message, start);
}

class MinRangeHeap {
  readonly #items: WorkRange[] = [];

  get size(): number {
    return this.#items.length;
  }

  push(range: WorkRange): void {
    this.#items.push(range);
    let idx = this.#items.length - 1;
    while (idx > 0) {
      const parent = (idx - 1) >> 1;
      if (this.#items[parent].start <= this.#items[idx].start) break;
      const tmp = this.#items[parent];
      this.#items[parent] = this.#items[idx];
      this.#items[idx] = tmp;
      idx = parent;
    }
  }

  pop(): WorkRange | undefined {
    const n = this.#items.length;
    if (n === 0) return undefined;
    const top = this.#items[0];
    const last = this.#items.pop()!;
    if (n > 1) {
      this.#items[0] = last;
      let idx = 0;
      for (;;) {
        const left = idx * 2 + 1;
        const right = left + 1;
        let smallest = idx;
        if (
          left < this.#items.length &&
          this.#items[left].start < this.#items[smallest].start
        ) {
          smallest = left;
        }
        if (
          right < this.#items.length &&
          this.#items[right].start < this.#items[smallest].start
        ) {
          smallest = right;
        }
        if (smallest === idx) break;
        const tmp = this.#items[idx];
        this.#items[idx] = this.#items[smallest];
        this.#items[smallest] = tmp;
        idx = smallest;
      }
    }
    return top;
  }

  dropAtOrAbove(limitStart: number): void {
    if (this.#items.length === 0) return;
    const kept = this.#items.filter((r) => r.start < limitStart);
    this.#items.length = 0;
    for (const r of kept) this.push(r);
  }

  clear(): void {
    this.#items.length = 0;
  }
}

type TransportOutcome =
  | { kind: "fenced" }
  | { kind: "fault"; reason: string }
  | { kind: "init_ok"; memoryBytes: number }
  | { kind: "init_fail"; oom: boolean }
  | { kind: "ctx_ok"; memoryBytes: number }
  | { kind: "ready"; resultBytes: number }
  | { kind: "overflow_ok"; memoryBytes: number }
  | { kind: "overflow_cleanup_fail" }
  | { kind: "discard_ok"; memoryBytes: number }
  | { kind: "commit_ok"; memoryBytes: number; returnedBuf?: ArrayBuffer }
  | { kind: "cleanup_fail"; resultBytes: number; returnedBuf?: ArrayBuffer }
  | { kind: "arena_oom" }
  | { kind: "run_trap"; cleanupOk: boolean };

interface PendingWaiter {
  readonly seq: number;
  readonly expectData:
    | null
    | {
      readonly kind: "fixed";
      targetBuf: ArrayBuffer;
      readonly byteOffset: number;
      readonly expectedBytes: number;
    }
    | {
      readonly kind: "variable";
      readonly expectedBytes: number;
    };
  readonly resolve: (outcome: TransportOutcome) => void;
}

type TerminalState = null | { kind: "fenced" } | {
  kind: "fault";
  reason: string;
};

class KernelSubprocess {
  readonly workerIndex: number;
  readonly child: Deno.ChildProcess;
  readonly stdinWriter: WritableStreamDefaultWriter<Uint8Array>;
  readonly stdoutReader: ReadableStreamBYOBReader;
  fenced = false;
  terminal: TerminalState = null;
  pendingWaiter: PendingWaiter | null = null;
  idleGateResolve: (() => void) | null = null;
  opDeadlineMs: number | null = null;
  parserDone!: Promise<void>;
  retirePromise: Promise<void> | null = null;
  installedSnapshotId: number | null = null;
  storeHasPriorHistory = false;
  memoryBytes = 0;
  memoryCharge = 0;
  chargesReleased = false;
  nextSeq = 1;
  #hooks?: KernelTestHooks;

  constructor(
    workerIndex: number,
    scriptUrl: URL,
    memoryCharge: number,
    hooks?: KernelTestHooks,
  ) {
    this.workerIndex = workerIndex;
    this.memoryCharge = memoryCharge;
    this.#hooks = hooks;
    const cmd = new Deno.Command(Deno.execPath(), {
      args: ["run", "--no-prompt", "--no-remote", scriptUrl.href],
      stdin: "piped",
      stdout: "piped",
      stderr: "null",
    });
    this.child = cmd.spawn();
    this.stdinWriter = this.child.stdin.getWriter();
    this.stdoutReader = this.child.stdout.getReader({ mode: "byob" });
    this.parserDone = this.#runParserLoop();
  }

  isDeadlineExpired(): boolean {
    return this.opDeadlineMs !== null && performance.now() >= this.opDeadlineMs;
  }

  /** Closed synchronous registration gate — first cause wins! */
  closeTransport(
    outcome: { kind: "fenced" } | { kind: "fault"; reason: string },
  ): void {
    if (this.terminal !== null) return;
    this.terminal = outcome;
    const waiter = this.pendingWaiter;
    this.pendingWaiter = null;
    if (waiter !== null) waiter.resolve(outcome);
    const wake = this.idleGateResolve;
    this.idleGateResolve = null;
    if (wake !== null) wake();
  }

  registerWaiter(
    seq: number,
    expectData: PendingWaiter["expectData"],
  ): Promise<TransportOutcome> {
    if (this.terminal !== null) {
      return Promise.resolve(this.terminal);
    }
    return new Promise<TransportOutcome>((resolve) => {
      if (this.terminal !== null) {
        resolve(this.terminal);
        return;
      }
      this.pendingWaiter = { seq, expectData, resolve };
      const wake = this.idleGateResolve;
      this.idleGateResolve = null;
      if (wake !== null) wake();
    });
  }

  async sendCommand(
    cmd: number,
    seq: number,
    payload: Uint8Array | null,
    inlineWord: number,
    expectData: PendingWaiter["expectData"] = null,
  ): Promise<TransportOutcome> {
    if (this.terminal !== null) return this.terminal;
    const waiterPromise = this.registerWaiter(seq, expectData);
    if (this.terminal !== null) return waiterPromise;
    const payloadLen = payload === null ? 0 : payload.byteLength;
    const frame = new Uint8Array(16 + payloadLen);
    const dv = new DataView(frame.buffer);
    dv.setUint32(0, cmd >>> 0, true);
    dv.setUint32(4, seq >>> 0, true);
    dv.setUint32(8, payloadLen >>> 0, true);
    dv.setUint32(12, inlineWord >>> 0, true);
    if (payload !== null && payloadLen > 0) {
      frame.set(payload, 16);
    }
    try {
      await this.stdinWriter.write(frame);
    } catch {
      this.closeTransport(
        this.isDeadlineExpired()
          ? { kind: "fenced" }
          : { kind: "fault", reason: "stdin_write_failed" },
      );
    }
    return waiterPromise;
  }

  async #readExactByob(
    buf: ArrayBuffer,
    byteOffset: number,
    byteLength: number,
  ): Promise<{ ok: true; buf: ArrayBuffer } | { ok: false; reason: string }> {
    let curBuf = buf;
    let filled = 0;
    while (filled < byteLength) {
      if (this.fenced) return { ok: false, reason: "fenced" };
      const remaining = byteLength - filled;
      const view = new Uint8Array(curBuf, byteOffset + filled, remaining);
      let res: ReadableStreamReadResult<Uint8Array<ArrayBuffer>>;
      try {
        res = await this.stdoutReader.read(view) as ReadableStreamReadResult<
          Uint8Array<ArrayBuffer>
        >;
      } catch {
        return { ok: false, reason: "byob_read_error" };
      }
      if (res.value !== undefined) {
        curBuf = res.value.buffer;
        filled += res.value.byteLength;
      }
      if (this.fenced) return { ok: false, reason: "fenced" };
      if (res.done && filled < byteLength) {
        return { ok: false, reason: "eof" };
      }
    }
    return { ok: true, buf: curBuf };
  }

  /** Strict parser-vs-coordinator split: NEVER calls or awaits retireSubprocess! */
  async #runParserLoop(): Promise<void> {
    let headerBuf: ArrayBuffer = new ArrayBuffer(16);
    let partialTarget: ArrayBuffer | null = null;
    try {
      while (!this.fenced && this.terminal === null) {
        if (this.pendingWaiter === null) {
          await new Promise<void>((resolve) => {
            if (
              this.fenced || this.terminal !== null ||
              this.pendingWaiter !== null
            ) {
              resolve();
              return;
            }
            this.idleGateResolve = resolve;
          });
          if (this.fenced || this.terminal !== null) break;
          continue;
        }

        const hdrRes = await this.#readExactByob(headerBuf, 0, 16);
        if (!hdrRes.ok) {
          this.closeTransport(
            this.fenced || this.isDeadlineExpired()
              ? { kind: "fenced" }
              : { kind: "fault", reason: hdrRes.reason },
          );
          break;
        }
        headerBuf = hdrRes.buf;

        if (this.#hooks?.delayFrameDeliveryMs) {
          await new Promise((r) =>
            setTimeout(r, this.#hooks!.delayFrameDeliveryMs)
          );
        }

        // Universal monotonic deadline check on EVERY frame observation!
        if (this.fenced || this.isDeadlineExpired()) {
          this.closeTransport({ kind: "fenced" });
          break;
        }

        const dv = new DataView(headerBuf);
        const tag = dv.getUint32(0, true);
        const seq = dv.getUint32(4, true);
        const payloadBytes = dv.getUint32(8, true);
        const inlineWord = dv.getUint32(12, true);

        const waiter = this.pendingWaiter;
        if (waiter === null || seq !== waiter.seq) {
          this.closeTransport(
            this.isDeadlineExpired()
              ? { kind: "fenced" }
              : { kind: "fault", reason: "seq_mismatch" },
          );
          break;
        }

        // Handle DATA_FRAME followed by trailing COMMIT_OK / CLEANUP_FAIL.
        if (tag === TAG_DATA_FRAME) {
          const spec = waiter.expectData;
          if (
            spec === null ||
            payloadBytes === 0 ||
            payloadBytes !== spec.expectedBytes
          ) {
            this.closeTransport(
              this.isDeadlineExpired()
                ? { kind: "fenced" }
                : { kind: "fault", reason: "data_length_mismatch" },
            );
            break;
          }

          if (this.#hooks?.injectByobReadError) {
            this.closeTransport(
              this.isDeadlineExpired()
                ? { kind: "fenced" }
                : { kind: "fault", reason: "injected_byob_error" },
            );
            break;
          }

          let dataBuf: ArrayBuffer;
          let byteOffset: number;
          if (spec.kind === "fixed") {
            dataBuf = spec.targetBuf;
            byteOffset = spec.byteOffset;
          } else {
            dataBuf = new ArrayBuffer(payloadBytes);
            byteOffset = 0;
          }
          partialTarget = dataBuf;

          const bodyRes = await this.#readExactByob(
            dataBuf,
            byteOffset,
            payloadBytes,
          );
          if (!bodyRes.ok) {
            partialTarget = null;
            this.closeTransport(
              this.fenced || this.isDeadlineExpired()
                ? { kind: "fenced" }
                : { kind: "fault", reason: bodyRes.reason },
            );
            break;
          }
          dataBuf = bodyRes.buf;
          partialTarget = dataBuf;

          // Now read mandatory trailing 16-byte COMMIT_OK or CLEANUP_FAIL header.
          const trailRes = await this.#readExactByob(headerBuf, 0, 16);
          if (!trailRes.ok) {
            partialTarget = null;
            this.closeTransport(
              this.fenced || this.isDeadlineExpired()
                ? { kind: "fenced" }
                : { kind: "fault", reason: trailRes.reason },
            );
            break;
          }
          headerBuf = trailRes.buf;
          if (this.fenced || this.isDeadlineExpired()) {
            partialTarget = null;
            this.closeTransport({ kind: "fenced" });
            break;
          }

          const tdv = new DataView(headerBuf);
          const tTag = tdv.getUint32(0, true);
          const tSeq = tdv.getUint32(4, true);
          const tPayload = tdv.getUint32(8, true);
          const tInline = tdv.getUint32(12, true);
          if (tSeq !== waiter.seq || tPayload !== 0) {
            partialTarget = null;
            this.closeTransport(
              this.isDeadlineExpired()
                ? { kind: "fenced" }
                : { kind: "fault", reason: "malformed_trailing_header" },
            );
            break;
          }

          if (tTag === TAG_COMMIT_OK) {
            const finishedBuf = dataBuf;
            partialTarget = null;
            this.pendingWaiter = null;
            waiter.resolve({
              kind: "commit_ok",
              memoryBytes: tInline,
              returnedBuf: finishedBuf,
            });
            continue;
          }
          if (tTag === TAG_CLEANUP_FAIL) {
            const returnedBuf = spec.kind === "fixed" ? dataBuf : undefined;
            partialTarget = null;
            this.pendingWaiter = null;
            waiter.resolve({
              kind: "cleanup_fail",
              resultBytes: payloadBytes,
              returnedBuf,
            });
            continue;
          }
          partialTarget = null;
          this.closeTransport(
            this.isDeadlineExpired()
              ? { kind: "fenced" }
              : { kind: "fault", reason: "unexpected_trailing_tag" },
          );
          break;
        }

        // All remaining tags MUST be header-only (`payload_bytes === 0`).
        if (payloadBytes !== 0) {
          this.closeTransport(
            this.isDeadlineExpired() ? { kind: "fenced" } : {
              kind: "fault",
              reason: "unexpected_payload_on_control_frame",
            },
          );
          break;
        }

        let outcome: TransportOutcome | null = null;
        switch (tag) {
          case TAG_INIT_OK:
            outcome = { kind: "init_ok", memoryBytes: inlineWord };
            break;
          case TAG_INIT_FAIL:
            outcome = { kind: "init_fail", oom: inlineWord !== 0 };
            break;
          case TAG_CTX_OK:
            outcome = { kind: "ctx_ok", memoryBytes: inlineWord };
            break;
          case TAG_READY:
            outcome = { kind: "ready", resultBytes: inlineWord };
            break;
          case TAG_OVERFLOW_OK:
            outcome = { kind: "overflow_ok", memoryBytes: inlineWord };
            break;
          case TAG_OVERFLOW_CLEANUP_FAIL:
            outcome = { kind: "overflow_cleanup_fail" };
            break;
          case TAG_DISCARD_OK:
            outcome = { kind: "discard_ok", memoryBytes: inlineWord };
            break;
          case TAG_COMMIT_OK: {
            // 0-byte variable commit (header-only path, no DATA_FRAME).
            const returnedBuf = waiter.expectData?.kind === "fixed"
              ? waiter.expectData.targetBuf
              : new ArrayBuffer(0);
            outcome = {
              kind: "commit_ok",
              memoryBytes: inlineWord,
              returnedBuf,
            };
            break;
          }
          case TAG_CLEANUP_FAIL: {
            const returnedBuf = waiter.expectData?.kind === "fixed"
              ? waiter.expectData.targetBuf
              : undefined;
            outcome = {
              kind: "cleanup_fail",
              resultBytes: inlineWord,
              returnedBuf,
            };
            break;
          }
          case TAG_ARENA_OOM:
            outcome = { kind: "arena_oom" };
            break;
          case TAG_RUN_TRAP:
            outcome = { kind: "run_trap", cleanupOk: inlineWord !== 0 };
            break;
          default:
            this.closeTransport(
              this.isDeadlineExpired()
                ? { kind: "fenced" }
                : { kind: "fault", reason: `unknown_tag_${tag}` },
            );
            break;
        }
        if (outcome === null) break;
        this.pendingWaiter = null;
        waiter.resolve(outcome);
      }
    } catch {
      this.closeTransport(
        this.fenced || this.isDeadlineExpired()
          ? { kind: "fenced" }
          : { kind: "fault", reason: "parser_exception" },
      );
    } finally {
      partialTarget = null;
      this.closeTransport(
        this.fenced || this.isDeadlineExpired()
          ? { kind: "fenced" }
          : { kind: "fault", reason: "parser_exit" },
      );
    }
  }

  /**
   * Kill-first 5-step idempotent subprocess retirement (§5.1):
   * 1. Synchronously fence & closeTransport (first cause wins; wakes idle gate).
   * 2. SIGKILL (ignoring AlreadyTerminated / NotFound).
   * 3. writer.abort().
   * 4. Let native BYOB read finish natively & await parserDone (clears partialTarget = null).
   * 5. ONLY AFTER parserDone: reader.cancel(), releaseLock(), await child.status.
   */
  retire(onChargesRelease: (worker: KernelSubprocess) => void): Promise<void> {
    if (this.retirePromise !== null) return this.retirePromise;
    this.fenced = true;
    this.closeTransport({ kind: "fenced" });
    this.retirePromise = (async () => {
      try {
        this.child.kill("SIGKILL");
      } catch {
        /* ignore NotFound / AlreadyTerminated TypeError */
      }
      await this.stdinWriter.abort().catch(() => {});
      await this.parserDone;
      await this.stdoutReader.cancel().catch(() => {});
      try {
        this.stdoutReader.releaseLock();
      } catch { /* ignore */ }
      try {
        this.stdinWriter.releaseLock();
      } catch { /* ignore */ }
      let status: Deno.CommandStatus | null = null;
      try {
        status = await this.child.status;
      } catch { /* ignore */ }
      if (!this.chargesReleased) {
        this.chargesReleased = true;
        onChargesRelease(this);
      }
      this.#hooks?.onSubprocessRetired?.({
        workerIndex: this.workerIndex,
        exitCode: status?.code ?? null,
        signal: status?.signal ?? null,
        terminalKind: this.terminal?.kind ?? "none",
      });
    })();
    return this.retirePromise;
  }
}

/** Synchronous inline Wasm instance used ONLY when `policy.deadlineMs === undefined && workers === 0` (or unbounded serial fallback). */
class InlineKernelGuest {
  readonly memory: WebAssembly.Memory;
  readonly allocate: (bytes: number) => number;
  readonly reset: (arg: number) => void;
  readonly finishInvocation: (() => void) | null;
  readonly entryFn: (ptr: number) => number;
  readonly ctxFn: ((arg: number) => void) | null;
  readonly clearFn: ((arg: number) => void) | null;
  readonly ctxWireTag: number;
  readonly variableOutput: boolean;
  installedSnapshotId: number | null = null;
  storeHasPriorHistory = false;

  constructor(meta: ValidatedModuleMeta, manifest: KernelManifest) {
    const stubImports: Record<string, Record<string, WebAssembly.ImportValue>> =
      {};
    for (const imp of WebAssembly.Module.imports(meta.module)) {
      if (imp.kind === "function") {
        (stubImports[imp.module] ??= {})[imp.name] = () => {
          throw new Error(`unexpected host import ${imp.module}/${imp.name}`);
        };
      }
    }
    const instance = new WebAssembly.Instance(meta.module, stubImports);
    const exports = instance.exports;
    const memory = exports["blot:memory"];
    const allocate = exports["blot:allocate"];
    const reset = exports["blot:reset"];
    const entryFn = exports[manifest.name];
    if (
      !(memory instanceof WebAssembly.Memory) ||
      typeof allocate !== "function" ||
      typeof reset !== "function" ||
      typeof entryFn !== "function"
    ) {
      throw new KernelError("transport_fault", "Missing kernel arena exports");
    }
    this.memory = memory;
    this.allocate = allocate as (bytes: number) => number;
    this.reset = reset as (arg: number) => void;
    const finishRaw = exports["blot:finish_invocation"];
    this.finishInvocation = typeof finishRaw === "function"
      ? (finishRaw as () => void)
      : null;
    this.entryFn = entryFn as (ptr: number) => number;
    this.ctxFn = manifest.ctxExport !== undefined
      ? (exports[manifest.ctxExport] as (arg: number) => void)
      : null;
    this.clearFn = manifest.clearExport !== undefined
      ? (exports[manifest.clearExport] as (arg: number) => void)
      : null;
    this.ctxWireTag = manifest.ctxSchema?.wireTagCode ?? 5;
    this.variableOutput = manifest.variableOutput;
  }

  memoryBytes(): number {
    return this.memory.buffer.byteLength;
  }

  readArenaOom(): boolean {
    if (this.memory.buffer.byteLength < ARENA_OOM_OFFSET + 4) return false;
    return new DataView(this.memory.buffer).getUint32(
      ARENA_OOM_OFFSET,
      true,
    ) !== 0;
  }

  writePacket(bytes: Uint8Array): number {
    this.reset(0);
    const words = bytes.byteLength >>> 2;
    const ptr = this.allocate((words + 1) * 4) >>> 0;
    const buf = this.memory.buffer;
    if (
      ptr < 4 || (ptr & 3) !== 0 || ptr + 4 + bytes.byteLength > buf.byteLength
    ) {
      throw new KernelError(
        "transport_fault",
        "Packet allocation out of bounds",
      );
    }
    new DataView(buf).setUint32(ptr, words, true);
    if (bytes.byteLength > 0) {
      new Uint8Array(buf, ptr + 4, bytes.byteLength).set(bytes);
    }
    return ptr;
  }
}

interface ActiveOp {
  readonly kind: "context" | "batch";
  readonly snapshot: PreparedContextSnapshot | null;
  readonly epoch: number;
  readonly cancelForClose: () => void;
  readonly done: Promise<void>;
}

interface VariableCompletedChunk {
  readonly end: number;
  readonly bytes: Uint32Array | null; // null for OverBudgetHint
  readonly byteLength: number;
  readonly overBudgetHint: boolean;
}

function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.byteLength !== b.byteLength) return false;
  for (let i = 0; i < a.byteLength; i++) {
    if (a[i] !== b[i]) return false;
  }
  return true;
}

function isMemoryGrowError(err: unknown): boolean {
  if (!(err instanceof Error)) return false;
  const msg = err.message.toLowerCase();
  return msg.includes("out of memory") || msg.includes("grow");
}

function encodeInitPayload(
  wasmBytes: Uint8Array,
  manifest: KernelManifest,
): Uint8Array {
  const metaJson = new TextEncoder().encode(JSON.stringify({
    entryName: manifest.name,
    variableOutput: manifest.variableOutput,
    ctxExport: manifest.ctxExport,
    clearExport: manifest.clearExport,
    ctxWireTag: manifest.ctxSchema?.wireTagCode ?? 5,
  }));
  const payload = new Uint8Array(
    8 + wasmBytes.byteLength + metaJson.byteLength,
  );
  const dv = new DataView(payload.buffer);
  dv.setUint32(0, wasmBytes.byteLength, true);
  dv.setUint32(4, metaJson.byteLength, true);
  payload.set(wasmBytes, 8);
  payload.set(metaJson, 8 + wasmBytes.byteLength);
  return payload;
}

export class KernelPool {
  readonly #meta: ValidatedModuleMeta;
  readonly manifest: KernelManifest;
  readonly transportBudget: number;
  readonly maxChunkItems: number;
  readonly #workersCount: number;
  readonly #deadlineMs: number | null;
  readonly #memoryLimit: number | null;
  readonly #maxTotalOutputBytes: number;
  readonly #maxPhysicalOutputBytes: number;
  readonly #maxInputSnapshotBytes: number | null;
  readonly #retireMemoryThreshold: number;
  readonly #maxRetiredInFlight: number;
  readonly #hooks?: KernelTestHooks;

  #state: "open" | "closing" | "closed" = "open";
  #poolEpoch = 0;
  #activeOp: ActiveOp | null = null;
  #closePromise: Promise<void> | null = null;
  #currentCtx: PreparedContextSnapshot | null = null;
  #nextSnapshotId = 1;

  // Persistent warm workers (subprocesses for workers >= 1 or deadline-bound workers == 0)
  readonly #warmSubprocesses: (KernelSubprocess | null)[] = [];
  #directSubprocess: KernelSubprocess | null = null;
  #inlineGuest: InlineKernelGuest | null = null;
  #forceFallback = false;

  // Live & peak accounting
  #peakChargedBytes = 0;
  #inputSnapshotBytes = 0;
  #contextSnapshotBytes = 0;
  #fixedOutputBytes = 0;
  #bufferedChunkBytes = 0;
  #inFlightGrantBytes = 0;
  #concatScratchBytes = 0;
  #workerMemoryBytes = 0;
  #freshRetries = 0;
  #fallbacks = 0;
  #activeSubprocesses = 0;
  #retiredSubprocesses = 0;
  #retiredInFlight = 0;
  readonly #liveSubprocesses = new Set<KernelSubprocess>();
  readonly #retiringPromises = new Set<Promise<void>>();

  private constructor(
    meta: ValidatedModuleMeta,
    manifest: KernelManifest,
    config: KernelPoolConfig,
  ) {
    this.#meta = meta;
    this.manifest = manifest;
    this.transportBudget = meta.abi.transportBudget ?? DEFAULT_TRANSPORT_BUDGET;
    this.#workersCount = config.workers ?? 1;
    this.#deadlineMs = config.deadlineMs ?? null;
    this.#memoryLimit = config.memory ?? null;
    this.#maxTotalOutputBytes = config.maxTotalOutputBytes ?? 16 * 1024 * 1024;
    this.#maxPhysicalOutputBytes = config.maxPhysicalOutputBytes ??
      this.#maxTotalOutputBytes * 2;
    this.#maxInputSnapshotBytes = config.maxInputSnapshotBytes ?? null;
    this.#retireMemoryThreshold = config.retireMemoryThreshold ??
      64 * 1024 * 1024;
    this.#maxRetiredInFlight = config.maxRetiredInFlight ??
      Math.max(4, this.#workersCount * 2);
    this.#hooks = config._testHooks;
    this.#forceFallback = Boolean(config._testHooks?.forceFallback);

    const defaultChunkItems = config.defaultChunkItems ?? 64;
    const inItemBytes = manifest.inSchema.stride * 4;
    const maxInItems = Math.floor((this.transportBudget - 4) / inItemBytes);
    const maxOutItems = manifest.variableOutput
      ? Number.POSITIVE_INFINITY
      : Math.floor(
        (this.transportBudget - 4) / (manifest.outSchema.stride * 4),
      );
    this.maxChunkItems = Math.max(
      1,
      Math.min(defaultChunkItems, maxInItems, maxOutItems),
    );
    for (let i = 0; i < this.#workersCount; i++) {
      this.#warmSubprocesses.push(null);
    }
  }

  static async open(
    source: Uint8Array | CompiledModuleReceipt,
    name: string,
    config: KernelPoolConfig = {},
  ): Promise<KernelPool> {
    const meta = resolveValidatedModule(source);
    const manifest = meta.abi.kernels?.find((k) => k.name === name);
    if (!manifest) {
      throw new KernelError("unknown_kernel", `Unknown kernel entry: ${name}`);
    }
    const workers = config.workers ?? 1;
    if (!Number.isSafeInteger(workers) || workers < 0) {
      throw new KernelError(
        "invalid_config",
        "workers must be a non-negative integer",
      );
    }
    if (config.deadlineMs !== undefined) {
      const d = config.deadlineMs;
      if (!Number.isFinite(d) || d < 1 || d > MAX_DEADLINE_MS) {
        throw new KernelError(
          "invalid_config",
          `deadlineMs must be finite in 1..=${MAX_DEADLINE_MS}, got ${d}`,
        );
      }
    }
    if (config.memory !== undefined) {
      if (!Number.isSafeInteger(config.memory) || config.memory <= 0) {
        throw new KernelError(
          "invalid_config",
          "memory must be a positive integer",
        );
      }
      if (meta.memoryShape.hasMemory) {
        if (meta.memoryShape.maximumPages === undefined) {
          throw new KernelError(
            "memory_limit_unbounded",
            "JS/Deno KernelPool rejects unbounded Wasm linear memory when policy.memory is set",
          );
        }
        const declaredMaxBytes = meta.memoryShape.maximumPages * 65_536;
        if (config.memory < declaredMaxBytes) {
          throw new KernelError(
            "memory_limit_exceeded",
            `policy.memory (${config.memory}) < declared Wasm maximum (${declaredMaxBytes})`,
          );
        }
      }
    }
    const maxTotal = config.maxTotalOutputBytes ?? 16 * 1024 * 1024;
    const maxPhysical = config.maxPhysicalOutputBytes ?? maxTotal * 2;
    if (
      !Number.isSafeInteger(maxTotal) || maxTotal < 0 ||
      !Number.isSafeInteger(maxPhysical) || maxPhysical < 0
    ) {
      throw new KernelError("invalid_config", "Invalid output byte limits");
    }
    if (
      config.defaultChunkItems !== undefined &&
      (!Number.isSafeInteger(config.defaultChunkItems) ||
        config.defaultChunkItems < 1)
    ) {
      throw new KernelError("invalid_config", "defaultChunkItems must be >= 1");
    }
    return await Promise.resolve(new KernelPool(meta, manifest, config));
  }

  get stats(): KernelPoolStats {
    const current = this.#currentOutputAndCopyBytes();
    return Object.freeze({
      peakChargedBytes: this.#peakChargedBytes,
      currentChargedBytes: current,
      inputSnapshotBytes: this.#inputSnapshotBytes,
      contextSnapshotBytes: this.#contextSnapshotBytes,
      fixedOutputBytes: this.#fixedOutputBytes,
      bufferedChunkBytes: this.#bufferedChunkBytes,
      inFlightGrantBytes: this.#inFlightGrantBytes,
      workerMemoryBytes: this.#workerMemoryBytes,
      freshRetries: this.#freshRetries,
      fallbacks: this.#fallbacks,
      activeSubprocesses: this.#activeSubprocesses,
      retiredSubprocesses: this.#retiredSubprocesses,
    });
  }

  /** Force subsequent `workers >= 1` runs to take the serial fallback path (testing / recovery). */
  forceSerialFallback(enabled = true): void {
    this.#forceFallback = enabled;
  }

  #currentOutputAndCopyBytes(): number {
    return this.#fixedOutputBytes + this.#bufferedChunkBytes +
      this.#inFlightGrantBytes + this.#concatScratchBytes;
  }

  #recordPeak(): void {
    const cur = this.#currentOutputAndCopyBytes();
    if (cur > this.#peakChargedBytes) this.#peakChargedBytes = cur;
  }

  #resetBatchPeak(): void {
    this.#peakChargedBytes = this.#currentOutputAndCopyBytes();
  }

  #perWorkerMemoryCharge(): number {
    if (this.#memoryLimit !== null) return this.#memoryLimit;
    if (this.#meta.memoryShape.maximumPages !== undefined) {
      return this.#meta.memoryShape.maximumPages * 65_536;
    }
    return this.#meta.memoryShape.initialPages * 65_536;
  }

  async #spawnSubprocess(
    workerIndex: number,
    opDeadlineMs: number | null,
  ): Promise<{ worker: KernelSubprocess } | { outcome: TransportOutcome }> {
    if (
      this.#activeSubprocesses + this.#retiredInFlight >=
        Math.max(1, this.#workersCount) + this.#maxRetiredInFlight + 2
    ) {
      throw new KernelError(
        "pool_exhausted",
        "Subprocess retirement cap saturated",
      );
    }
    const memCharge = this.#perWorkerMemoryCharge();
    const scriptUrl = this.#hooks?.workerScriptUrl ?? WORKER_SCRIPT_URL;
    const worker = new KernelSubprocess(
      workerIndex,
      scriptUrl,
      memCharge,
      this.#hooks,
    );
    worker.opDeadlineMs = opDeadlineMs;
    this.#activeSubprocesses++;
    this.#workerMemoryBytes += memCharge;
    this.#liveSubprocesses.add(worker);

    const seq = worker.nextSeq++;
    const initPayload = encodeInitPayload(this.#meta.snapshot, this.manifest);
    const res = await worker.sendCommand(CMD_INIT, seq, initPayload, 0);
    if (res.kind !== "init_ok") {
      await this.#retireSubprocess(worker);
      return { outcome: res };
    }
    worker.memoryBytes = res.memoryBytes;
    return { worker };
  }

  #retireSubprocess(worker: KernelSubprocess): Promise<void> {
    if (worker.retirePromise !== null) return worker.retirePromise;
    this.#liveSubprocesses.delete(worker);
    for (let i = 0; i < this.#warmSubprocesses.length; i++) {
      if (this.#warmSubprocesses[i] === worker) {
        this.#warmSubprocesses[i] = null;
      }
    }
    if (this.#directSubprocess === worker) {
      this.#directSubprocess = null;
    }
    this.#retiredInFlight++;
    const p = worker.retire((w) => {
      this.#activeSubprocesses = Math.max(0, this.#activeSubprocesses - 1);
      this.#workerMemoryBytes = Math.max(
        0,
        this.#workerMemoryBytes - w.memoryCharge,
      );
      this.#retiredInFlight = Math.max(0, this.#retiredInFlight - 1);
      this.#retiredSubprocesses++;
    }).finally(() => {
      this.#retiringPromises.delete(p);
    });
    this.#retiringPromises.add(p);
    return p;
  }

  /** Arm a monotonic deadline timer with premature-wakeup re-arming (§5.1). */
  #armDeadlineTimer(
    opDeadlineMs: number,
    onExpire: () => void,
  ): { clear: () => void } {
    let cleared = false;
    let handle: ReturnType<typeof setTimeout> | undefined;
    const tick = () => {
      if (cleared) return;
      const remaining = opDeadlineMs - performance.now();
      if (remaining > 0) {
        handle = setTimeout(tick, Math.ceil(remaining));
        return;
      }
      cleared = true;
      onExpire();
    };
    const initial = Math.max(1, Math.ceil(opDeadlineMs - performance.now()));
    handle = setTimeout(tick, initial);
    this.#hooks?.onTimerArmed?.({ deadlineMs: opDeadlineMs, fire: tick });
    return {
      clear: () => {
        cleared = true;
        if (handle !== undefined) clearTimeout(handle);
      },
    };
  }

  #ensureInlineGuest(): InlineKernelGuest {
    if (this.#inlineGuest === null) {
      this.#inlineGuest = new InlineKernelGuest(this.#meta, this.manifest);
    }
    return this.#inlineGuest;
  }

  /** Unified snapshot installation for inline direct execution (deadlineMs === null only). */
  #ensureInlineSnapshot(target: PreparedContextSnapshot | null): void {
    if (!this.manifest.hasContext || target === null) return;
    let retriedFresh = false;
    for (;;) {
      const guest = this.#ensureInlineGuest();
      if (guest.installedSnapshotId === target.snapshotId) return;
      if (guest.installedSnapshotId !== null) {
        const eligibleClear = guest.storeHasPriorHistory && !retriedFresh;
        try {
          guest.reset(0);
          guest.clearFn!(0);
          guest.finishInvocation?.();
          guest.reset(0);
          guest.installedSnapshotId = null;
          guest.storeHasPriorHistory = true;
        } catch (err) {
          const oom = guest.readArenaOom() || isMemoryGrowError(err);
          this.#inlineGuest = null;
          if (oom && eligibleClear) {
            retriedFresh = true;
            this.#freshRetries++;
            continue;
          }
          throw new KernelError(
            oom ? "out_of_memory" : "cleanup_trap",
            `Context clear failed: ${String(err)}`,
          );
        }
      }
      const eligible = guest.storeHasPriorHistory && !retriedFresh;
      try {
        let arg: number;
        const wireTag = guest.ctxWireTag;
        if (wireTag === 1 || wireTag === 2 || wireTag === 3) {
          guest.reset(0);
          const dv = new DataView(
            target.bytes.buffer,
            target.bytes.byteOffset,
            4,
          );
          arg = wireTag === 3
            ? dv.getFloat32(0, true)
            : wireTag === 2
            ? (dv.getUint32(0, true) !== 0 ? 1 : 0)
            : dv.getUint32(0, true);
        } else {
          arg = guest.writePacket(target.bytes);
        }
        guest.ctxFn!(arg);
        guest.finishInvocation?.();
        guest.reset(0);
        guest.installedSnapshotId = target.snapshotId;
        return;
      } catch (err) {
        const oom = guest.readArenaOom() || isMemoryGrowError(err);
        this.#inlineGuest = null;
        if (oom && eligible) {
          retriedFresh = true;
          this.#freshRetries++;
          continue;
        }
        throw new KernelError(
          oom ? "out_of_memory" : "run_trap",
          `Context prepare failed: ${String(err)}`,
        );
      }
    }
  }

  /** Unified snapshot installation on a subprocess worker slot. */
  async #ensureSubprocessSnapshot(
    workerRef: { worker: KernelSubprocess | null },
    workerIndex: number,
    target: PreparedContextSnapshot | null,
    opDeadlineMs: number | null,
    activeOpEpoch: number,
  ): Promise<
    | { ok: true; worker: KernelSubprocess }
    | { ok: false; error: KernelError }
  > {
    let retriedFresh = false;
    for (;;) {
      if (this.#state !== "open" || this.#poolEpoch !== activeOpEpoch) {
        return {
          ok: false,
          error: new KernelError("pool_closed", "KernelPool is closed"),
        };
      }
      if (opDeadlineMs !== null && performance.now() >= opDeadlineMs) {
        return {
          ok: false,
          error: new KernelError("timeout", "Operation timed out"),
        };
      }
      if (workerRef.worker === null || workerRef.worker.terminal !== null) {
        if (workerRef.worker !== null) {
          await this.#retireSubprocess(workerRef.worker);
          workerRef.worker = null;
        }
        const spawned = await this.#spawnSubprocess(workerIndex, opDeadlineMs);
        if ("outcome" in spawned) {
          if (this.#state !== "open" || this.#poolEpoch !== activeOpEpoch) {
            return {
              ok: false,
              error: new KernelError("pool_closed", "KernelPool is closed"),
            };
          }
          if (
            spawned.outcome.kind === "fenced" ||
            (opDeadlineMs !== null && performance.now() >= opDeadlineMs)
          ) {
            return {
              ok: false,
              error: new KernelError("timeout", "Worker spawn timed out"),
            };
          }
          if (spawned.outcome.kind === "init_fail" && spawned.outcome.oom) {
            return {
              ok: false,
              error: new KernelError("out_of_memory", "Worker init OOM"),
            };
          }
          return {
            ok: false,
            error: new KernelError(
              "transport_fault",
              "Worker initialization failed",
            ),
          };
        }
        workerRef.worker = spawned.worker;
      }
      const w = workerRef.worker;
      w.opDeadlineMs = opDeadlineMs;

      if (!this.manifest.hasContext || target === null) {
        return { ok: true, worker: w };
      }
      if (w.installedSnapshotId === target.snapshotId) {
        return { ok: true, worker: w };
      }

      // Warm replacement: clear old context FIRST, flipping storeHasPriorHistory = true.
      if (w.installedSnapshotId !== null) {
        const eligibleClear = w.storeHasPriorHistory && !retriedFresh;
        const clearRes = await w.sendCommand(
          CMD_CLEAR_CTX,
          w.nextSeq++,
          null,
          0,
        );
        if (this.#state !== "open" || this.#poolEpoch !== activeOpEpoch) {
          await this.#retireSubprocess(w);
          workerRef.worker = null;
          return {
            ok: false,
            error: new KernelError("pool_closed", "KernelPool is closed"),
          };
        }
        if (
          clearRes.kind === "fenced" ||
          (opDeadlineMs !== null && performance.now() >= opDeadlineMs)
        ) {
          await this.#retireSubprocess(w);
          workerRef.worker = null;
          return {
            ok: false,
            error: new KernelError("timeout", "Context clear timed out"),
          };
        }
        if (clearRes.kind !== "ctx_ok") {
          await this.#retireSubprocess(w);
          workerRef.worker = null;
          if (clearRes.kind === "arena_oom" && eligibleClear) {
            retriedFresh = true;
            this.#freshRetries++;
            continue;
          }
          return {
            ok: false,
            error: new KernelError(
              clearRes.kind === "arena_oom" ? "out_of_memory" : "cleanup_trap",
              "Context clear failed",
            ),
          };
        }
        w.installedSnapshotId = null;
        w.storeHasPriorHistory = true;
        w.memoryBytes = clearRes.memoryBytes;
      }

      const eligible = w.storeHasPriorHistory && !retriedFresh;
      const ctxRes = await w.sendCommand(
        CMD_SET_CTX,
        w.nextSeq++,
        target.bytes,
        0,
      );
      if (this.#state !== "open" || this.#poolEpoch !== activeOpEpoch) {
        await this.#retireSubprocess(w);
        workerRef.worker = null;
        return {
          ok: false,
          error: new KernelError("pool_closed", "KernelPool is closed"),
        };
      }
      if (
        ctxRes.kind === "fenced" ||
        (opDeadlineMs !== null && performance.now() >= opDeadlineMs)
      ) {
        await this.#retireSubprocess(w);
        workerRef.worker = null;
        return {
          ok: false,
          error: new KernelError("timeout", "Context prepare timed out"),
        };
      }
      if (ctxRes.kind === "ctx_ok") {
        w.installedSnapshotId = target.snapshotId;
        w.memoryBytes = ctxRes.memoryBytes;
        return { ok: true, worker: w };
      }
      await this.#retireSubprocess(w);
      workerRef.worker = null;
      if (ctxRes.kind === "arena_oom" && eligible) {
        retriedFresh = true;
        this.#freshRetries++;
        continue;
      }
      if (ctxRes.kind === "arena_oom") {
        return {
          ok: false,
          error: new KernelError("out_of_memory", "Context prepare OOM"),
        };
      }
      if (ctxRes.kind === "fault") {
        return {
          ok: false,
          error: new KernelError(
            "transport_fault",
            `Context transport fault: ${ctxRes.reason}`,
          ),
        };
      }
      return {
        ok: false,
        error: new KernelError("run_trap", "Context prepare trapped"),
      };
    }
  }

  /**
   * Prepare and publish a new context snapshot on a brand-new EMPTY candidate
   * instance before atomically replacing `currentCtx` (§5.1).
   */
  setContext(
    revision: number | bigint,
    bytes: ArrayBufferView,
  ): Promise<void> {
    if (this.#state !== "open") {
      return Promise.reject(
        new KernelError("pool_closed", "KernelPool is closed"),
      );
    }
    if (this.#activeOp !== null) {
      return Promise.reject(
        new KernelError(
          this.#activeOp.kind === "batch"
            ? "batch_in_progress"
            : "context_operation_in_progress",
          "Another operation is already in progress on this KernelPool",
        ),
      );
    }
    if (!this.manifest.hasContext || !this.manifest.ctxSchema) {
      return Promise.reject(
        new KernelError(
          "invalid_config",
          "Kernel does not accept a prepared context",
        ),
      );
    }
    const rev = typeof revision === "bigint" ? revision : BigInt(revision);
    // Synchronously copy caller bytes via primordial copyPrivateBytes BEFORE any await!
    const ownedBytes = copyPrivateBytes(bytes);
    if (ownedBytes.byteLength % 4 !== 0) {
      return Promise.reject(
        new KernelError(
          "invalid_input",
          "Context byte length must be a multiple of 4",
        ),
      );
    }
    if (ownedBytes.byteLength > this.transportBudget - 4) {
      return Promise.reject(
        new KernelError(
          "invalid_input",
          `Context (${ownedBytes.byteLength} B) exceeds transport budget (${
            this.transportBudget - 4
          } B)`,
        ),
      );
    }
    if (
      this.manifest.ctxSchema.kind === "FlatFixed" &&
      ownedBytes.byteLength !== this.manifest.ctxSchema.stride * 4
    ) {
      return Promise.reject(
        new KernelError(
          "invalid_input",
          `Fixed context requires exact ${
            this.manifest.ctxSchema.stride * 4
          } bytes`,
        ),
      );
    }
    if (
      this.#currentCtx !== null && this.#currentCtx.revision === rev &&
      !bytesEqual(this.#currentCtx.bytes, ownedBytes)
    ) {
      return Promise.reject(
        new KernelError(
          "revision_content_mismatch",
          `Context revision ${rev} already exists with different bytes`,
        ),
      );
    }

    const opEpoch = this.#poolEpoch;
    const candidateBytesCharge = ownedBytes.byteLength;
    this.#contextSnapshotBytes += candidateBytesCharge;
    let candidateChargeReleased = false;
    const releaseCandidateCharge = () => {
      if (!candidateChargeReleased) {
        candidateChargeReleased = true;
        this.#contextSnapshotBytes = Math.max(
          0,
          this.#contextSnapshotBytes - candidateBytesCharge,
        );
      }
    };

    const nextSnapshot: PreparedContextSnapshot = Object.freeze({
      snapshotId: this.#nextSnapshotId++,
      revision: rev,
      bytes: ownedBytes,
    });

    const ctxDeadlineMs = this.#deadlineMs !== null
      ? performance.now() + this.#deadlineMs
      : null;

    let candidateWorker: KernelSubprocess | null = null;
    let timedOut = false;
    let timerHandle: { clear: () => void } | null = null;

    const cancelForClose = () => {
      timerHandle?.clear();
      if (candidateWorker !== null) {
        candidateWorker.fenced = true;
        candidateWorker.closeTransport({ kind: "fenced" });
      }
    };

    let resolveBarrier!: () => void;
    const settledBarrier = new Promise<void>((r) => {
      resolveBarrier = r;
    });
    this.#activeOp = {
      kind: "context",
      snapshot: null,
      epoch: opEpoch,
      cancelForClose,
      done: settledBarrier,
    };

    const done = (async () => {
      try {
        if (ctxDeadlineMs !== null) {
          timerHandle = this.#armDeadlineTimer(ctxDeadlineMs, () => {
            timedOut = true;
            if (candidateWorker !== null) {
              candidateWorker.fenced = true;
              candidateWorker.closeTransport({ kind: "fenced" });
            }
          });
        }

        // Always validate/prepare on a brand-new EMPTY candidate instance!
        if (this.#deadlineMs !== null || this.#workersCount > 0) {
          const spawned = await this.#spawnSubprocess(-1, ctxDeadlineMs);
          if ("outcome" in spawned) {
            if (this.#state !== "open" || this.#poolEpoch !== opEpoch) {
              throw new KernelError(
                "pool_closed",
                "KernelPool closed during setContext",
              );
            }
            if (
              timedOut || spawned.outcome.kind === "fenced" ||
              (ctxDeadlineMs !== null && performance.now() >= ctxDeadlineMs)
            ) {
              throw new KernelError("timeout", "setContext timed out");
            }
            if (spawned.outcome.kind === "init_fail" && spawned.outcome.oom) {
              throw new KernelError("out_of_memory", "Candidate init OOM");
            }
            throw new KernelError(
              "transport_fault",
              "Candidate subprocess init failed",
            );
          }
          candidateWorker = spawned.worker;
          const res = await candidateWorker.sendCommand(
            CMD_SET_CTX,
            candidateWorker.nextSeq++,
            ownedBytes,
            0,
          );
          if (this.#hooks?.onBeforeContextPublish) {
            await this.#hooks.onBeforeContextPublish();
          }
          if (this.#state !== "open" || this.#poolEpoch !== opEpoch) {
            await this.#retireSubprocess(candidateWorker);
            candidateWorker = null;
            throw new KernelError(
              "pool_closed",
              "KernelPool closed during setContext",
            );
          }
          if (
            timedOut || res.kind === "fenced" ||
            (ctxDeadlineMs !== null && performance.now() >= ctxDeadlineMs)
          ) {
            await this.#retireSubprocess(candidateWorker);
            candidateWorker = null;
            throw new KernelError("timeout", "setContext timed out");
          }
          if (res.kind !== "ctx_ok") {
            await this.#retireSubprocess(candidateWorker);
            candidateWorker = null;
            if (res.kind === "arena_oom") {
              throw new KernelError("out_of_memory", "Context prepare OOM");
            }
            if (res.kind === "fault") {
              throw new KernelError(
                "transport_fault",
                `setContext fault: ${res.reason}`,
              );
            }
            throw new KernelError("run_trap", "Context prepare trapped");
          }
          candidateWorker.installedSnapshotId = nextSnapshot.snapshotId;
          candidateWorker.memoryBytes = res.memoryBytes;
          candidateWorker.opDeadlineMs = null;
          if (this.#workersCount === 0 && this.#directSubprocess === null) {
            this.#directSubprocess = candidateWorker;
            candidateWorker = null;
          } else if (
            this.#workersCount > 0 && this.#warmSubprocesses[0] === null
          ) {
            this.#warmSubprocesses[0] = candidateWorker;
            candidateWorker = null;
          } else {
            await this.#retireSubprocess(candidateWorker);
            candidateWorker = null;
          }
        } else {
          const candidate = new InlineKernelGuest(this.#meta, this.manifest);
          try {
            let arg: number;
            const wireTag = candidate.ctxWireTag;
            if (wireTag === 1 || wireTag === 2 || wireTag === 3) {
              candidate.reset(0);
              const dv = new DataView(
                ownedBytes.buffer,
                ownedBytes.byteOffset,
                4,
              );
              arg = wireTag === 3
                ? dv.getFloat32(0, true)
                : wireTag === 2
                ? (dv.getUint32(0, true) !== 0 ? 1 : 0)
                : dv.getUint32(0, true);
            } else {
              arg = candidate.writePacket(ownedBytes);
            }
            candidate.ctxFn!(arg);
            candidate.finishInvocation?.();
            candidate.reset(0);
            candidate.installedSnapshotId = nextSnapshot.snapshotId;
          } catch (err) {
            const oom = candidate.readArenaOom() || isMemoryGrowError(err);
            throw new KernelError(
              oom ? "out_of_memory" : "run_trap",
              `Context prepare failed: ${String(err)}`,
            );
          }
          if (this.#hooks?.onBeforeContextPublish) {
            await this.#hooks.onBeforeContextPublish();
          }
          if (this.#state !== "open" || this.#poolEpoch !== opEpoch) {
            throw new KernelError(
              "pool_closed",
              "KernelPool closed during setContext",
            );
          }
          if (this.#inlineGuest === null) {
            this.#inlineGuest = candidate;
          }
        }

        const prev = this.#currentCtx;
        this.#currentCtx = nextSnapshot;
        if (prev !== null) {
          this.#contextSnapshotBytes = Math.max(
            0,
            this.#contextSnapshotBytes - prev.bytes.byteLength,
          );
        }
        candidateChargeReleased = true;
      } catch (err) {
        if (candidateWorker !== null) {
          await this.#retireSubprocess(candidateWorker);
          candidateWorker = null;
        }
        releaseCandidateCharge();
        throw err;
      } finally {
        timerHandle?.clear();
        if (this.#activeOp?.epoch === opEpoch) this.#activeOp = null;
        resolveBarrier();
      }
    })();

    return done;
  }

  /** Clear published context snapshot under `ctxDeadlineMs` (preserving prior snapshot on timeout/close). */
  clearContext(): Promise<void> {
    if (this.#state !== "open") {
      return Promise.reject(
        new KernelError("pool_closed", "KernelPool is closed"),
      );
    }
    if (this.#activeOp !== null) {
      return Promise.reject(
        new KernelError(
          this.#activeOp.kind === "batch"
            ? "batch_in_progress"
            : "context_operation_in_progress",
          "Another operation is already in progress on this KernelPool",
        ),
      );
    }
    if (!this.manifest.hasContext) {
      return Promise.reject(
        new KernelError(
          "invalid_config",
          "Kernel does not accept a prepared context",
        ),
      );
    }

    const opEpoch = this.#poolEpoch;
    const ctxDeadlineMs = this.#deadlineMs !== null
      ? performance.now() + this.#deadlineMs
      : null;

    let timedOut = false;
    let timerHandle: { clear: () => void } | null = null;
    const activeWorkersToFence: KernelSubprocess[] = [];

    const cancelForClose = () => {
      timerHandle?.clear();
      for (const w of activeWorkersToFence) {
        w.fenced = true;
        w.closeTransport({ kind: "fenced" });
      }
    };

    let resolveClearBarrier!: () => void;
    const clearBarrier = new Promise<void>((r) => {
      resolveClearBarrier = r;
    });
    this.#activeOp = {
      kind: "context",
      snapshot: null,
      epoch: opEpoch,
      cancelForClose,
      done: clearBarrier,
    };

    const done = (async () => {
      try {
        if (ctxDeadlineMs !== null) {
          timerHandle = this.#armDeadlineTimer(ctxDeadlineMs, () => {
            timedOut = true;
            for (const w of activeWorkersToFence) {
              w.fenced = true;
              w.closeTransport({ kind: "fenced" });
            }
          });
        }

        // Clear any warm subprocess holding an installed context under ctxDeadlineMs.
        const toClear: KernelSubprocess[] = [];
        if (
          this.#directSubprocess !== null &&
          this.#directSubprocess.installedSnapshotId !== null
        ) {
          toClear.push(this.#directSubprocess);
        }
        for (const w of this.#warmSubprocesses) {
          if (w !== null && w.installedSnapshotId !== null) toClear.push(w);
        }

        if (toClear.length > 0) {
          for (const w of toClear) {
            w.opDeadlineMs = ctxDeadlineMs;
            activeWorkersToFence.push(w);
          }
          const results = await Promise.all(
            toClear.map((w) =>
              w.sendCommand(CMD_CLEAR_CTX, w.nextSeq++, null, 0)
            ),
          );
          if (this.#hooks?.onBeforeContextPublish) {
            await this.#hooks.onBeforeContextPublish();
          }
          if (this.#state !== "open" || this.#poolEpoch !== opEpoch) {
            await Promise.all(toClear.map((w) => this.#retireSubprocess(w)));
            throw new KernelError(
              "pool_closed",
              "KernelPool closed during clearContext",
            );
          }
          if (
            timedOut ||
            results.some((r) => r.kind === "fenced") ||
            (ctxDeadlineMs !== null && performance.now() >= ctxDeadlineMs)
          ) {
            await Promise.all(toClear.map((w) => this.#retireSubprocess(w)));
            throw new KernelError("timeout", "clearContext timed out");
          }
          for (let i = 0; i < toClear.length; i++) {
            const w = toClear[i];
            const res = results[i];
            w.opDeadlineMs = null;
            if (res.kind === "ctx_ok") {
              w.installedSnapshotId = null;
              w.storeHasPriorHistory = true;
              w.memoryBytes = res.memoryBytes;
            } else {
              await this.#retireSubprocess(w);
            }
          }
        } else {
          if (
            this.#inlineGuest !== null &&
            this.#inlineGuest.installedSnapshotId !== null
          ) {
            try {
              this.#inlineGuest.reset(0);
              this.#inlineGuest.clearFn!(0);
              this.#inlineGuest.finishInvocation?.();
              this.#inlineGuest.reset(0);
              this.#inlineGuest.installedSnapshotId = null;
              this.#inlineGuest.storeHasPriorHistory = true;
            } catch {
              this.#inlineGuest = null;
            }
          }
          if (this.#hooks?.onBeforeContextPublish) {
            await this.#hooks.onBeforeContextPublish();
          }
          if (this.#state !== "open" || this.#poolEpoch !== opEpoch) {
            throw new KernelError(
              "pool_closed",
              "KernelPool closed during clearContext",
            );
          }
          if (
            timedOut ||
            (ctxDeadlineMs !== null && performance.now() >= ctxDeadlineMs)
          ) {
            throw new KernelError("timeout", "clearContext timed out");
          }
        }

        const prev = this.#currentCtx;
        this.#currentCtx = null;
        if (prev !== null) {
          this.#contextSnapshotBytes = Math.max(
            0,
            this.#contextSnapshotBytes - prev.bytes.byteLength,
          );
        }
      } finally {
        timerHandle?.clear();
        if (this.#activeOp?.epoch === opEpoch) this.#activeOp = null;
        resolveClearBarrier();
      }
    })();

    return done;
  }

  runFixed(items: ArrayBufferView): Promise<Uint32Array> {
    if (this.manifest.variableOutput) {
      return Promise.reject(
        new KernelError(
          "invalid_config",
          `Kernel ${this.manifest.name} emits variable output; use runVariable/runVariableChunks`,
        ),
      );
    }
    return this.#beginBatch("fixed", items) as Promise<Uint32Array>;
  }

  runVariableChunks(items: ArrayBufferView): Promise<Uint32Array[]> {
    if (!this.manifest.variableOutput) {
      return Promise.reject(
        new KernelError(
          "invalid_config",
          `Kernel ${this.manifest.name} emits fixed output; use runFixed`,
        ),
      );
    }
    return this.#beginBatch("variable_chunks", items) as Promise<Uint32Array[]>;
  }

  runVariable(items: ArrayBufferView): Promise<Uint32Array> {
    if (!this.manifest.variableOutput) {
      return Promise.reject(
        new KernelError(
          "invalid_config",
          `Kernel ${this.manifest.name} emits fixed output; use runFixed`,
        ),
      );
    }
    return this.#beginBatch("variable_flat", items) as Promise<Uint32Array>;
  }

  #beginBatch(
    mode: "fixed" | "variable_chunks" | "variable_flat",
    items: ArrayBufferView,
  ): Promise<Uint32Array | Uint32Array[]> {
    // Synchronously BEFORE any await: lifecycle, exclusivity, context, and private copy!
    if (this.#state !== "open") {
      return Promise.reject(
        new KernelError("pool_closed", "KernelPool is closed"),
      );
    }
    if (this.#activeOp !== null) {
      return Promise.reject(
        new KernelError(
          this.#activeOp.kind === "context"
            ? "context_operation_in_progress"
            : "batch_in_progress",
          "Another operation is already in progress on this KernelPool",
        ),
      );
    }
    if (this.manifest.hasContext && this.#currentCtx === null) {
      return Promise.reject(
        new KernelError(
          "context_not_prepared",
          `Prepared kernel ${this.manifest.name} requires setContext() before run`,
        ),
      );
    }

    const requiredPhysical = mode === "variable_flat"
      ? this.#maxTotalOutputBytes * 2
      : this.#maxTotalOutputBytes;
    if (this.#maxPhysicalOutputBytes < requiredPhysical) {
      return Promise.reject(
        new KernelError(
          "invalid_config",
          `maxPhysicalOutputBytes (${this.#maxPhysicalOutputBytes}) < required (${requiredPhysical})`,
        ),
      );
    }

    // Validate & copy caller bytes privately via captured primordials!
    const inputSnapshot = copyPrivateBytes(items);
    const inItemBytes = this.manifest.inSchema.stride * 4;
    if (inputSnapshot.byteLength % inItemBytes !== 0) {
      return Promise.reject(
        new KernelError(
          "invalid_input",
          `Input byte length (${inputSnapshot.byteLength}) is not a multiple of item size (${inItemBytes})`,
        ),
      );
    }
    if (
      this.#maxInputSnapshotBytes !== null &&
      inputSnapshot.byteLength > this.#maxInputSnapshotBytes
    ) {
      return Promise.reject(
        new KernelError(
          "input_snapshot_budget_exceeded",
          `Input snapshot (${inputSnapshot.byteLength} B) exceeds maxInputSnapshotBytes (${this.#maxInputSnapshotBytes} B)`,
        ),
      );
    }

    const itemCount = inputSnapshot.byteLength / inItemBytes;
    if (mode === "fixed" && itemCount > 0) {
      const totalFixedBytes = itemCount * this.manifest.outSchema.stride * 4;
      const limit = Math.min(
        this.#maxTotalOutputBytes,
        this.#maxPhysicalOutputBytes,
      );
      if (totalFixedBytes > limit) {
        return Promise.reject(
          new KernelError(
            "output_budget_exceeded",
            `Fixed output (${totalFixedBytes} B) exceeds output limit (${limit} B)`,
            0,
          ),
        );
      }
    }

    const batchSnapshot = this.#currentCtx;
    const batchEpoch = this.#poolEpoch;
    this.#inputSnapshotBytes = inputSnapshot.byteLength;
    this.#resetBatchPeak();

    const batchDeadlineMs = this.#deadlineMs !== null
      ? performance.now() + this.#deadlineMs
      : null;

    let timedOut = false;
    let closedAbort = false;
    let timerHandle: { clear: () => void } | null = null;
    const batchSubprocesses = new Set<KernelSubprocess>();

    const fenceBatchWorkers = () => {
      for (const w of batchSubprocesses) {
        w.fenced = true;
        w.closeTransport({ kind: "fenced" });
      }
    };

    const cancelForClose = () => {
      closedAbort = true;
      timerHandle?.clear();
      fenceBatchWorkers();
    };

    let resolveBatchBarrier!: () => void;
    const batchBarrier = new Promise<void>((r) => {
      resolveBatchBarrier = r;
    });
    this.#activeOp = {
      kind: "batch",
      snapshot: batchSnapshot,
      epoch: batchEpoch,
      cancelForClose,
      done: batchBarrier,
    };

    const done = (async (): Promise<Uint32Array | Uint32Array[]> => {
      try {
        if (batchDeadlineMs !== null) {
          timerHandle = this.#armDeadlineTimer(batchDeadlineMs, () => {
            timedOut = true;
            fenceBatchWorkers();
          });
        }

        const checkOpenOrTimeout = () => {
          if (
            closedAbort || this.#state !== "open" ||
            this.#poolEpoch !== batchEpoch
          ) {
            throw new KernelError(
              "pool_closed",
              "KernelPool closed during batch",
            );
          }
          if (
            timedOut ||
            (batchDeadlineMs !== null && performance.now() >= batchDeadlineMs)
          ) {
            throw new KernelError("timeout", "Batch timed out");
          }
        };

        // Empty batch (count == 0): already enforced ContextNotPrepared above!
        if (itemCount === 0) {
          if (this.manifest.hasContext && batchSnapshot !== null) {
            if (this.#deadlineMs !== null || this.#workersCount > 0) {
              const ref = {
                worker: this.#workersCount === 0
                  ? this.#directSubprocess
                  : this.#warmSubprocesses[0],
              };
              const res = await this.#ensureSubprocessSnapshot(
                ref,
                0,
                batchSnapshot,
                batchDeadlineMs,
                batchEpoch,
              );
              if (this.#workersCount === 0) this.#directSubprocess = ref.worker;
              else this.#warmSubprocesses[0] = ref.worker;
              if (!res.ok) throw res.error;
              res.worker.opDeadlineMs = null;
            } else {
              this.#ensureInlineSnapshot(batchSnapshot);
            }
          }
          checkOpenOrTimeout();
          return mode === "variable_chunks" ? [] : new Uint32Array(0);
        }

        const useFallback = this.#workersCount > 0 && this.#forceFallback;
        if (useFallback) this.#fallbacks++;
        const runSerial = this.#workersCount === 0 || useFallback;

        if (runSerial && this.#deadlineMs === null) {
          // Synchronous inline serial execution (strictly when deadlineMs === null).
          const res = await this.#runInlineSerial(
            mode,
            inputSnapshot,
            itemCount,
            batchSnapshot,
            batchEpoch,
            checkOpenOrTimeout,
          );
          checkOpenOrTimeout();
          return res;
        }

        // Subprocess execution: either 1 serial subprocess (workers == 0 w/ deadline OR fallback w/ deadline)
        // or parallel worker pool (workers >= 1).
        const activeCount = runSerial ? 1 : this.#workersCount;
        const result = mode === "fixed"
          ? await this.#runSubprocessFixed(
            inputSnapshot,
            itemCount,
            batchSnapshot,
            batchEpoch,
            batchDeadlineMs,
            activeCount,
            runSerial,
            batchSubprocesses,
            () =>
              closedAbort || this.#state !== "open" ||
              this.#poolEpoch !== batchEpoch,
            () =>
              timedOut ||
              (batchDeadlineMs !== null &&
                performance.now() >= batchDeadlineMs),
          )
          : await this.#runSubprocessVariable(
            mode,
            inputSnapshot,
            itemCount,
            batchSnapshot,
            batchEpoch,
            batchDeadlineMs,
            activeCount,
            runSerial,
            batchSubprocesses,
            () =>
              closedAbort || this.#state !== "open" ||
              this.#poolEpoch !== batchEpoch,
            () =>
              timedOut ||
              (batchDeadlineMs !== null &&
                performance.now() >= batchDeadlineMs),
          );

        checkOpenOrTimeout();
        return result;
      } finally {
        timerHandle?.clear();
        this.#inputSnapshotBytes = 0;
        this.#fixedOutputBytes = 0;
        this.#bufferedChunkBytes = 0;
        this.#inFlightGrantBytes = 0;
        this.#concatScratchBytes = 0;
        if (this.#activeOp?.epoch === batchEpoch) this.#activeOp = null;
        resolveBatchBarrier();
      }
    })();

    return done;
  }

  /** Serial inline execution (ONLY when deadlineMs === null). */
  async #runInlineSerial(
    mode: "fixed" | "variable_chunks" | "variable_flat",
    inputSnapshot: Uint8Array,
    itemCount: number,
    batchSnapshot: PreparedContextSnapshot | null,
    batchEpoch: number,
    checkOpenOrTimeout: () => void,
  ): Promise<Uint32Array | Uint32Array[]> {
    const inItemBytes = this.manifest.inSchema.stride * 4;
    const outItemBytes = this.manifest.outSchema.stride * 4;

    if (mode === "fixed") {
      const totalFixedBytes = itemCount * outItemBytes;
      const outputBuf = new ArrayBuffer(totalFixedBytes);
      const outputU8 = new Uint8Array(outputBuf);
      this.#fixedOutputBytes = totalFixedBytes;
      this.#recordPeak();

      for (let start = 0; start < itemCount; start += this.maxChunkItems) {
        const end = Math.min(itemCount, start + this.maxChunkItems);
        const expectedBytes = (end - start) * outItemBytes;
        let retriedFresh = false;
        for (;;) {
          checkOpenOrTimeout();
          this.#ensureInlineSnapshot(batchSnapshot);
          const guest = this.#ensureInlineGuest();
          const eligible = guest.storeHasPriorHistory && !retriedFresh;
          const slice = inputSnapshot.subarray(
            start * inItemBytes,
            end * inItemBytes,
          );
          let ptr = 0;
          try {
            const inPtr = guest.writePacket(slice);
            ptr = guest.entryFn(inPtr) >>> 0;
          } catch (err) {
            const oom = guest.readArenaOom() || isMemoryGrowError(err);
            if (oom) {
              this.#inlineGuest = null;
              if (eligible) {
                retriedFresh = true;
                this.#freshRetries++;
                continue;
              }
              throw new KernelError("out_of_memory", "Kernel OOM", start);
            }
            let cleanupOk = true;
            try {
              guest.finishInvocation?.();
              guest.reset(0);
              if (guest.readArenaOom()) cleanupOk = false;
            } catch {
              cleanupOk = false;
            }
            if (
              !cleanupOk || guest.memoryBytes() >= this.#retireMemoryThreshold
            ) {
              this.#inlineGuest = null;
            } else {
              guest.storeHasPriorHistory = true;
            }
            throw new KernelError(
              "run_trap",
              `Kernel trapped: ${String(err)}`,
              start,
            );
          }

          const buf = guest.memory.buffer;
          const lenWords = new DataView(buf).getUint32(ptr, true);
          if (lenWords * 4 !== expectedBytes) {
            this.#inlineGuest = null;
            throw new KernelError(
              "transport_fault",
              "Fixed output length mismatch",
              start,
            );
          }
          outputU8.set(
            new Uint8Array(buf, ptr + 4, expectedBytes),
            start * outItemBytes,
          );
          let cleanupOk = true;
          try {
            guest.finishInvocation?.();
            guest.reset(0);
            if (guest.readArenaOom()) cleanupOk = false;
          } catch {
            cleanupOk = false;
          }
          if (this.#hooks?.forceCleanupFailAtStart?.has(start)) {
            cleanupOk = false;
          }
          if (!cleanupOk) {
            this.#inlineGuest = null;
            throw new KernelError("cleanup_trap", "Cleanup trapped", start);
          }
          guest.storeHasPriorHistory = true;
          if (guest.memoryBytes() >= this.#retireMemoryThreshold) {
            this.#inlineGuest = null;
          }
          break;
        }
      }
      return new Uint32Array(outputBuf);
    }

    // Inline variable output
    const heap = new MinRangeHeap();
    for (let start = 0; start < itemCount; start += this.maxChunkItems) {
      heap.push({
        start,
        end: Math.min(itemCount, start + this.maxChunkItems),
        retriedFresh: false,
      });
    }
    const chunks: Uint32Array[] = [];
    let settledBytes = 0;
    while (heap.size > 0) {
      checkOpenOrTimeout();
      const range = heap.pop()!;
      for (;;) {
        this.#ensureInlineSnapshot(batchSnapshot);
        const guest = this.#ensureInlineGuest();
        const eligible = guest.storeHasPriorHistory && !range.retriedFresh;
        const slice = inputSnapshot.subarray(
          range.start * inItemBytes,
          range.end * inItemBytes,
        );
        let ptr = 0;
        try {
          const inPtr = guest.writePacket(slice);
          ptr = guest.entryFn(inPtr) >>> 0;
        } catch (err) {
          const oom = guest.readArenaOom() || isMemoryGrowError(err);
          if (oom) {
            this.#inlineGuest = null;
            if (eligible) {
              range.retriedFresh = true;
              this.#freshRetries++;
              continue;
            }
            throw new KernelError("out_of_memory", "Kernel OOM", range.start);
          }
          let cleanupOk = true;
          try {
            guest.finishInvocation?.();
            guest.reset(0);
            if (guest.readArenaOom()) cleanupOk = false;
          } catch {
            cleanupOk = false;
          }
          if (
            !cleanupOk || guest.memoryBytes() >= this.#retireMemoryThreshold
          ) {
            this.#inlineGuest = null;
          } else {
            guest.storeHasPriorHistory = true;
          }
          throw new KernelError(
            "run_trap",
            `Kernel trapped: ${String(err)}`,
            range.start,
          );
        }

        const buf = guest.memory.buffer;
        const lenWords = new DataView(buf).getUint32(ptr, true);
        if (lenWords === 0xffff_ffff) {
          // Unified [0xffffffff] transition: run cleanup FIRST!
          let cleanupOk = true;
          try {
            guest.finishInvocation?.();
            guest.reset(0);
            if (guest.readArenaOom()) cleanupOk = false;
          } catch {
            cleanupOk = false;
          }
          if (this.#hooks?.forceCleanupFailAtStart?.has(range.start)) {
            cleanupOk = false;
          }
          if (!cleanupOk) {
            this.#inlineGuest = null;
            if (range.end - range.start === 1) {
              throw new KernelError(
                "single_item_output_overflow",
                "Single item overflowed transport budget",
                range.start,
              );
            }
            throw new KernelError(
              "cleanup_trap",
              "Overflow cleanup trapped",
              range.start,
            );
          }
          guest.storeHasPriorHistory = true;
          if (guest.memoryBytes() >= this.#retireMemoryThreshold) {
            this.#inlineGuest = null;
          }
          if (range.end - range.start === 1) {
            throw new KernelError(
              "single_item_output_overflow",
              "Single item overflowed transport budget",
              range.start,
            );
          }
          const mid = range.start + ((range.end - range.start) >> 1);
          heap.push({ start: mid, end: range.end, retriedFresh: false });
          heap.push({ start: range.start, end: mid, retriedFresh: false });
          break;
        }

        const resultBytes = lenWords * 4;
        const overBudget =
          settledBytes + resultBytes > this.#maxTotalOutputBytes;
        let outWords: Uint32Array | null = null;
        if (!overBudget) {
          outWords = new Uint32Array(lenWords);
          if (resultBytes > 0) {
            new Uint8Array(outWords.buffer).set(
              new Uint8Array(buf, ptr + 4, resultBytes),
            );
          }
        }
        let cleanupOk = true;
        try {
          guest.finishInvocation?.();
          guest.reset(0);
          if (guest.readArenaOom()) cleanupOk = false;
        } catch {
          cleanupOk = false;
        }
        if (this.#hooks?.forceCleanupFailAtStart?.has(range.start)) {
          cleanupOk = false;
        }
        if (!cleanupOk) {
          this.#inlineGuest = null;
          if (overBudget) {
            throw new KernelError(
              "output_budget_exceeded",
              "Output budget exceeded",
              range.start,
            );
          }
          throw new KernelError("cleanup_trap", "Cleanup trapped", range.start);
        }
        guest.storeHasPriorHistory = true;
        if (guest.memoryBytes() >= this.#retireMemoryThreshold) {
          this.#inlineGuest = null;
        }
        if (overBudget) {
          throw new KernelError(
            "output_budget_exceeded",
            "Output budget exceeded",
            range.start,
          );
        }
        settledBytes += resultBytes;
        this.#bufferedChunkBytes = settledBytes;
        this.#recordPeak();
        chunks.push(outWords!);
        break;
      }
    }

    if (mode === "variable_chunks") return chunks;
    if (chunks.length === 1) return chunks[0];
    return await this.#concatenateVariableChunks(
      chunks,
      settledBytes,
      batchEpoch,
      null,
    );
  }

  async #concatenateVariableChunks(
    chunks: Uint32Array[],
    totalBytes: number,
    batchEpoch: number,
    batchDeadlineMs: number | null,
  ): Promise<Uint32Array> {
    if (chunks.length === 0) return new Uint32Array(0);
    if (chunks.length === 1) return chunks[0];
    const totalWords = totalBytes >>> 2;
    const out = new Uint32Array(totalWords);
    this.#concatScratchBytes = totalBytes;
    this.#recordPeak();
    let offset = 0;
    for (let i = 0; i < chunks.length; i++) {
      const c = chunks[i];
      out.set(c, offset);
      offset += c.length;
      const freed = c.byteLength;
      chunks[i] = new Uint32Array(0);
      this.#bufferedChunkBytes = Math.max(0, this.#bufferedChunkBytes - freed);
    }
    if (this.#hooks?.onBeforeConcatPublish) {
      await this.#hooks.onBeforeConcatPublish();
    }
    if (this.#state !== "open" || this.#poolEpoch !== batchEpoch) {
      this.#concatScratchBytes = 0;
      throw new KernelError("pool_closed", "KernelPool closed before publish");
    }
    if (batchDeadlineMs !== null && performance.now() >= batchDeadlineMs) {
      this.#concatScratchBytes = 0;
      throw new KernelError("timeout", "Batch timed out during concatenation");
    }
    return out;
  }

  /**
   * True 1x single-buffer `runFixed` over persistent Deno subprocesses (§5.1):
   * - All workers execute Wasm chunks in parallel (0 JS copy bytes while computing).
   * - Ready chunks drain through ONE serialized `fixedCopyQueue` using BYOB reads
   *   directly into the ONE `outputBuf`.
   * - On recoverable `CLEANUP_FAIL` / deterministic trap: converts existing queued
   *   `fixedCopyQueue` entries AND future `READY` arrivals to cleanup-only `CMD_DISCARD`!
   * - On BYOB read rejection / EOF / timeout: immediate batch abort + kill-first `retireSubprocess`.
   */
  async #runSubprocessFixed(
    inputSnapshot: Uint8Array,
    itemCount: number,
    batchSnapshot: PreparedContextSnapshot | null,
    batchEpoch: number,
    batchDeadlineMs: number | null,
    workerCount: number,
    isDirectOrFallback: boolean,
    batchSubprocesses: Set<KernelSubprocess>,
    isClosed: () => boolean,
    isTimedOut: () => boolean,
  ): Promise<Uint32Array> {
    const inItemBytes = this.manifest.inSchema.stride * 4;
    const outItemBytes = this.manifest.outSchema.stride * 4;
    const totalFixedBytes = itemCount * outItemBytes;

    let outputBuf: ArrayBuffer | null = new ArrayBuffer(totalFixedBytes);
    this.#fixedOutputBytes = totalFixedBytes;
    this.#recordPeak();

    const heap = new MinRangeHeap();
    for (let start = 0; start < itemCount; start += this.maxChunkItems) {
      heap.push({
        start,
        end: Math.min(itemCount, start + this.maxChunkItems),
        retriedFresh: false,
      });
    }

    let earliestFailedItem = Number.POSITIVE_INFINITY;
    const failuresByStart = new Map<number, FailureKind>();
    let fatalAbort: KernelError | null = null;

    const recordFailure = (start: number, failure: FailureKind) => {
      const existing = failuresByStart.get(start);
      if (
        existing === undefined ||
        failurePriority(failure) > failurePriority(existing)
      ) {
        failuresByStart.set(start, failure);
      }
      if (start < earliestFailedItem) {
        earliestFailedItem = start;
        heap.dropAtOrAbove(earliestFailedItem);
      }
    };

    // Single-owner serialized copy_grant_fixed queue.
    interface ReadyFixedEntry {
      readonly worker: KernelSubprocess;
      readonly range: WorkRange;
      readonly resultBytes: number;
      readonly slotIdx: number;
      readonly doneResolve: (action: "grant" | "discard" | "abort") => void;
    }
    const fixedCopyQueue: ReadyFixedEntry[] = [];
    let fixedGrantInFlight = false;

    const convertQueueToDiscard = () => {
      while (fixedCopyQueue.length > 0) {
        const entry = fixedCopyQueue.shift()!;
        entry.doneResolve(fatalAbort !== null ? "abort" : "discard");
      }
    };

    const triggerFatalAbort = (err: KernelError) => {
      if (fatalAbort === null) fatalAbort = err;
      heap.clear();
      convertQueueToDiscard();
      for (const w of batchSubprocesses) {
        w.fenced = true;
        w.closeTransport({ kind: "fenced" });
      }
    };

    const pumpFixedQueue = () => {
      if (fatalAbort !== null) {
        convertQueueToDiscard();
        return;
      }
      if (earliestFailedItem < Number.POSITIVE_INFINITY) {
        convertQueueToDiscard();
        if (!fixedGrantInFlight && outputBuf !== null) {
          outputBuf = null;
          this.#fixedOutputBytes = 0;
        }
        return;
      }
      if (
        fixedGrantInFlight || outputBuf === null || fixedCopyQueue.length === 0
      ) {
        return;
      }
      // Pick lowest start_item ready entry.
      fixedCopyQueue.sort((a, b) => a.range.start - b.range.start);
      const next = fixedCopyQueue.shift()!;
      fixedGrantInFlight = true;
      next.doneResolve("grant");
    };

    const getSlotWorker = (slotIdx: number): KernelSubprocess | null =>
      isDirectOrFallback
        ? this.#directSubprocess
        : this.#warmSubprocesses[slotIdx];
    const setSlotWorker = (slotIdx: number, w: KernelSubprocess | null) => {
      if (isDirectOrFallback) this.#directSubprocess = w;
      else this.#warmSubprocesses[slotIdx] = w;
    };

    const activeWorkersToRetire: Promise<void>[] = [];

    const runWorkerLoop = async (slotIdx: number) => {
      for (;;) {
        if (fatalAbort !== null || isClosed() || isTimedOut()) break;
        const range = heap.pop();
        if (range === undefined) break;
        if (range.start >= earliestFailedItem) continue;

        const ref = { worker: getSlotWorker(slotIdx) };
        const snapRes = await this.#ensureSubprocessSnapshot(
          ref,
          slotIdx,
          batchSnapshot,
          batchDeadlineMs,
          batchEpoch,
        );
        setSlotWorker(slotIdx, ref.worker);
        if (!snapRes.ok) {
          if (
            snapRes.error.code === "pool_closed" ||
            snapRes.error.code === "timeout" ||
            snapRes.error.code === "transport_fault"
          ) {
            triggerFatalAbort(snapRes.error);
            break;
          }
          recordFailure(range.start, {
            kind: snapRes.error.code === "out_of_memory"
              ? "out_of_memory"
              : snapRes.error.code === "cleanup_trap"
              ? "cleanup_trap"
              : "run_trap",
            message: snapRes.error.message,
            resultBytes: 0,
          } as FailureKind);
          pumpFixedQueue();
          continue;
        }

        const w = snapRes.worker;
        batchSubprocesses.add(w);
        w.opDeadlineMs = batchDeadlineMs;

        const eligible = w.storeHasPriorHistory && !range.retriedFresh;
        const slice = inputSnapshot.subarray(
          range.start * inItemBytes,
          range.end * inItemBytes,
        );
        const runRes = await w.sendCommand(CMD_RUN, w.nextSeq++, slice, 0);

        if (isClosed()) {
          triggerFatalAbort(
            new KernelError("pool_closed", "KernelPool closed"),
          );
          activeWorkersToRetire.push(this.#retireSubprocess(w));
          break;
        }
        if (runRes.kind === "fenced" || isTimedOut()) {
          triggerFatalAbort(new KernelError("timeout", "Batch timed out"));
          activeWorkersToRetire.push(this.#retireSubprocess(w));
          break;
        }
        if (runRes.kind === "fault") {
          triggerFatalAbort(
            new KernelError(
              "transport_fault",
              `Worker fault: ${runRes.reason}`,
            ),
          );
          activeWorkersToRetire.push(this.#retireSubprocess(w));
          break;
        }
        if (runRes.kind === "arena_oom") {
          await this.#retireSubprocess(w);
          setSlotWorker(slotIdx, null);
          if (eligible) {
            range.retriedFresh = true;
            this.#freshRetries++;
            heap.push(range);
          } else {
            recordFailure(range.start, {
              kind: "out_of_memory",
              message: "Kernel out of memory",
            });
            pumpFixedQueue();
          }
          continue;
        }
        if (runRes.kind === "run_trap") {
          if (!runRes.cleanupOk) {
            await this.#retireSubprocess(w);
            setSlotWorker(slotIdx, null);
          } else {
            w.storeHasPriorHistory = true;
            if (w.memoryBytes >= this.#retireMemoryThreshold) {
              await this.#retireSubprocess(w);
              setSlotWorker(slotIdx, null);
            }
          }
          recordFailure(range.start, {
            kind: "run_trap",
            message: "Kernel trapped",
          });
          pumpFixedQueue();
          continue;
        }
        if (runRes.kind !== "ready") {
          triggerFatalAbort(
            new KernelError(
              "transport_fault",
              `Unexpected run response: ${runRes.kind}`,
            ),
          );
          activeWorkersToRetire.push(this.#retireSubprocess(w));
          break;
        }

        const expectedBytes = (range.end - range.start) * outItemBytes;
        if (runRes.resultBytes !== expectedBytes) {
          triggerFatalAbort(
            new KernelError(
              "transport_fault",
              `Fixed output byte mismatch: got ${runRes.resultBytes}, expected ${expectedBytes}`,
            ),
          );
          activeWorkersToRetire.push(this.#retireSubprocess(w));
          break;
        }

        if (this.#hooks?.onAfterReady) {
          await this.#hooks.onAfterReady({
            start: range.start,
            end: range.end,
            resultBytes: runRes.resultBytes,
            workerIndex: slotIdx,
          });
        }
        if (isClosed()) {
          triggerFatalAbort(
            new KernelError("pool_closed", "KernelPool closed"),
          );
          activeWorkersToRetire.push(this.#retireSubprocess(w));
          break;
        }
        if (isTimedOut() || fatalAbort !== null) {
          if (isTimedOut()) {
            triggerFatalAbort(new KernelError("timeout", "Batch timed out"));
          }
          activeWorkersToRetire.push(this.#retireSubprocess(w));
          break;
        }

        // Request serialized fixed grant or discard.
        const decision = await new Promise<"grant" | "discard" | "abort">(
          (resolve) => {
            if (fatalAbort !== null) {
              resolve("abort");
              return;
            }
            if (earliestFailedItem < Number.POSITIVE_INFINITY) {
              resolve("discard");
              return;
            }
            fixedCopyQueue.push({
              worker: w,
              range,
              resultBytes: runRes.resultBytes,
              slotIdx,
              doneResolve: resolve,
            });
            pumpFixedQueue();
          },
        );

        if (decision === "abort" || fatalAbort !== null) {
          activeWorkersToRetire.push(this.#retireSubprocess(w));
          break;
        }

        if (decision === "discard") {
          const discRes = await w.sendCommand(
            CMD_DISCARD,
            w.nextSeq++,
            null,
            0,
          );
          if (isClosed()) {
            triggerFatalAbort(
              new KernelError("pool_closed", "KernelPool closed"),
            );
            activeWorkersToRetire.push(this.#retireSubprocess(w));
            break;
          }
          if (discRes.kind === "fenced" || isTimedOut()) {
            triggerFatalAbort(new KernelError("timeout", "Batch timed out"));
            activeWorkersToRetire.push(this.#retireSubprocess(w));
            break;
          }
          if (discRes.kind === "fault") {
            triggerFatalAbort(
              new KernelError(
                "transport_fault",
                `Discard fault: ${discRes.reason}`,
              ),
            );
            activeWorkersToRetire.push(this.#retireSubprocess(w));
            break;
          }
          const forcedCleanupFail = this.#hooks?.forceCleanupFailAtStart?.has(
            range.start,
          );
          if (discRes.kind === "cleanup_fail" || forcedCleanupFail) {
            await this.#retireSubprocess(w);
            setSlotWorker(slotIdx, null);
            recordFailure(range.start, {
              kind: "cleanup_trap",
              message: "Cleanup trapped during discard",
              resultBytes: runRes.resultBytes,
            });
            pumpFixedQueue();
          } else if (discRes.kind === "discard_ok") {
            w.storeHasPriorHistory = true;
            w.memoryBytes = discRes.memoryBytes;
            if (w.memoryBytes >= this.#retireMemoryThreshold) {
              await this.#retireSubprocess(w);
              setSlotWorker(slotIdx, null);
            }
          }
          continue;
        }

        // decision === "grant": single-owner serialized BYOB read directly into outputBuf!
        const targetBuf = outputBuf!;
        outputBuf = null; // checked out exclusively to this grant!
        const grantPromise = w.sendCommand(
          CMD_COPY_GRANT,
          w.nextSeq++,
          null,
          runRes.resultBytes,
          {
            kind: "fixed",
            targetBuf,
            byteOffset: range.start * outItemBytes,
            expectedBytes: runRes.resultBytes,
          },
        );
        if (this.#hooks?.onAfterFixedGrantIssued) {
          await this.#hooks.onAfterFixedGrantIssued({
            start: range.start,
            end: range.end,
            workerIndex: slotIdx,
          });
        }
        const grantRes = await grantPromise;
        fixedGrantInFlight = false;

        if (isClosed()) {
          triggerFatalAbort(
            new KernelError("pool_closed", "KernelPool closed"),
          );
          activeWorkersToRetire.push(this.#retireSubprocess(w));
          break;
        }
        if (grantRes.kind === "fenced" || isTimedOut()) {
          triggerFatalAbort(new KernelError("timeout", "Batch timed out"));
          activeWorkersToRetire.push(this.#retireSubprocess(w));
          break;
        }
        if (grantRes.kind === "fault") {
          // Backing-store-losing BYOB fault: immediate non-deterministic batch abort!
          triggerFatalAbort(
            new KernelError(
              "transport_fault",
              `BYOB grant fault: ${grantRes.reason}`,
            ),
          );
          activeWorkersToRetire.push(this.#retireSubprocess(w));
          break;
        }

        const forcedCleanupFail = this.#hooks?.forceCleanupFailAtStart?.has(
          range.start,
        );
        if (grantRes.kind === "cleanup_fail" || forcedCleanupFail) {
          // Recoverable cleanup failure: outputBuf returned intact!
          outputBuf =
            grantRes.kind === "cleanup_fail" || grantRes.kind === "commit_ok"
              ? (grantRes.returnedBuf ?? null)
              : null;
          await this.#retireSubprocess(w);
          setSlotWorker(slotIdx, null);
          recordFailure(range.start, {
            kind: "cleanup_trap",
            message: "Cleanup trapped after fixed copy",
            resultBytes: runRes.resultBytes,
          });
          // Drop outputBuf now that it's handed back & convert queued entries to discard!
          outputBuf = null;
          this.#fixedOutputBytes = 0;
          pumpFixedQueue();
          continue;
        }

        if (
          grantRes.kind === "commit_ok" && grantRes.returnedBuf !== undefined
        ) {
          outputBuf = grantRes.returnedBuf;
          w.storeHasPriorHistory = true;
          w.memoryBytes = grantRes.memoryBytes;
          if (w.memoryBytes >= this.#retireMemoryThreshold) {
            await this.#retireSubprocess(w);
            setSlotWorker(slotIdx, null);
          }
          pumpFixedQueue();
          continue;
        }

        triggerFatalAbort(
          new KernelError(
            "transport_fault",
            `Unexpected fixed grant outcome: ${grantRes.kind}`,
          ),
        );
        activeWorkersToRetire.push(this.#retireSubprocess(w));
        break;
      }
    };

    await Promise.all(
      Array.from({ length: workerCount }, (_, idx) => runWorkerLoop(idx)),
    );
    // Clear opDeadlineMs on surviving warm workers.
    for (const w of batchSubprocesses) {
      if (w.terminal === null) w.opDeadlineMs = null;
    }

    if (fatalAbort !== null || isClosed() || isTimedOut()) {
      // Ensure every subprocess involved in the aborted batch finishes full 5-step retirement
      // BEFORE releasing fixedOutputBytes!
      for (const w of batchSubprocesses) {
        if (w.terminal !== null || w.fenced) {
          activeWorkersToRetire.push(this.#retireSubprocess(w));
        }
      }
      await Promise.all(activeWorkersToRetire);
      outputBuf = null;
      this.#fixedOutputBytes = 0;
      if (isClosed()) {
        throw new KernelError("pool_closed", "KernelPool closed during batch");
      }
      if (isTimedOut()) {
        throw new KernelError("timeout", "Batch timed out");
      }
      throw fatalAbort!;
    }

    await Promise.all(activeWorkersToRetire);

    if (earliestFailedItem < Number.POSITIVE_INFINITY) {
      outputBuf = null;
      this.#fixedOutputBytes = 0;
      const err = failuresByStart.get(earliestFailedItem)!;
      throw toKernelError(earliestFailedItem, err);
    }

    if (outputBuf === null) {
      throw new KernelError("transport_fault", "Fixed output buffer lost");
    }
    return new Uint32Array(outputBuf);
  }

  /**
   * Variable-output subprocess execution with two-step `READY` -> `COPY_GRANT`/`DISCARD`,
   * `PendingFrontierGrant` drain, cooperative post-READY settlement, unified `[0xffffffff]`
   * transition, and worker-count-invariant same-`start_item` precedence (§5.1).
   */
  async #runSubprocessVariable(
    mode: "variable_chunks" | "variable_flat",
    inputSnapshot: Uint8Array,
    itemCount: number,
    batchSnapshot: PreparedContextSnapshot | null,
    batchEpoch: number,
    batchDeadlineMs: number | null,
    workerCount: number,
    isDirectOrFallback: boolean,
    batchSubprocesses: Set<KernelSubprocess>,
    isClosed: () => boolean,
    isTimedOut: () => boolean,
  ): Promise<Uint32Array | Uint32Array[]> {
    const inItemBytes = this.manifest.inSchema.stride * 4;

    const heap = new MinRangeHeap();
    for (let start = 0; start < itemCount; start += this.maxChunkItems) {
      heap.push({
        start,
        end: Math.min(itemCount, start + this.maxChunkItems),
        retriedFresh: false,
      });
    }

    let frontierItem = 0;
    let settledPrefixBytes = 0;
    let higherBufferedBytes = 0;
    let earliestFailedItem = Number.POSITIVE_INFINITY;
    const failuresByStart = new Map<number, FailureKind>();
    const cleanupResultBytesByStart = new Map<number, number>();
    const settledChunks: Uint32Array[] = [];
    const higherChunks = new Map<number, VariableCompletedChunk>();
    let fatalAbort: KernelError | null = null;

    // Track PendingFrontierGrant and parked speculative workers.
    let pendingFrontierGrant: {
      readonly range: WorkRange;
      readonly resultBytes: number;
      readonly resolve: (action: "grant" | "discard" | "abort") => void;
    } | null = null;
    const workAvailableWaiters: (() => void)[] = [];
    let activeExecuting = 0;

    const wakeWorkWaiters = () => {
      while (workAvailableWaiters.length > 0) {
        workAvailableWaiters.shift()!();
      }
    };

    const recordFailure = (start: number, failure: FailureKind) => {
      if (failure.kind === "cleanup_trap") {
        cleanupResultBytesByStart.set(start, failure.resultBytes);
      }
      const existing = failuresByStart.get(start);
      if (
        existing === undefined ||
        failurePriority(failure) > failurePriority(existing)
      ) {
        failuresByStart.set(start, failure);
      }
      if (start < earliestFailedItem) {
        earliestFailedItem = start;
        heap.dropAtOrAbove(earliestFailedItem);
        // Drop completed higher chunks >= earliestFailedItem immediately.
        for (const [s, c] of [...higherChunks.entries()]) {
          if (s >= earliestFailedItem) {
            higherChunks.delete(s);
            if (!c.overBudgetHint) {
              higherBufferedBytes -= c.byteLength;
              this.#bufferedChunkBytes = settledPrefixBytes +
                higherBufferedBytes;
            }
          }
        }
      }
      wakeWorkWaiters();
    };

    const triggerFatalAbort = (err: KernelError) => {
      if (fatalAbort === null) fatalAbort = err;
      heap.clear();
      if (pendingFrontierGrant !== null) {
        const p = pendingFrontierGrant;
        pendingFrontierGrant = null;
        p.resolve("abort");
      }
      for (const w of batchSubprocesses) {
        w.fenced = true;
        w.closeTransport({ kind: "fenced" });
      }
      wakeWorkWaiters();
    };

    const evictHighestHigherChunk = (minStartExclusive: number): boolean => {
      let maxStart = -1;
      for (const [s, c] of higherChunks) {
        if (s > minStartExclusive && !c.overBudgetHint && s > maxStart) {
          maxStart = s;
        }
      }
      if (maxStart === -1) return false;
      const chunk = higherChunks.get(maxStart)!;
      higherChunks.delete(maxStart);
      higherBufferedBytes -= chunk.byteLength;
      this.#bufferedChunkBytes = settledPrefixBytes + higherBufferedBytes;
      if (maxStart < earliestFailedItem) {
        heap.push({ start: maxStart, end: chunk.end, retriedFresh: false });
      }
      return true;
    };

    const tryReleasePendingFrontierGrant = () => {
      if (pendingFrontierGrant === null) return;
      if (fatalAbort !== null) {
        const p = pendingFrontierGrant;
        pendingFrontierGrant = null;
        p.resolve("abort");
        return;
      }
      const p = pendingFrontierGrant;
      if (p.range.start >= earliestFailedItem) {
        pendingFrontierGrant = null;
        p.resolve("discard");
        return;
      }
      if (settledPrefixBytes + p.resultBytes > this.#maxTotalOutputBytes) {
        pendingFrontierGrant = null;
        recordFailure(p.range.start, {
          kind: "output_budget_exceeded",
          message: "Output budget exceeded at frontier",
        });
        p.resolve("discard");
        return;
      }
      while (
        settledPrefixBytes + higherBufferedBytes + this.#inFlightGrantBytes +
            p.resultBytes > this.#maxTotalOutputBytes
      ) {
        if (!evictHighestHigherChunk(frontierItem)) break;
      }
      if (
        settledPrefixBytes + higherBufferedBytes + this.#inFlightGrantBytes +
            p.resultBytes <= this.#maxTotalOutputBytes
      ) {
        pendingFrontierGrant = null;
        this.#inFlightGrantBytes += p.resultBytes;
        this.#recordPeak();
        p.resolve("grant");
      }
    };

    const advanceFrontier = () => {
      for (;;) {
        // Resolve same-start_item failure precedence strictly when frontier reaches it!
        if (frontierItem === earliestFailedItem) {
          const cleanupBytes = cleanupResultBytesByStart.get(frontierItem);
          if (
            cleanupBytes !== undefined &&
            settledPrefixBytes + cleanupBytes > this.#maxTotalOutputBytes
          ) {
            recordFailure(frontierItem, {
              kind: "output_budget_exceeded",
              message: "Output budget exceeded (precedes cleanup failure)",
            });
          }
          break;
        }
        const chunk = higherChunks.get(frontierItem);
        if (chunk === undefined) break;
        higherChunks.delete(frontierItem);
        if (chunk.overBudgetHint) {
          if (
            settledPrefixBytes + chunk.byteLength > this.#maxTotalOutputBytes
          ) {
            recordFailure(frontierItem, {
              kind: "output_budget_exceeded",
              message: "Output budget exceeded at frontier",
            });
            break;
          }
          // Rare case: over-budget hint now fits; re-queue at frontier.
          heap.push({
            start: frontierItem,
            end: chunk.end,
            retriedFresh: false,
          });
          wakeWorkWaiters();
          break;
        }
        higherBufferedBytes -= chunk.byteLength;
        if (settledPrefixBytes + chunk.byteLength > this.#maxTotalOutputBytes) {
          this.#bufferedChunkBytes = settledPrefixBytes + higherBufferedBytes;
          recordFailure(frontierItem, {
            kind: "output_budget_exceeded",
            message: "Output budget exceeded advancing frontier",
          });
          break;
        }
        settledPrefixBytes += chunk.byteLength;
        this.#bufferedChunkBytes = settledPrefixBytes + higherBufferedBytes;
        this.#recordPeak();
        settledChunks.push(chunk.bytes!);
        frontierItem = chunk.end;
      }
      tryReleasePendingFrontierGrant();
      wakeWorkWaiters();
    };

    const getSlotWorker = (slotIdx: number): KernelSubprocess | null =>
      isDirectOrFallback
        ? this.#directSubprocess
        : this.#warmSubprocesses[slotIdx];
    const setSlotWorker = (slotIdx: number, w: KernelSubprocess | null) => {
      if (isDirectOrFallback) this.#directSubprocess = w;
      else this.#warmSubprocesses[slotIdx] = w;
    };

    const activeWorkersToRetire: Promise<void>[] = [];

    const runWorkerLoop = async (slotIdx: number) => {
      for (;;) {
        if (fatalAbort !== null || isClosed() || isTimedOut()) break;
        if (frontierItem >= itemCount || frontierItem >= earliestFailedItem) {
          break;
        }
        const range = heap.pop();
        if (range === undefined) {
          if (activeExecuting === 0 && pendingFrontierGrant === null) break;
          await new Promise<void>((resolve) => {
            workAvailableWaiters.push(resolve);
          });
          continue;
        }
        if (range.start >= earliestFailedItem) continue;

        activeExecuting++;
        try {
          const ref = { worker: getSlotWorker(slotIdx) };
          const snapRes = await this.#ensureSubprocessSnapshot(
            ref,
            slotIdx,
            batchSnapshot,
            batchDeadlineMs,
            batchEpoch,
          );
          setSlotWorker(slotIdx, ref.worker);
          if (!snapRes.ok) {
            if (
              snapRes.error.code === "pool_closed" ||
              snapRes.error.code === "timeout" ||
              snapRes.error.code === "transport_fault"
            ) {
              triggerFatalAbort(snapRes.error);
              break;
            }
            recordFailure(range.start, {
              kind: snapRes.error.code === "out_of_memory"
                ? "out_of_memory"
                : snapRes.error.code === "cleanup_trap"
                ? "cleanup_trap"
                : "run_trap",
              message: snapRes.error.message,
              resultBytes: 0,
            } as FailureKind);
            advanceFrontier();
            continue;
          }

          const w = snapRes.worker;
          batchSubprocesses.add(w);
          w.opDeadlineMs = batchDeadlineMs;

          const eligible = w.storeHasPriorHistory && !range.retriedFresh;
          const slice = inputSnapshot.subarray(
            range.start * inItemBytes,
            range.end * inItemBytes,
          );
          const runRes = await w.sendCommand(CMD_RUN, w.nextSeq++, slice, 0);

          if (isClosed()) {
            triggerFatalAbort(
              new KernelError("pool_closed", "KernelPool closed"),
            );
            activeWorkersToRetire.push(this.#retireSubprocess(w));
            break;
          }
          if (runRes.kind === "fenced" || isTimedOut()) {
            triggerFatalAbort(new KernelError("timeout", "Batch timed out"));
            activeWorkersToRetire.push(this.#retireSubprocess(w));
            break;
          }
          if (runRes.kind === "fault") {
            triggerFatalAbort(
              new KernelError(
                "transport_fault",
                `Worker fault: ${runRes.reason}`,
              ),
            );
            activeWorkersToRetire.push(this.#retireSubprocess(w));
            break;
          }
          if (runRes.kind === "arena_oom") {
            await this.#retireSubprocess(w);
            setSlotWorker(slotIdx, null);
            if (eligible) {
              range.retriedFresh = true;
              this.#freshRetries++;
              heap.push(range);
              wakeWorkWaiters();
            } else {
              recordFailure(range.start, {
                kind: "out_of_memory",
                message: "Kernel out of memory",
              });
              advanceFrontier();
            }
            continue;
          }
          if (runRes.kind === "run_trap") {
            if (!runRes.cleanupOk) {
              await this.#retireSubprocess(w);
              setSlotWorker(slotIdx, null);
            } else {
              w.storeHasPriorHistory = true;
              if (w.memoryBytes >= this.#retireMemoryThreshold) {
                await this.#retireSubprocess(w);
                setSlotWorker(slotIdx, null);
              }
            }
            recordFailure(range.start, {
              kind: "run_trap",
              message: "Kernel trapped",
            });
            advanceFrontier();
            continue;
          }

          // Unified [0xffffffff] overflow-sentinel transition (§5.1).
          if (
            runRes.kind === "overflow_ok" ||
            runRes.kind === "overflow_cleanup_fail"
          ) {
            const forcedCleanupFail = this.#hooks?.forceCleanupFailAtStart?.has(
              range.start,
            );
            const cleanupFailed = runRes.kind === "overflow_cleanup_fail" ||
              forcedCleanupFail;
            if (cleanupFailed) {
              await this.#retireSubprocess(w);
              setSlotWorker(slotIdx, null);
              if (range.end - range.start === 1) {
                recordFailure(range.start, {
                  kind: "single_item_output_overflow",
                  message: "Single item output overflow",
                });
              } else {
                recordFailure(range.start, {
                  kind: "cleanup_trap",
                  message: "Overflow cleanup trapped",
                  resultBytes: 0,
                });
              }
              advanceFrontier();
              continue;
            }
            w.storeHasPriorHistory = true;
            w.memoryBytes = runRes.memoryBytes;
            if (w.memoryBytes >= this.#retireMemoryThreshold) {
              await this.#retireSubprocess(w);
              setSlotWorker(slotIdx, null);
            }
            if (range.end - range.start === 1) {
              recordFailure(range.start, {
                kind: "single_item_output_overflow",
                message: "Single item output overflow",
              });
              advanceFrontier();
            } else {
              const mid = range.start + ((range.end - range.start) >> 1);
              heap.push({ start: mid, end: range.end, retriedFresh: false });
              heap.push({ start: range.start, end: mid, retriedFresh: false });
              wakeWorkWaiters();
            }
            continue;
          }

          if (runRes.kind !== "ready") {
            triggerFatalAbort(
              new KernelError(
                "transport_fault",
                `Unexpected run response: ${runRes.kind}`,
              ),
            );
            activeWorkersToRetire.push(this.#retireSubprocess(w));
            break;
          }

          const resultBytes = runRes.resultBytes;
          if (resultBytes % 4 !== 0) {
            triggerFatalAbort(
              new KernelError(
                "transport_fault",
                "Unaligned variable output length",
              ),
            );
            activeWorkersToRetire.push(this.#retireSubprocess(w));
            break;
          }

          if (this.#hooks?.onAfterReady) {
            await this.#hooks.onAfterReady({
              start: range.start,
              end: range.end,
              resultBytes,
              workerIndex: slotIdx,
            });
          }
          if (isClosed()) {
            triggerFatalAbort(
              new KernelError("pool_closed", "KernelPool closed"),
            );
            activeWorkersToRetire.push(this.#retireSubprocess(w));
            break;
          }
          if (isTimedOut() || fatalAbort !== null) {
            if (isTimedOut()) {
              triggerFatalAbort(new KernelError("timeout", "Batch timed out"));
            }
            activeWorkersToRetire.push(this.#retireSubprocess(w));
            break;
          }

          // Coordinator admission for variable-output READY chunk.
          let decision: "grant" | "discard" | "abort" = "discard";
          let requeueOnDiscard = false;
          let overBudgetHintOnDiscard = false;
          let frontierBudgetExceeded = false;

          if (range.start >= earliestFailedItem) {
            decision = "discard";
          } else if (range.start === frontierItem) {
            if (settledPrefixBytes + resultBytes > this.#maxTotalOutputBytes) {
              frontierBudgetExceeded = true;
              decision = "discard";
            } else {
              while (
                settledPrefixBytes + higherBufferedBytes +
                    this.#inFlightGrantBytes + resultBytes >
                  this.#maxTotalOutputBytes
              ) {
                if (!evictHighestHigherChunk(frontierItem)) break;
              }
              if (
                settledPrefixBytes + higherBufferedBytes +
                    this.#inFlightGrantBytes + resultBytes <=
                  this.#maxTotalOutputBytes
              ) {
                this.#inFlightGrantBytes += resultBytes;
                this.#recordPeak();
                decision = "grant";
              } else {
                // PendingFrontierGrant drain: park frontier holding Wasm packet (0 JS bytes)
                // and freeze all new higher copy_grants!
                decision = await new Promise<"grant" | "discard" | "abort">(
                  (resolve) => {
                    pendingFrontierGrant = { range, resultBytes, resolve };
                    tryReleasePendingFrontierGrant();
                  },
                );
              }
            }
          } else {
            // Speculative higher range (range.start > frontierItem)
            if (pendingFrontierGrant !== null) {
              requeueOnDiscard = true;
              decision = "discard";
            } else if (
              settledPrefixBytes + resultBytes > this.#maxTotalOutputBytes
            ) {
              overBudgetHintOnDiscard = true;
              decision = "discard";
            } else {
              while (
                settledPrefixBytes + higherBufferedBytes +
                    this.#inFlightGrantBytes + resultBytes >
                  this.#maxTotalOutputBytes
              ) {
                if (!evictHighestHigherChunk(range.start)) break;
              }
              if (
                settledPrefixBytes + higherBufferedBytes +
                    this.#inFlightGrantBytes + resultBytes <=
                  this.#maxTotalOutputBytes
              ) {
                this.#inFlightGrantBytes += resultBytes;
                this.#recordPeak();
                decision = "grant";
              } else {
                requeueOnDiscard = true;
                decision = "discard";
              }
            }
          }

          if (decision === "abort" || fatalAbort !== null) {
            activeWorkersToRetire.push(this.#retireSubprocess(w));
            break;
          }

          if (decision === "discard") {
            const discRes = await w.sendCommand(
              CMD_DISCARD,
              w.nextSeq++,
              null,
              0,
            );
            if (isClosed()) {
              triggerFatalAbort(
                new KernelError("pool_closed", "KernelPool closed"),
              );
              activeWorkersToRetire.push(this.#retireSubprocess(w));
              break;
            }
            if (discRes.kind === "fenced" || isTimedOut()) {
              triggerFatalAbort(new KernelError("timeout", "Batch timed out"));
              activeWorkersToRetire.push(this.#retireSubprocess(w));
              break;
            }
            if (discRes.kind === "fault") {
              triggerFatalAbort(
                new KernelError(
                  "transport_fault",
                  `Discard fault: ${discRes.reason}`,
                ),
              );
              activeWorkersToRetire.push(this.#retireSubprocess(w));
              break;
            }
            const forcedCleanupFail = this.#hooks?.forceCleanupFailAtStart?.has(
              range.start,
            );
            if (discRes.kind === "cleanup_fail" || forcedCleanupFail) {
              await this.#retireSubprocess(w);
              setSlotWorker(slotIdx, null);
              if (frontierBudgetExceeded) {
                recordFailure(range.start, {
                  kind: "output_budget_exceeded",
                  message: "Output budget exceeded at frontier",
                });
              } else {
                recordFailure(range.start, {
                  kind: "cleanup_trap",
                  message: "Cleanup trapped during discard",
                  resultBytes,
                });
              }
              advanceFrontier();
              continue;
            }
            w.storeHasPriorHistory = true;
            w.memoryBytes = discRes.kind === "discard_ok"
              ? discRes.memoryBytes
              : w.memoryBytes;
            if (w.memoryBytes >= this.#retireMemoryThreshold) {
              await this.#retireSubprocess(w);
              setSlotWorker(slotIdx, null);
            }
            if (frontierBudgetExceeded) {
              recordFailure(range.start, {
                kind: "output_budget_exceeded",
                message: "Output budget exceeded at frontier",
              });
              advanceFrontier();
            } else if (
              overBudgetHintOnDiscard && range.start < earliestFailedItem
            ) {
              higherChunks.set(range.start, {
                end: range.end,
                bytes: null,
                byteLength: resultBytes,
                overBudgetHint: true,
              });
              advanceFrontier();
            } else if (requeueOnDiscard && range.start < earliestFailedItem) {
              heap.push({
                start: range.start,
                end: range.end,
                retriedFresh: false,
              });
              wakeWorkWaiters();
            }
            continue;
          }

          // decision === "grant": cooperative post-READY copy_grant!
          const grantPromise = w.sendCommand(
            CMD_COPY_GRANT,
            w.nextSeq++,
            null,
            resultBytes,
            resultBytes > 0
              ? { kind: "variable", expectedBytes: resultBytes }
              : null,
          );
          if (this.#hooks?.onAfterVariableGrantIssued) {
            await this.#hooks.onAfterVariableGrantIssued({
              start: range.start,
              end: range.end,
              resultBytes,
              workerIndex: slotIdx,
            });
          }
          const grantRes = await grantPromise;

          // Release inFlightGrantBytes ONLY AFTER reply arrives (or on fatal abort AFTER retire!).
          if (isClosed()) {
            triggerFatalAbort(
              new KernelError("pool_closed", "KernelPool closed"),
            );
            activeWorkersToRetire.push(
              this.#retireSubprocess(w).finally(() => {
                this.#inFlightGrantBytes = Math.max(
                  0,
                  this.#inFlightGrantBytes - resultBytes,
                );
              }),
            );
            break;
          }
          if (grantRes.kind === "fenced" || isTimedOut()) {
            triggerFatalAbort(new KernelError("timeout", "Batch timed out"));
            activeWorkersToRetire.push(
              this.#retireSubprocess(w).finally(() => {
                this.#inFlightGrantBytes = Math.max(
                  0,
                  this.#inFlightGrantBytes - resultBytes,
                );
              }),
            );
            break;
          }
          if (grantRes.kind === "fault") {
            triggerFatalAbort(
              new KernelError(
                "transport_fault",
                `Variable grant fault: ${grantRes.reason}`,
              ),
            );
            activeWorkersToRetire.push(
              this.#retireSubprocess(w).finally(() => {
                this.#inFlightGrantBytes = Math.max(
                  0,
                  this.#inFlightGrantBytes - resultBytes,
                );
              }),
            );
            break;
          }

          // Cooperative settlement: worker has finished copy & cleanup!
          this.#inFlightGrantBytes = Math.max(
            0,
            this.#inFlightGrantBytes - resultBytes,
          );

          const forcedCleanupFail = this.#hooks?.forceCleanupFailAtStart?.has(
            range.start,
          );
          if (grantRes.kind === "cleanup_fail" || forcedCleanupFail) {
            await this.#retireSubprocess(w);
            setSlotWorker(slotIdx, null);
            recordFailure(range.start, {
              kind: "cleanup_trap",
              message: "Cleanup trapped after variable copy",
              resultBytes,
            });
            advanceFrontier();
            continue;
          }

          if (grantRes.kind !== "commit_ok") {
            triggerFatalAbort(
              new KernelError(
                "transport_fault",
                `Unexpected grant outcome: ${grantRes.kind}`,
              ),
            );
            activeWorkersToRetire.push(this.#retireSubprocess(w));
            break;
          }

          w.storeHasPriorHistory = true;
          w.memoryBytes = grantRes.memoryBytes;
          if (w.memoryBytes >= this.#retireMemoryThreshold) {
            await this.#retireSubprocess(w);
            setSlotWorker(slotIdx, null);
          }

          // If frontier is waiting in PendingFrontierGrant OR range >= earliestFailedItem:
          // drop payload immediately and re-queue (if < earliestFailedItem) to unblock frontier!
          if (range.start >= earliestFailedItem) {
            tryReleasePendingFrontierGrant();
            continue;
          }
          if (
            pendingFrontierGrant !== null &&
            range.start > frontierItem
          ) {
            heap.push({
              start: range.start,
              end: range.end,
              retriedFresh: false,
            });
            tryReleasePendingFrontierGrant();
            wakeWorkWaiters();
            continue;
          }

          const words = new Uint32Array(
            grantRes.returnedBuf ?? new ArrayBuffer(0),
          );
          higherChunks.set(range.start, {
            end: range.end,
            bytes: words,
            byteLength: resultBytes,
            overBudgetHint: false,
          });
          higherBufferedBytes += resultBytes;
          this.#bufferedChunkBytes = settledPrefixBytes + higherBufferedBytes;
          this.#recordPeak();
          advanceFrontier();
        } finally {
          activeExecuting--;
          wakeWorkWaiters();
        }
      }
    };

    await Promise.all(
      Array.from({ length: workerCount }, (_, idx) => runWorkerLoop(idx)),
    );
    for (const w of batchSubprocesses) {
      if (w.terminal === null) w.opDeadlineMs = null;
    }

    if (fatalAbort !== null || isClosed() || isTimedOut()) {
      for (const w of batchSubprocesses) {
        if (w.terminal !== null || w.fenced) {
          activeWorkersToRetire.push(this.#retireSubprocess(w));
        }
      }
      await Promise.all(activeWorkersToRetire);
      higherChunks.clear();
      settledChunks.length = 0;
      this.#bufferedChunkBytes = 0;
      this.#inFlightGrantBytes = 0;
      if (isClosed()) {
        throw new KernelError("pool_closed", "KernelPool closed during batch");
      }
      if (isTimedOut()) {
        throw new KernelError("timeout", "Batch timed out");
      }
      throw fatalAbort!;
    }

    await Promise.all(activeWorkersToRetire);
    advanceFrontier();

    if (earliestFailedItem < Number.POSITIVE_INFINITY) {
      higherChunks.clear();
      settledChunks.length = 0;
      this.#bufferedChunkBytes = 0;
      const err = failuresByStart.get(earliestFailedItem)!;
      throw toKernelError(earliestFailedItem, err);
    }

    if (mode === "variable_chunks") return settledChunks;
    if (settledChunks.length === 1) return settledChunks[0];
    return await this.#concatenateVariableChunks(
      settledChunks,
      settledPrefixBytes,
      batchEpoch,
      batchDeadlineMs,
    );
  }

  /**
   * Idempotent close (§5.1): synchronously transitions `#state = "closing"`,
   * bumps `#poolEpoch++`, fences any active op so it rejects with `PoolClosed`,
   * awaits teardown of all active & idle subprocesses, releases all charges to 0,
   * and sets `#state = "closed"`.
   */
  close(): Promise<void> {
    if (this.#closePromise !== null) return this.#closePromise;
    this.#state = "closing";
    this.#poolEpoch++;
    const activeOp = this.#activeOp;
    if (activeOp !== null) {
      activeOp.cancelForClose();
    }
    this.#closePromise = (async () => {
      if (activeOp !== null) {
        await activeOp.done;
      }
      const allLive = [...this.#liveSubprocesses];
      await Promise.all([
        ...allLive.map((w) => this.#retireSubprocess(w)),
        ...[...this.#retiringPromises],
      ]);
      this.#warmSubprocesses.fill(null);
      this.#directSubprocess = null;
      this.#inlineGuest = null;
      this.#currentCtx = null;
      this.#inputSnapshotBytes = 0;
      this.#contextSnapshotBytes = 0;
      this.#fixedOutputBytes = 0;
      this.#bufferedChunkBytes = 0;
      this.#inFlightGrantBytes = 0;
      this.#concatScratchBytes = 0;
      this.#state = "closed";
    })();
    return this.#closePromise;
  }
}
