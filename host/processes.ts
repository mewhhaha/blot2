// Deterministic Standalone `Processes` Scheduler for Deno (§5.2).
//
// Guarantees:
// - Pre-instantiation private-copy `MemoryShape` & `CompiledModuleReceipt` admission
// - Explicit rejection of `rustWasmtimeFuel` in JS/Deno
// - Sandboxed `--no-prompt` / zero-`--allow-run` `Deno.Command` subprocesses for
//   all deadline-bearing policies (and parallel waves with deadlines)
// - Ticketless budgeted-wave initialization (`INIT_OK`/`INIT_FAIL`) with
//   pre-spawn `initDeadlineMs`, latched `initOnTimeCaptured`, and immediate `admit()`
//   private `copyPrivateBytes(config)` charge
// - Exact ABI `reply_schema.wire_tag` 16-byte header framing:
//   - `wire_tag == 0` (`Unit`): header-only `COMMIT_OK_UNIT` (0 B)
//   - `wire_tag in {1, 2, 3}` (`U32`/`Bool`/`F32` incl. 1-word records): header-only
//     `COMMIT_OK_SCALAR` (4 B logical, validating `Bool <= 1` and `4 <= maxReplyBytes`)
//   - `wire_tag in {5, 6}`: `DATA_FRAME` + BYOB read + trailing `COMMIT_OK`/`CLEANUP_FAIL`
// - Strict parser-vs-coordinator split, closed registration gate & kill-first
//   5-step `retireSubprocess` across ALL 5 retirement paths
// - Continuous mailbox-slot (`pending + inFlight + events`), resident-memory,
//   and `mailboxBytes` accounting
// - Single-owner `InFlightTurn`, explicit `retirementState`, unified `child.settlementDone`,
//   `#runningGeneration`, and single exclusive drain owner `#exclusiveTransition`
// - Serial-equivalent multi-wave `advanceAllParallel(budget)`

import {
  type CompiledModuleReceipt,
  copyPrivateBytes,
  DEFAULT_TRANSPORT_BUDGET,
  type ProcessManifest,
  resolveValidatedModule,
  type ValidatedModuleMeta,
  type WireSchema,
} from "./guest.ts";

const CMD_INIT = 1;
const CMD_STEP = 2;

const TAG_INIT_OK = 1;
const TAG_INIT_FAIL = 2;
const TAG_COMMIT_OK_UNIT = 3;
const TAG_COMMIT_OK_SCALAR = 4;
const TAG_DATA_FRAME = 5;
const TAG_COMMIT_OK = 6;
const TAG_CLEANUP_FAIL = 7;
const TAG_STEP_FAIL = 8;

const WIRE_UNIT = 0;
const WIRE_U32 = 1;
const WIRE_BOOL = 2;
const WIRE_F32 = 3;

const MAX_DEADLINE_MS = 2_147_483_647;
const SUBPROCESS_URL = new URL("./process_subprocess.ts", import.meta.url);
const f32View = new DataView(new ArrayBuffer(4));

function f32ToBits(v: number): number {
  f32View.setFloat32(0, Math.fround(v), true);
  return f32View.getUint32(0, true);
}

function bitsToF32(bits: number): number {
  f32View.setUint32(0, bits >>> 0, true);
  return f32View.getFloat32(0, true);
}

export type ProcessErrorCode =
  | "invalid_config"
  | "unknown_process"
  | "fuel_unsupported"
  | "memory_limit_unbounded"
  | "memory_limit_exceeded"
  | "invalid_argument"
  | "already_advancing"
  | "transition_in_progress"
  | "scheduler_aborted"
  | "overrun";

export class ProcessError extends Error {
  constructor(
    readonly code: ProcessErrorCode,
    message: string,
    options?: ErrorOptions,
  ) {
    super(message, options);
    this.name = "ProcessError";
  }
}

export class ProcessOverrunError extends ProcessError {
  constructor(
    message: string,
    readonly drainedEvents: ReadonlyMap<ProcessHandle, readonly ProcessEvent[]>,
  ) {
    super("overrun", message);
    this.name = "ProcessOverrunError";
  }
}

export interface ProcessHandle {
  readonly schedulerId: number;
  readonly endpoint: number;
  readonly epoch: number;
}

export type ProcessStatus = "starting" | "ready" | "failed" | "closed";

export type ProcessValue =
  | null
  | number
  | boolean
  | Uint32Array
  | Float32Array;

export type ProcessEvent =
  | {
    readonly ticket: number;
    readonly status: "done";
    readonly value: ProcessValue;
    readonly logicalReplyBytes: number;
  }
  | { readonly ticket: number; readonly status: "cancelled" | "failed" };

export interface ProcessPolicy {
  readonly name: string;
  readonly initWork: number;
  readonly stepWork: number;
  readonly rustWasmtimeFuel?: unknown;
  readonly deadlineMs?: number;
  readonly memory?: number;
  readonly mailbox: number;
  readonly mailboxBytes: number;
  readonly maxReplyBytes: number;
  readonly slots?: number;
}

export interface ProcessTestHooks {
  /** Override subprocess worker URL for fault-injection tests. */
  subprocessUrl?: URL;
  /** Force synchronous `Deno.Command.spawn()` failure for a given process name. */
  failSpawnForName?: Set<string>;
  /** Capture armed init/step timer callbacks so tests can fire them early/late. */
  onTimerArmed?: (info: {
    kind: "init" | "step";
    endpoint: number;
    deadlineMs: number;
    fire: () => void;
  }) => void;
  /** Pause hook right before retirement transport teardown completes. */
  onBeforeRetireFinish?: (endpoint: number) => Promise<void> | void;
  /** Pause hook right after a child latches its on-time wave result, before sibling finishes. */
  onAfterChildWaveResult?: (info: {
    endpoint: number;
    kind: "init" | "step";
  }) => Promise<void> | void;
  /** Pause hook inside parser after reading partial bytes (or before reading trailing header). */
  onPartialByobRead?: (endpoint: number) => Promise<void> | void;
  /** Override per-turn maxReplyBytes defensively on framed reply validation (test witness). */
  overrideValidatorMaxReplyBytes?: number;
  /** Observe subprocess retirement completion. */
  onSubprocessRetired?: (info: {
    endpoint: number;
    exitCode: number | null;
    signal: Deno.Signal | null;
    terminalKind: string;
  }) => void;
  /** Observe when advance/advanceAllParallel finally executes. */
  onBeforeAdvanceFinally?: (generation: number) => Promise<void> | void;
  /** Force subprocess execution even when deadlineMs is unset. */
  forceSubprocess?: boolean;
}

export interface ProcessesOptions {
  readonly slots?: number;
  readonly _testHooks?: ProcessTestHooks;
}

interface EncodedValue {
  readonly bytes: Uint8Array<ArrayBuffer> | null; // non-null for array wire_tag in {5, 6}
  readonly inlineWord: number;
  readonly byteLength: number; // 0 for Unit/scalar, bytes.byteLength for array
}

interface PendingCommand {
  readonly ticket: number;
  readonly encoded: EncodedValue;
  readonly cmdBytes: number;
  readonly maxReplyBytes: number;
}

interface InFlightTurn {
  readonly generation: number;
  readonly ticket: number;
  readonly cmdBytes: number;
  readonly maxReplyBytes: number;
  completedReply: ProcessValue | undefined;
  completedReplyBytes: number;
  onTimeCaptured: boolean;
  settled: boolean;
  timer?: ReturnType<typeof setTimeout>;
}

type TransportOutcome =
  | { kind: "fenced" }
  | { kind: "fault"; reason: string }
  | { kind: "init_ok" }
  | { kind: "init_fail" }
  | { kind: "commit_ok_unit" }
  | { kind: "commit_ok_scalar"; word: number }
  | { kind: "commit_ok_data"; buffer: ArrayBuffer }
  | { kind: "cleanup_fail" }
  | { kind: "step_fail" };

type TerminalState = null | { kind: "fenced" } | {
  kind: "fault";
  reason: string;
};

interface PendingWaiter {
  readonly seq: number;
  readonly kind: "init" | "step";
  readonly replyWireTag: number;
  readonly replyFixedBytes: number | null;
  readonly maxReplyBytes: number;
  readonly deadlineMs: number | null;
  readonly resolve: (outcome: TransportOutcome) => void;
}

class ProcessSubprocess {
  readonly endpoint: number;
  readonly child: Deno.ChildProcess;
  readonly stdinWriter: WritableStreamDefaultWriter<Uint8Array>;
  readonly stdoutReader: ReadableStreamBYOBReader;
  fenced = false;
  terminal: TerminalState = null;
  pendingWaiter: PendingWaiter | null = null;
  idleGateResolve: (() => void) | null = null;
  parserDone!: Promise<void>;
  retirePromise: Promise<void> | null = null;
  readonly #hooks?: ProcessTestHooks;

  constructor(
    endpoint: number,
    scriptUrl: URL,
    hooks?: ProcessTestHooks,
  ) {
    this.endpoint = endpoint;
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
    waiter: Omit<PendingWaiter, "resolve">,
  ): Promise<TransportOutcome> {
    if (this.terminal !== null) {
      return Promise.resolve(this.terminal);
    }
    return new Promise<TransportOutcome>((resolve) => {
      if (this.terminal !== null) {
        resolve(this.terminal);
        return;
      }
      this.pendingWaiter = { ...waiter, resolve };
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
    waiterSpec: Omit<PendingWaiter, "resolve">,
  ): Promise<TransportOutcome> {
    if (this.terminal !== null) return this.terminal;
    const waiterPromise = this.registerWaiter(waiterSpec);
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
      this.closeTransport({ kind: "fault", reason: "stdin_write_failed" });
    }
    return waiterPromise;
  }

  async #readExactByob(
    buf: ArrayBuffer,
    byteOffset: number,
    byteLength: number,
    notifyPartial = false,
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
      if (
        notifyPartial && filled > 0 && filled < byteLength &&
        this.#hooks?.onPartialByobRead
      ) {
        await this.#hooks.onPartialByobRead(this.endpoint);
      }
      if (this.fenced) return { ok: false, reason: "fenced" };
      if (res.done && filled < byteLength) {
        return { ok: false, reason: "eof" };
      }
    }
    return { ok: true, buf: curBuf };
  }

  /** Strict parser-vs-coordinator split: NEVER calls or awaits retire()! */
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
            this.fenced
              ? { kind: "fenced" }
              : { kind: "fault", reason: hdrRes.reason },
          );
          break;
        }
        headerBuf = hdrRes.buf;
        if (this.fenced) {
          this.closeTransport({ kind: "fenced" });
          break;
        }

        const waiter = this.pendingWaiter;
        if (waiter === null) {
          this.closeTransport({ kind: "fault", reason: "unsolicited_frame" });
          break;
        }

        const dv = new DataView(headerBuf);
        const tag = dv.getUint32(0, true);
        const seq = dv.getUint32(4, true);
        const payloadBytes = dv.getUint32(8, true);
        const inlineWord = dv.getUint32(12, true);

        if (seq !== waiter.seq) {
          this.closeTransport({ kind: "fault", reason: "seq_mismatch" });
          break;
        }

        if (waiter.kind === "init") {
          if (payloadBytes !== 0) {
            this.closeTransport({
              kind: "fault",
              reason: "malformed_init_frame",
            });
            break;
          }
          if (tag === TAG_INIT_OK) {
            this.pendingWaiter = null;
            waiter.resolve({ kind: "init_ok" });
            continue;
          }
          if (tag === TAG_INIT_FAIL) {
            this.pendingWaiter = null;
            waiter.resolve({ kind: "init_fail" });
            break;
          }
          this.closeTransport({ kind: "fault", reason: "unexpected_init_tag" });
          break;
        }

        // Step turn reply validation strictly by ABI reply_schema.wire_tag (§5.2):
        if (tag === TAG_STEP_FAIL) {
          if (payloadBytes !== 0) {
            this.closeTransport({
              kind: "fault",
              reason: "malformed_step_fail",
            });
            break;
          }
          this.pendingWaiter = null;
          waiter.resolve({ kind: "step_fail" });
          break;
        }
        if (tag === TAG_CLEANUP_FAIL) {
          if (payloadBytes !== 0) {
            this.closeTransport({
              kind: "fault",
              reason: "malformed_cleanup_fail",
            });
            break;
          }
          this.pendingWaiter = null;
          waiter.resolve({ kind: "cleanup_fail" });
          break;
        }

        if (waiter.replyWireTag === WIRE_UNIT) {
          if (tag !== TAG_COMMIT_OK_UNIT || payloadBytes !== 0) {
            this.closeTransport({ kind: "fault", reason: "schema_or_width" });
            break;
          }
          this.pendingWaiter = null;
          waiter.resolve({ kind: "commit_ok_unit" });
          continue;
        }

        if (
          waiter.replyWireTag === WIRE_U32 ||
          waiter.replyWireTag === WIRE_BOOL ||
          waiter.replyWireTag === WIRE_F32
        ) {
          const effMaxReply = this.#hooks?.overrideValidatorMaxReplyBytes ??
            waiter.maxReplyBytes;
          if (
            tag !== TAG_COMMIT_OK_SCALAR ||
            payloadBytes !== 0 ||
            effMaxReply < 4 ||
            (waiter.replyWireTag === WIRE_BOOL && inlineWord > 1)
          ) {
            this.closeTransport({ kind: "fault", reason: "schema_or_width" });
            break;
          }
          this.pendingWaiter = null;
          waiter.resolve({ kind: "commit_ok_scalar", word: inlineWord });
          continue;
        }

        // wire_tag in {5, 6}: DATA_FRAME + BYOB read (if > 0) + trailing COMMIT_OK / CLEANUP_FAIL!
        if (tag !== TAG_DATA_FRAME) {
          this.closeTransport({ kind: "fault", reason: "schema_or_width" });
          break;
        }
        const effMaxReply = this.#hooks?.overrideValidatorMaxReplyBytes ??
          waiter.maxReplyBytes;
        if (
          payloadBytes % 4 !== 0 ||
          payloadBytes > effMaxReply ||
          (waiter.replyFixedBytes !== null &&
            payloadBytes !== waiter.replyFixedBytes)
        ) {
          this.closeTransport({ kind: "fault", reason: "schema_or_width" });
          break;
        }

        let dataBuf: ArrayBuffer = new ArrayBuffer(payloadBytes);
        if (payloadBytes > 0) {
          partialTarget = dataBuf;
          const bodyRes = await this.#readExactByob(
            dataBuf,
            0,
            payloadBytes,
            true,
          );
          if (!bodyRes.ok) {
            partialTarget = null;
            this.closeTransport(
              this.fenced
                ? { kind: "fenced" }
                : { kind: "fault", reason: bodyRes.reason },
            );
            break;
          }
          dataBuf = bodyRes.buf;
          partialTarget = dataBuf;
        }

        // Read mandatory trailing 16-byte COMMIT_OK / CLEANUP_FAIL header!
        const trailRes = await this.#readExactByob(headerBuf, 0, 16);
        if (!trailRes.ok) {
          partialTarget = null;
          this.closeTransport(
            this.fenced
              ? { kind: "fenced" }
              : { kind: "fault", reason: trailRes.reason },
          );
          break;
        }
        headerBuf = trailRes.buf;
        if (this.fenced) {
          partialTarget = null;
          this.closeTransport({ kind: "fenced" });
          break;
        }
        const tdv = new DataView(headerBuf);
        const tTag = tdv.getUint32(0, true);
        const tSeq = tdv.getUint32(4, true);
        const tPayload = tdv.getUint32(8, true);
        if (tSeq !== waiter.seq || tPayload !== 0) {
          partialTarget = null;
          this.closeTransport({
            kind: "fault",
            reason: "malformed_trailing_header",
          });
          break;
        }
        if (tTag === TAG_COMMIT_OK) {
          const finished = dataBuf;
          partialTarget = null;
          this.pendingWaiter = null;
          waiter.resolve({ kind: "commit_ok_data", buffer: finished });
          continue;
        }
        if (tTag === TAG_CLEANUP_FAIL) {
          partialTarget = null;
          this.pendingWaiter = null;
          waiter.resolve({ kind: "cleanup_fail" });
          break;
        }
        partialTarget = null;
        this.closeTransport({
          kind: "fault",
          reason: "unexpected_trailing_tag",
        });
        break;
      }
    } catch {
      this.closeTransport(
        this.fenced
          ? { kind: "fenced" }
          : { kind: "fault", reason: "parser_exception" },
      );
    } finally {
      partialTarget = null;
      this.closeTransport(
        this.fenced
          ? { kind: "fenced" }
          : { kind: "fault", reason: "parser_exit" },
      );
    }
  }

  /**
   * Unified kill-first 5-step idempotent subprocess retirement (§5.2):
   * 1. Synchronously fence & closeTransport (first cause wins; wakes idle gate).
   * 2. SIGKILL (ignoring NotFound / AlreadyTerminated).
   * 3. writer.abort().
   * 4. Let native BYOB read finish natively & await parserDone (clears partialTarget = null).
   * 5. ONLY AFTER parserDone: reader.cancel(), releaseLock(), await child.status.
   */
  retire(): Promise<void> {
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
      this.#hooks?.onSubprocessRetired?.({
        endpoint: this.endpoint,
        exitCode: status?.code ?? null,
        signal: status?.signal ?? null,
        terminalKind: this.terminal?.kind ?? "none",
      });
    })();
    return this.retirePromise;
  }
}

class InlineProcessGuest {
  readonly memory: WebAssembly.Memory | null;
  readonly allocate: ((bytes: number) => number) | null;
  readonly reset: ((arg: number) => void) | null;
  readonly finishInvocation: (() => void) | null;
  readonly initFn: (arg: number) => void;
  readonly stepFn: (arg: number) => number;
  readonly manifest: ProcessManifest;
  readonly maxReplyBytes: number;

  constructor(
    meta: ValidatedModuleMeta,
    manifest: ProcessManifest,
    maxReplyBytes: number,
  ) {
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
    const mem = exports["squid:memory"];
    const alloc = exports["squid:allocate"];
    const reset = exports["squid:reset"];
    const finish = exports["squid:finish_invocation"];
    const hasArena = mem instanceof WebAssembly.Memory &&
      typeof alloc === "function" && typeof reset === "function";
    this.memory = hasArena ? mem : null;
    this.allocate = hasArena ? (alloc as (bytes: number) => number) : null;
    this.reset = hasArena ? (reset as (arg: number) => void) : null;
    this.finishInvocation = typeof finish === "function"
      ? (finish as () => void)
      : null;
    this.initFn = exports[manifest.initExport] as (arg: number) => void;
    this.stepFn = exports[manifest.stepExport] as (arg: number) => number;
    this.manifest = manifest;
    this.maxReplyBytes = maxReplyBytes;
  }

  #writePacket(bytes: Uint8Array): number {
    if (this.memory === null || this.allocate === null || this.reset === null) {
      throw new Error("missing guest arena");
    }
    this.reset(0);
    const words = bytes.byteLength >>> 2;
    const ptr = this.allocate((words + 1) * 4) >>> 0;
    const buf = this.memory.buffer;
    if (
      ptr < 4 || (ptr & 3) !== 0 || ptr + 4 + bytes.byteLength > buf.byteLength
    ) {
      throw new Error("packet allocation out of bounds");
    }
    new DataView(buf).setUint32(ptr, words, true);
    if (bytes.byteLength > 0) {
      new Uint8Array(buf, ptr + 4, bytes.byteLength).set(bytes);
    }
    return ptr;
  }

  #cleanup(): void {
    this.finishInvocation?.();
    this.reset?.(0);
  }

  init(encoded: EncodedValue): void {
    const tag = this.manifest.configSchema.wireTagCode;
    let arg: number;
    if (tag === 5 || tag === 6) {
      arg = this.#writePacket(encoded.bytes!);
    } else {
      this.reset?.(0);
      arg = tag === WIRE_UNIT
        ? 0
        : tag === WIRE_BOOL
        ? (encoded.inlineWord !== 0 ? 1 : 0)
        : tag === WIRE_F32
        ? bitsToF32(encoded.inlineWord)
        : encoded.inlineWord >>> 0;
    }
    this.initFn(arg);
    this.#cleanup();
  }

  step(
    encoded: EncodedValue,
  ): { value: ProcessValue; logicalReplyBytes: number } {
    const cmdTag = this.manifest.cmdSchema.wireTagCode;
    let arg: number;
    if (cmdTag === 5 || cmdTag === 6) {
      arg = this.#writePacket(encoded.bytes!);
    } else {
      this.reset?.(0);
      arg = cmdTag === WIRE_UNIT
        ? 0
        : cmdTag === WIRE_BOOL
        ? (encoded.inlineWord !== 0 ? 1 : 0)
        : cmdTag === WIRE_F32
        ? bitsToF32(encoded.inlineWord)
        : encoded.inlineWord >>> 0;
    }
    const raw = this.stepFn(arg);
    const replySchema = this.manifest.replySchema;
    const replyTag = replySchema.wireTagCode;

    if (replyTag === WIRE_UNIT) {
      this.#cleanup();
      return { value: null, logicalReplyBytes: 0 };
    }
    if (
      replyTag === WIRE_U32 || replyTag === WIRE_BOOL || replyTag === WIRE_F32
    ) {
      if (this.maxReplyBytes < 4) {
        throw new Error("scalar exceeds maxReplyBytes");
      }
      let val: ProcessValue;
      if (replyTag === WIRE_U32) {
        val = raw >>> 0;
      } else if (replyTag === WIRE_BOOL) {
        if (raw !== 0 && raw !== 1) throw new Error("non-canonical bool reply");
        val = raw === 1;
      } else {
        val = Math.fround(raw);
      }
      this.#cleanup();
      return { value: val, logicalReplyBytes: 4 };
    }

    if (this.memory === null) throw new Error("missing guest memory");
    const ptr = raw >>> 0;
    const buf = this.memory.buffer;
    if (ptr < 4 || (ptr & 3) !== 0 || ptr + 4 > buf.byteLength) {
      throw new Error("reply pointer out of bounds");
    }
    const lenWords = new DataView(buf).getUint32(ptr, true);
    const replyBytes = lenWords * 4;
    if (
      ptr + 4 + replyBytes > buf.byteLength ||
      replyBytes > this.maxReplyBytes ||
      (replySchema.kind === "FlatFixed" &&
        replyBytes !== replySchema.stride * 4)
    ) {
      throw new Error("reply exceeds bounds");
    }
    const copyBuf = new ArrayBuffer(replyBytes);
    if (replyBytes > 0) {
      new Uint8Array(copyBuf).set(new Uint8Array(buf, ptr + 4, replyBytes));
    }
    this.#cleanup();
    const value = replyTag === 6
      ? new Float32Array(copyBuf)
      : new Uint32Array(copyBuf);
    return { value, logicalReplyBytes: replyBytes };
  }
}

interface Child {
  readonly handle: ProcessHandle;
  readonly policy: ProcessPolicy;
  readonly manifest: ProcessManifest;
  status: ProcessStatus;
  retirementState: "live" | "retiring" | "retired";
  fenced: boolean;
  transport: ProcessSubprocess | null;
  inlineGuest: InlineProcessGuest | null;
  retireTransportPromise: Promise<void> | null;
  settlementDone: Promise<void> | null;
  memoryReserved: boolean;
  readonly memoryCharge: number;
  initConfig: EncodedValue | null;
  initConfigBytesCharged: number;
  initRunId: number;
  initOnTimeCaptured: boolean;
  initTimer?: ReturnType<typeof setTimeout>;
  inFlight: InFlightTurn | null;
  pending: Map<number, PendingCommand>;
  events: ProcessEvent[];
  mailboxBytesUsed: number;
}

function encodeValueForSchema(
  value: ProcessValue,
  schema: WireSchema,
  transportBudget: number,
  label: string,
): EncodedValue {
  const tag = schema.wireTagCode;
  if (tag === WIRE_UNIT) {
    if (value !== null) {
      throw new ProcessError(
        "invalid_argument",
        `${label} must be null (Unit)`,
      );
    }
    return { bytes: null, inlineWord: 0, byteLength: 0 };
  }
  if (tag === WIRE_U32) {
    if (
      typeof value !== "number" || !Number.isInteger(value) || value < 0 ||
      value > 0xffff_ffff
    ) {
      throw new ProcessError("invalid_argument", `${label} must be a U32`);
    }
    return { bytes: null, inlineWord: value >>> 0, byteLength: 0 };
  }
  if (tag === WIRE_BOOL) {
    if (typeof value !== "boolean") {
      throw new ProcessError("invalid_argument", `${label} must be a Bool`);
    }
    return { bytes: null, inlineWord: value ? 1 : 0, byteLength: 0 };
  }
  if (tag === WIRE_F32) {
    if (typeof value !== "number") {
      throw new ProcessError("invalid_argument", `${label} must be an F32`);
    }
    return { bytes: null, inlineWord: f32ToBits(value), byteLength: 0 };
  }

  // wire_tag in {5=ArrayU32, 6=ArrayF32}
  if (!ArrayBuffer.isView(value)) {
    throw new ProcessError(
      "invalid_argument",
      `${label} must be a TypedArray/ArrayBufferView`,
    );
  }
  const bytes = copyPrivateBytes(value);
  if (bytes.byteLength % 4 !== 0) {
    throw new ProcessError(
      "invalid_argument",
      `${label} byte length must be a multiple of 4`,
    );
  }
  if (bytes.byteLength > transportBudget - 4) {
    throw new ProcessError(
      "invalid_argument",
      `${label} (${bytes.byteLength} B) exceeds transport budget (${
        transportBudget - 4
      } B)`,
    );
  }
  if (schema.kind === "FlatFixed" && bytes.byteLength !== schema.stride * 4) {
    throw new ProcessError(
      "invalid_argument",
      `${label} requires exact ${schema.stride * 4} bytes`,
    );
  }
  return { bytes, inlineWord: 0, byteLength: bytes.byteLength };
}

function decodeProcessReply(
  schema: WireSchema,
  outcome:
    | { kind: "commit_ok_unit" }
    | { kind: "commit_ok_scalar"; word: number }
    | { kind: "commit_ok_data"; buffer: ArrayBuffer },
): { value: ProcessValue; logicalReplyBytes: number } {
  if (outcome.kind === "commit_ok_unit") {
    return { value: null, logicalReplyBytes: 0 };
  }
  if (outcome.kind === "commit_ok_scalar") {
    const tag = schema.wireTagCode;
    if (tag === WIRE_U32) {
      return { value: outcome.word >>> 0, logicalReplyBytes: 4 };
    }
    if (tag === WIRE_BOOL) {
      return { value: outcome.word === 1, logicalReplyBytes: 4 };
    }
    return { value: bitsToF32(outcome.word), logicalReplyBytes: 4 };
  }
  const value = schema.wireTagCode === 6
    ? new Float32Array(outcome.buffer)
    : new Uint32Array(outcome.buffer);
  return { value, logicalReplyBytes: outcome.buffer.byteLength };
}

function encodeProcessInitPayload(
  wasmBytes: Uint8Array,
  manifest: ProcessManifest,
  maxReplyBytes: number,
  configBytes: Uint8Array | null,
): Uint8Array {
  const metaJson = new TextEncoder().encode(JSON.stringify({
    initExport: manifest.initExport,
    stepExport: manifest.stepExport,
    configWireTag: manifest.configSchema.wireTagCode,
    cmdWireTag: manifest.cmdSchema.wireTagCode,
    replyWireTag: manifest.replySchema.wireTagCode,
    replyFixedBytes: manifest.replySchema.kind === "FlatFixed" &&
        (manifest.replySchema.wireTagCode === 5 ||
          manifest.replySchema.wireTagCode === 6)
      ? manifest.replySchema.stride * 4
      : null,
    maxReplyBytes,
  }));
  const cfgLen = configBytes === null ? 0 : configBytes.byteLength;
  const out = new Uint8Array(
    12 + wasmBytes.byteLength + metaJson.byteLength + cfgLen,
  );
  const dv = new DataView(out.buffer);
  dv.setUint32(0, wasmBytes.byteLength, true);
  dv.setUint32(4, metaJson.byteLength, true);
  dv.setUint32(8, cfgLen, true);
  out.set(wasmBytes, 12);
  out.set(metaJson, 12 + wasmBytes.byteLength);
  if (configBytes !== null && cfgLen > 0) {
    out.set(configBytes, 12 + wasmBytes.byteLength + metaJson.byteLength);
  }
  return out;
}

let nextSchedulerId = 1;

export class Processes {
  readonly #schedulerId: number;
  readonly #meta: ValidatedModuleMeta;
  readonly #transportBudget: number;
  readonly #policies = new Map<
    string,
    { policy: ProcessPolicy; manifest: ProcessManifest }
  >();
  readonly #slots: number;
  readonly #hooks?: ProcessTestHooks;

  readonly #children = new Map<number, Child>();
  readonly #order: number[] = [];
  #cursor = 0;
  #nextEndpoint = 1;
  #nextTicket = 1;
  #nextInitRunId = 1;
  #generation = 1;
  #runningGeneration: number | null = null;
  #exclusiveTransition: null | "restoring" | "aborting" = null;
  #aborted = false;

  // Accounting
  #residentMemoryBytes = 0;
  #mailboxBytesReserved = 0;
  #activeSubprocesses = 0;

  constructor(
    source: Uint8Array | CompiledModuleReceipt,
    policies: readonly ProcessPolicy[],
    options: ProcessesOptions = {},
  ) {
    this.#schedulerId = nextSchedulerId++;
    this.#meta = resolveValidatedModule(source);
    this.#transportBudget = this.#meta.abi.transportBudget ??
      DEFAULT_TRANSPORT_BUDGET;
    this.#hooks = options._testHooks;
    const slots = options.slots ?? 16;
    if (!Number.isSafeInteger(slots) || slots <= 0) {
      throw new ProcessError(
        "invalid_config",
        "slots must be a positive integer",
      );
    }
    this.#slots = slots;

    const manifests = new Map(
      (this.#meta.abi.processes ?? []).map((p) => [p.name, p]),
    );
    for (const policy of policies) {
      if (policy.rustWasmtimeFuel !== undefined) {
        throw new ProcessError(
          "fuel_unsupported",
          `Process ${policy.name}: rustWasmtimeFuel is unsupported in JS/Deno`,
        );
      }
      const manifest = manifests.get(policy.name);
      if (!manifest) {
        throw new ProcessError(
          "unknown_process",
          `Unknown #process ${policy.name}`,
        );
      }
      if (this.#policies.has(policy.name)) {
        throw new ProcessError(
          "invalid_config",
          `Duplicate process policy ${policy.name}`,
        );
      }
      if (
        !Number.isSafeInteger(policy.initWork) || policy.initWork <= 0 ||
        !Number.isSafeInteger(policy.stepWork) || policy.stepWork <= 0 ||
        !Number.isSafeInteger(policy.mailbox) || policy.mailbox <= 0 ||
        !Number.isSafeInteger(policy.mailboxBytes) || policy.mailboxBytes < 0 ||
        !Number.isSafeInteger(policy.maxReplyBytes) || policy.maxReplyBytes < 0
      ) {
        throw new ProcessError(
          "invalid_config",
          `Invalid numeric policy parameters for process ${policy.name}`,
        );
      }
      if (
        policy.slots !== undefined &&
        (!Number.isSafeInteger(policy.slots) || policy.slots <= 0)
      ) {
        throw new ProcessError(
          "invalid_config",
          `Invalid slots for process ${policy.name}`,
        );
      }
      if (policy.deadlineMs !== undefined) {
        const d = policy.deadlineMs;
        if (!Number.isFinite(d) || d < 1 || d > MAX_DEADLINE_MS) {
          throw new ProcessError(
            "invalid_config",
            `Process ${policy.name}: deadlineMs must be finite in 1..=${MAX_DEADLINE_MS}, got ${d}`,
          );
        }
      }
      if (policy.memory !== undefined) {
        if (!Number.isSafeInteger(policy.memory) || policy.memory <= 0) {
          throw new ProcessError(
            "invalid_config",
            `Process ${policy.name}: memory must be a positive integer`,
          );
        }
        if (this.#meta.memoryShape.hasMemory) {
          if (this.#meta.memoryShape.maximumPages === undefined) {
            throw new ProcessError(
              "memory_limit_unbounded",
              `Process ${policy.name}: unbounded Wasm linear memory rejected when policy.memory is set`,
            );
          }
          const declaredMaxBytes = this.#meta.memoryShape.maximumPages * 65_536;
          if (policy.memory < declaredMaxBytes) {
            throw new ProcessError(
              "memory_limit_exceeded",
              `Process ${policy.name}: policy.memory (${policy.memory}) < declared Wasm maximum (${declaredMaxBytes})`,
            );
          }
        }
      }

      // Reply width admission check (§5.2):
      const replySchema = manifest.replySchema;
      if (
        (replySchema.wireTagCode === WIRE_U32 ||
          replySchema.wireTagCode === WIRE_BOOL ||
          replySchema.wireTagCode === WIRE_F32) &&
        policy.maxReplyBytes < 4
      ) {
        throw new ProcessError(
          "invalid_config",
          `Process ${policy.name}: scalar/1-word reply requires maxReplyBytes >= 4, got ${policy.maxReplyBytes}`,
        );
      }
      if (
        replySchema.kind === "FlatFixed" &&
        policy.maxReplyBytes < replySchema.stride * 4
      ) {
        throw new ProcessError(
          "invalid_config",
          `Process ${policy.name}: FlatFixed reply requires maxReplyBytes >= ${
            replySchema.stride * 4
          }, got ${policy.maxReplyBytes}`,
        );
      }

      this.#policies.set(policy.name, { policy: { ...policy }, manifest });
    }
  }

  get residentMemoryBytes(): number {
    return this.#residentMemoryBytes;
  }

  get mailboxBytesReserved(): number {
    return this.#mailboxBytesReserved;
  }

  get activeSubprocesses(): number {
    return this.#activeSubprocesses;
  }

  get aborted(): boolean {
    return this.#aborted;
  }

  #memoryChargeFor(policy: ProcessPolicy): number {
    if (policy.memory !== undefined) return policy.memory;
    if (this.#meta.memoryShape.maximumPages !== undefined) {
      return this.#meta.memoryShape.maximumPages * 65_536;
    }
    return this.#meta.memoryShape.initialPages * 65_536;
  }

  #useSubprocess(policy: ProcessPolicy): boolean {
    return policy.deadlineMs !== undefined ||
      Boolean(this.#hooks?.forceSubprocess);
  }

  #assertNotTransitioningOrAborted(allowWhenAborted = false): void {
    if (this.#exclusiveTransition !== null) {
      throw new ProcessError(
        "transition_in_progress",
        `Processes scheduler is ${this.#exclusiveTransition}`,
      );
    }
    if (!allowWhenAborted && this.#aborted) {
      throw new ProcessError(
        "scheduler_aborted",
        "Processes scheduler permanently aborted after Overrun",
      );
    }
  }

  #lookupHandle(handle: ProcessHandle): Child | "stale" | undefined {
    if (handle.schedulerId !== this.#schedulerId) return "stale";
    if (handle.epoch !== this.#generation) return "stale";
    return this.#children.get(handle.endpoint);
  }

  admit(name: string, config: ProcessValue): ProcessHandle | null {
    this.#assertNotTransitioningOrAborted();
    const reg = this.#policies.get(name);
    if (!reg) return null;
    if (
      this.#children.size >= this.#slots ||
      this.#nextEndpoint > 0xffff_ffff
    ) {
      return null;
    }
    if (reg.policy.slots !== undefined) {
      let count = 0;
      for (const c of this.#children.values()) {
        if (c.policy.name === name) count++;
      }
      if (count >= reg.policy.slots) return null;
    }

    // Validate & privately copy array config synchronously BEFORE returning!
    const encoded = encodeValueForSchema(
      config,
      reg.manifest.configSchema,
      this.#transportBudget,
      `${name} config`,
    );
    if (encoded.byteLength > reg.policy.mailboxBytes) {
      return null;
    }

    const endpoint = this.#nextEndpoint++;
    const handle: ProcessHandle = Object.freeze({
      schedulerId: this.#schedulerId,
      endpoint,
      epoch: this.#generation,
    });

    const child: Child = {
      handle,
      policy: reg.policy,
      manifest: reg.manifest,
      status: "starting",
      retirementState: "live",
      fenced: false,
      transport: null,
      inlineGuest: null,
      retireTransportPromise: null,
      settlementDone: null,
      memoryReserved: false,
      memoryCharge: this.#memoryChargeFor(reg.policy),
      initConfig: encoded,
      initConfigBytesCharged: encoded.byteLength,
      initRunId: 0,
      initOnTimeCaptured: false,
      inFlight: null,
      pending: new Map(),
      events: [],
      mailboxBytesUsed: encoded.byteLength,
    };
    this.#mailboxBytesReserved += encoded.byteLength;
    this.#children.set(endpoint, child);
    this.#order.push(endpoint);
    return handle;
  }

  status(handle: ProcessHandle): ProcessStatus {
    const c = this.#lookupHandle(handle);
    if (c === "stale" || c === undefined) return "closed";
    return c.status;
  }

  send(
    handle: ProcessHandle,
    command: ProcessValue,
  ): number | "starting" | "full" | "closed" | "stale" {
    this.#assertNotTransitioningOrAborted();
    const child = this.#lookupHandle(handle);
    if (child === "stale") return "stale";
    if (
      child === undefined ||
      child.fenced ||
      child.retirementState !== "live" ||
      child.status === "failed" ||
      child.status === "closed"
    ) {
      return "closed";
    }
    if (child.status === "starting") return "starting";

    // Continuous mailbox-slot reservation spanning pending + inFlight + events (§5.2)!
    const occupiedSlots = child.pending.size +
      (child.inFlight !== null ? 1 : 0) + child.events.length;
    if (occupiedSlots >= child.policy.mailbox) return "full";

    // Privately copy array cmd synchronously via copyPrivateBytes!
    const encoded = encodeValueForSchema(
      command,
      child.manifest.cmdSchema,
      this.#transportBudget,
      `${child.policy.name} command`,
    );
    const reserveBytes = encoded.byteLength + child.policy.maxReplyBytes;
    if (child.mailboxBytesUsed + reserveBytes > child.policy.mailboxBytes) {
      return "full";
    }

    const ticket = this.#nextTicket++;
    child.mailboxBytesUsed += reserveBytes;
    this.#mailboxBytesReserved += reserveBytes;
    child.pending.set(ticket, {
      ticket,
      encoded,
      cmdBytes: encoded.byteLength,
      maxReplyBytes: child.policy.maxReplyBytes,
    });
    return ticket;
  }

  poll(handle: ProcessHandle): ProcessEvent | undefined {
    this.#assertNotTransitioningOrAborted(true);
    const child = this.#lookupHandle(handle);
    if (child === "stale" || child === undefined) return undefined;
    const ev = child.events.shift();
    if (ev !== undefined && ev.status === "done") {
      child.mailboxBytesUsed = Math.max(
        0,
        child.mailboxBytesUsed - ev.logicalReplyBytes,
      );
      this.#mailboxBytesReserved = Math.max(
        0,
        this.#mailboxBytesReserved - ev.logicalReplyBytes,
      );
    }
    return ev;
  }

  cancel(handle: ProcessHandle, ticket: number): boolean {
    if (this.#exclusiveTransition !== null || this.#aborted) return false;
    const child = this.#lookupHandle(handle);
    if (
      child === "stale" ||
      child === undefined ||
      child.fenced ||
      child.retirementState !== "live" ||
      (child.status !== "starting" && child.status !== "ready")
    ) {
      return false;
    }
    const pending = child.pending.get(ticket);
    if (!pending) return false;
    child.pending.delete(ticket);
    const release = pending.cmdBytes + pending.maxReplyBytes;
    child.mailboxBytesUsed = Math.max(0, child.mailboxBytesUsed - release);
    this.#mailboxBytesReserved = Math.max(
      0,
      this.#mailboxBytesReserved - release,
    );
    child.events.push({ ticket, status: "cancelled" });
    return true;
  }

  release(handle: ProcessHandle): boolean {
    if (this.#exclusiveTransition !== null) return false;
    const child = this.#lookupHandle(handle);
    if (child === "stale" || child === undefined) return false;
    if (
      child.retirementState !== "retired" ||
      child.inFlight !== null ||
      child.pending.size !== 0 ||
      child.events.length !== 0
    ) {
      return false;
    }
    const idx = this.#order.indexOf(handle.endpoint);
    if (idx !== -1) {
      this.#order.splice(idx, 1);
      if (idx < this.#cursor) this.#cursor--;
      if (this.#cursor >= this.#order.length) this.#cursor = 0;
    }
    return this.#children.delete(handle.endpoint);
  }

  /** Single-owner in-flight turn settlement (§5.2). */
  #settleInFlightTurn(
    child: Child,
    outcome:
      | { kind: "done"; value: ProcessValue; logicalReplyBytes: number }
      | { kind: "failed" | "cancelled" },
  ): void {
    const turn = child.inFlight;
    if (turn === null || turn.settled) return;
    turn.settled = true;
    if (turn.timer !== undefined) {
      clearTimeout(turn.timer);
      turn.timer = undefined;
    }
    turn.completedReply = undefined;
    child.inFlight = null;

    const reserved = turn.cmdBytes + turn.maxReplyBytes;
    if (outcome.kind === "done") {
      // Release cmdBytes + maxReplyBytes and replace with logicalReplyBytes!
      const delta = reserved - outcome.logicalReplyBytes;
      child.mailboxBytesUsed = Math.max(0, child.mailboxBytesUsed - delta);
      this.#mailboxBytesReserved = Math.max(
        0,
        this.#mailboxBytesReserved - delta,
      );
      child.events.push({
        ticket: turn.ticket,
        status: "done",
        value: outcome.value,
        logicalReplyBytes: outcome.logicalReplyBytes,
      });
    } else {
      child.mailboxBytesUsed = Math.max(0, child.mailboxBytesUsed - reserved);
      this.#mailboxBytesReserved = Math.max(
        0,
        this.#mailboxBytesReserved - reserved,
      );
      child.events.push({ ticket: turn.ticket, status: outcome.kind });
    }
  }

  /**
   * Unified retirement pipeline (`child.settlementDone`) identically handling
   * never-spawned, sync-spawn-failed, partially-spawned, and live children (§5.2).
   */
  #startRetirement(
    child: Child,
    terminalKind: "failed" | "cancelled",
    transportOutcome: { kind: "fenced" } | { kind: "fault"; reason: string } = {
      kind: "fenced",
    },
  ): Promise<void> {
    if (child.settlementDone !== null) return child.settlementDone;

    // Synchronous phase BEFORE any await:
    child.retirementState = "retiring";
    child.fenced = true;
    child.status = terminalKind === "failed" ? "failed" : "closed";
    if (child.inFlight?.timer !== undefined) {
      clearTimeout(child.inFlight.timer);
      child.inFlight.timer = undefined;
    }
    if (child.initTimer !== undefined) {
      clearTimeout(child.initTimer);
      child.initTimer = undefined;
    }
    if (child.transport !== null) {
      child.transport.closeTransport(transportOutcome);
    }
    const detachedPending = [...child.pending.values()];
    child.pending.clear();
    if (child.inFlight !== null) {
      child.inFlight.completedReply = undefined;
    }

    const transport = child.transport;
    child.settlementDone = (async () => {
      if (this.#hooks?.onBeforeRetireFinish) {
        await this.#hooks.onBeforeRetireFinish(child.handle.endpoint);
      }
      if (transport !== null) {
        await (child.retireTransportPromise ??= transport.retire());
        if (child.transport === transport) {
          child.transport = null;
          this.#activeSubprocesses = Math.max(0, this.#activeSubprocesses - 1);
        }
      }
      child.inlineGuest = null;

      if (child.initConfigBytesCharged > 0) {
        const cfgBytes = child.initConfigBytesCharged;
        child.initConfigBytesCharged = 0;
        child.initConfig = null;
        child.mailboxBytesUsed = Math.max(0, child.mailboxBytesUsed - cfgBytes);
        this.#mailboxBytesReserved = Math.max(
          0,
          this.#mailboxBytesReserved - cfgBytes,
        );
      }

      if (child.inFlight !== null) {
        this.#settleInFlightTurn(child, { kind: terminalKind });
      }
      for (const cmd of detachedPending) {
        const rel = cmd.cmdBytes + cmd.maxReplyBytes;
        child.mailboxBytesUsed = Math.max(0, child.mailboxBytesUsed - rel);
        this.#mailboxBytesReserved = Math.max(
          0,
          this.#mailboxBytesReserved - rel,
        );
        child.events.push({ ticket: cmd.ticket, status: terminalKind });
      }
      if (child.memoryReserved) {
        child.memoryReserved = false;
        this.#residentMemoryBytes = Math.max(
          0,
          this.#residentMemoryBytes - child.memoryCharge,
        );
      }
      child.retirementState = "retired";
    })();
    return child.settlementDone;
  }

  async close(handle: ProcessHandle): Promise<void> {
    this.#assertNotTransitioningOrAborted(true);
    const child = this.#lookupHandle(handle);
    if (child === "stale" || child === undefined) return;
    if (child.retirementState === "retired") return;
    await this.#startRetirement(child, "cancelled", { kind: "fenced" });
  }

  /**
   * Exclusive drain helper shared by `restore()` and fatal `Overrun` abort.
   * Caller MUST have already claimed `this.#exclusiveTransition` synchronously!
   */
  async #drainAllAndReset(): Promise<
    Map<ProcessHandle, readonly ProcessEvent[]>
  > {
    this.#generation++;
    const allChildren = [...this.#children.values()];
    for (const child of allChildren) {
      if (child.retirementState === "live") {
        this.#startRetirement(child, "cancelled", { kind: "fenced" });
      }
    }
    await Promise.all(
      allChildren
        .map((c) => c.settlementDone)
        .filter((p): p is Promise<void> => p !== null),
    );

    const drained = new Map<ProcessHandle, readonly ProcessEvent[]>();
    for (const child of allChildren) {
      if (child.events.length > 0) {
        for (const ev of child.events) {
          if (ev.status === "done") {
            child.mailboxBytesUsed = Math.max(
              0,
              child.mailboxBytesUsed - ev.logicalReplyBytes,
            );
            this.#mailboxBytesReserved = Math.max(
              0,
              this.#mailboxBytesReserved - ev.logicalReplyBytes,
            );
          }
        }
        drained.set(child.handle, [...child.events]);
        child.events.length = 0;
      }
    }
    this.#children.clear();
    this.#order.length = 0;
    this.#cursor = 0;
    this.#runningGeneration = null;
    return drained;
  }

  /**
   * Fence all live endpoints, join all retirements (including in-flight `close`),
   * and exclusively drain all undelivered `Done` + `Cancelled` events (§5.2).
   */
  async restore(): Promise<
    ReadonlyMap<ProcessHandle, readonly ProcessEvent[]>
  > {
    if (this.#exclusiveTransition !== null) {
      throw new ProcessError(
        "transition_in_progress",
        `Cannot restore while scheduler is ${this.#exclusiveTransition}`,
      );
    }
    if (this.#aborted) {
      return new Map();
    }
    this.#exclusiveTransition = "restoring";
    try {
      return await this.#drainAllAndReset();
    } finally {
      this.#exclusiveTransition = null;
    }
  }

  /**
   * Claim `#exclusiveTransition = "aborting"`, permanently mark `#aborted = true`,
   * kill-first retire ALL live children (both active AND idle!), and return
   * `ProcessOverrunError` carrying all drained events.
   */
  #abortForOverrun(reason: string): Promise<ProcessOverrunError> | null {
    if (this.#exclusiveTransition !== null) return null;
    this.#exclusiveTransition = "aborting";
    this.#aborted = true;
    return (async () => {
      try {
        const drained = await this.#drainAllAndReset();
        return new ProcessOverrunError(reason, drained);
      } finally {
        this.#exclusiveTransition = null;
      }
    })();
  }

  /** Execute one child turn (either init or step), returning wave result. */
  async #executeChildTurn(
    child: Child,
    isInit: boolean,
    generation: number,
    onOverrunSignal: (reason: string) => void,
    isWaveAborted: () => boolean,
  ): Promise<
    | { kind: "ok_init" }
    | { kind: "ok_step"; turn: InFlightTurn }
    | { kind: "deterministic_fail" }
    | { kind: "overrun"; reason: string }
    | { kind: "fenced" }
  > {
    const useSub = this.#useSubprocess(child.policy);

    if (isInit) {
      // Reserve resident memory BEFORE spawn / Wasm start!
      child.memoryReserved = true;
      this.#residentMemoryBytes += child.memoryCharge;

      if (!useSub) {
        try {
          const guest = new InlineProcessGuest(
            this.#meta,
            child.manifest,
            child.policy.maxReplyBytes,
          );
          guest.init(child.initConfig!);
          child.inlineGuest = guest;
          child.initOnTimeCaptured = true;
          return { kind: "ok_init" };
        } catch {
          await this.#startRetirement(child, "failed", {
            kind: "fault",
            reason: "init_trap",
          });
          return { kind: "deterministic_fail" };
        }
      }

      const runId = ++this.#nextInitRunId;
      child.initRunId = runId;
      child.initOnTimeCaptured = false;
      const initDeadlineMs = child.policy.deadlineMs !== undefined
        ? performance.now() + child.policy.deadlineMs
        : null;

      // Arm init timer BEFORE calling Deno.Command.spawn()!
      if (initDeadlineMs !== null) {
        const initTimerCb = () => {
          // Ticketless init timer guard (NO child.inFlight check!) + monotonic recheck!
          if (
            generation !== this.#generation ||
            this.#exclusiveTransition !== null ||
            child.retirementState !== "live" ||
            child.fenced ||
            child.status !== "starting" ||
            child.initRunId !== runId ||
            child.initOnTimeCaptured
          ) {
            return;
          }
          const remaining = initDeadlineMs - performance.now();
          if (remaining > 0) {
            child.initTimer = setTimeout(initTimerCb, Math.ceil(remaining));
            return;
          }
          onOverrunSignal(`Process ${child.policy.name} init timed out`);
        };
        child.initTimer = setTimeout(
          initTimerCb,
          Math.max(1, Math.ceil(initDeadlineMs - performance.now())),
        );
        this.#hooks?.onTimerArmed?.({
          kind: "init",
          endpoint: child.handle.endpoint,
          deadlineMs: initDeadlineMs,
          fire: initTimerCb,
        });
      }

      // Spawn subprocess (handling synchronous spawn failure cleanly via settlementDone!).
      let transport: ProcessSubprocess;
      try {
        if (this.#hooks?.failSpawnForName?.has(child.policy.name)) {
          throw new Error("injected synchronous spawn failure");
        }
        const scriptUrl = this.#hooks?.subprocessUrl ?? SUBPROCESS_URL;
        transport = new ProcessSubprocess(
          child.handle.endpoint,
          scriptUrl,
          this.#hooks,
        );
      } catch {
        await this.#startRetirement(child, "failed", {
          kind: "fault",
          reason: "spawn_failed",
        });
        return { kind: "deterministic_fail" };
      }

      child.transport = transport;
      this.#activeSubprocesses++;

      // If fenced/aborted between spawn and command send:
      if (
        generation !== this.#generation ||
        child.retirementState !== "live" ||
        child.fenced ||
        isWaveAborted()
      ) {
        return { kind: "fenced" };
      }

      const initPayload = encodeProcessInitPayload(
        this.#meta.snapshot,
        child.manifest,
        child.policy.maxReplyBytes,
        child.initConfig!.bytes,
      );
      const outcome = await transport.sendCommand(
        CMD_INIT,
        runId,
        initPayload,
        child.initConfig!.inlineWord,
        {
          seq: runId,
          kind: "init",
          replyWireTag: child.manifest.replySchema.wireTagCode,
          replyFixedBytes: null,
          maxReplyBytes: child.policy.maxReplyBytes,
          deadlineMs: initDeadlineMs,
        },
      );

      // Evaluate generation / fencing FIRST (restore or close beat us).
      if (
        generation !== this.#generation ||
        child.retirementState !== "live" ||
        child.fenced ||
        this.#exclusiveTransition === "restoring"
      ) {
        return { kind: "fenced" };
      }
      if (isWaveAborted()) {
        return { kind: "overrun", reason: "Wave aborted" };
      }

      // Evaluate monotonic initDeadlineMs ONCE right at observation!
      if (initDeadlineMs !== null && performance.now() >= initDeadlineMs) {
        return {
          kind: "overrun",
          reason: `Process ${child.policy.name} init exceeded deadline`,
        };
      }

      if (outcome.kind === "init_ok") {
        // Latch on-time capture and disarm timer immediately!
        child.initOnTimeCaptured = true;
        if (child.initTimer !== undefined) {
          clearTimeout(child.initTimer);
          child.initTimer = undefined;
        }
        if (this.#hooks?.onAfterChildWaveResult) {
          await this.#hooks.onAfterChildWaveResult({
            endpoint: child.handle.endpoint,
            kind: "init",
          });
        }
        return { kind: "ok_init" };
      }

      if (outcome.kind === "fenced") {
        return { kind: "fenced" };
      }

      // Deterministic init failure (INIT_FAIL or parser fault before deadline).
      await this.#startRetirement(child, "failed", {
        kind: "fault",
        reason: outcome.kind === "fault" ? outcome.reason : "init_fail",
      });
      return { kind: "deterministic_fail" };
    }

    // Step turn: move oldest pending ticket into child.inFlight (retaining slot + bytes!).
    const [ticket, cmd] = child.pending.entries().next().value!;
    child.pending.delete(ticket);
    const turn: InFlightTurn = {
      generation,
      ticket,
      cmdBytes: cmd.cmdBytes,
      maxReplyBytes: cmd.maxReplyBytes,
      completedReply: undefined,
      completedReplyBytes: 0,
      onTimeCaptured: false,
      settled: false,
    };
    child.inFlight = turn;

    if (!useSub) {
      try {
        const res = child.inlineGuest!.step(cmd.encoded);
        turn.completedReply = res.value;
        turn.completedReplyBytes = res.logicalReplyBytes;
        turn.onTimeCaptured = true;
        return { kind: "ok_step", turn };
      } catch {
        await this.#startRetirement(child, "failed", {
          kind: "fault",
          reason: "step_trap",
        });
        return { kind: "deterministic_fail" };
      }
    }

    const transport = child.transport;
    if (transport === null) {
      await this.#startRetirement(child, "failed", {
        kind: "fault",
        reason: "missing_transport",
      });
      return { kind: "deterministic_fail" };
    }

    const turnDeadlineMs = child.policy.deadlineMs !== undefined
      ? performance.now() + child.policy.deadlineMs
      : null;

    if (turnDeadlineMs !== null) {
      const turnTimerCb = () => {
        // Ticketed step timer guard + monotonic clock recheck (§5.2)!
        if (
          generation !== this.#generation ||
          this.#exclusiveTransition !== null ||
          child.retirementState !== "live" ||
          child.fenced ||
          child.inFlight !== turn ||
          turn.onTimeCaptured ||
          turn.settled
        ) {
          return;
        }
        const remaining = turnDeadlineMs - performance.now();
        if (remaining > 0) {
          turn.timer = setTimeout(turnTimerCb, Math.ceil(remaining));
          return;
        }
        onOverrunSignal(`Process ${child.policy.name} step timed out`);
      };
      turn.timer = setTimeout(
        turnTimerCb,
        Math.max(1, Math.ceil(turnDeadlineMs - performance.now())),
      );
      this.#hooks?.onTimerArmed?.({
        kind: "step",
        endpoint: child.handle.endpoint,
        deadlineMs: turnDeadlineMs,
        fire: turnTimerCb,
      });
    }

    const replyFixedBytes = child.manifest.replySchema.kind === "FlatFixed" &&
        (child.manifest.replySchema.wireTagCode === 5 ||
          child.manifest.replySchema.wireTagCode === 6)
      ? child.manifest.replySchema.stride * 4
      : null;

    const outcome = await transport.sendCommand(
      CMD_STEP,
      ticket,
      cmd.encoded.bytes,
      cmd.encoded.inlineWord,
      {
        seq: ticket,
        kind: "step",
        replyWireTag: child.manifest.replySchema.wireTagCode,
        replyFixedBytes,
        maxReplyBytes: cmd.maxReplyBytes,
        deadlineMs: turnDeadlineMs,
      },
    );

    if (
      generation !== this.#generation ||
      child.retirementState !== "live" ||
      child.fenced ||
      turn.settled ||
      this.#exclusiveTransition === "restoring"
    ) {
      return { kind: "fenced" };
    }
    if (isWaveAborted()) {
      return { kind: "overrun", reason: "Wave aborted" };
    }

    // Evaluate monotonic turnDeadlineMs ONCE right at observation BEFORE accepting reply/fault!
    if (turnDeadlineMs !== null && performance.now() >= turnDeadlineMs) {
      return {
        kind: "overrun",
        reason: `Process ${child.policy.name} step exceeded deadline`,
      };
    }

    if (
      outcome.kind === "commit_ok_unit" ||
      outcome.kind === "commit_ok_scalar" ||
      outcome.kind === "commit_ok_data"
    ) {
      const decoded = decodeProcessReply(child.manifest.replySchema, outcome);
      turn.completedReply = decoded.value;
      turn.completedReplyBytes = decoded.logicalReplyBytes;
      turn.onTimeCaptured = true;
      if (turn.timer !== undefined) {
        clearTimeout(turn.timer);
        turn.timer = undefined;
      }
      if (this.#hooks?.onAfterChildWaveResult) {
        await this.#hooks.onAfterChildWaveResult({
          endpoint: child.handle.endpoint,
          kind: "step",
        });
      }
      return { kind: "ok_step", turn };
    }

    if (outcome.kind === "fenced") {
      return { kind: "fenced" };
    }

    // Deterministic step/cleanup/parser/schema fault before deadline:
    await this.#startRetirement(child, "failed", {
      kind: "fault",
      reason: outcome.kind === "fault" ? outcome.reason : outcome.kind,
    });
    return { kind: "deterministic_fail" };
  }

  async advance(budget: number): Promise<number> {
    return await this.#runScheduler(budget, false);
  }

  /**
   * Serial-equivalent multi-wave parallel scheduler (§5.2):
   * Preserves call-wide `spent`, `skipped`, single `deferred`, and ring order
   * identically to `advance(budget)` across all non-fatal calls.
   */
  async advanceAllParallel(budget: number): Promise<number> {
    return await this.#runScheduler(budget, true);
  }

  async #runScheduler(budget: number, parallel: boolean): Promise<number> {
    if (!Number.isSafeInteger(budget) || budget < 0) {
      throw new ProcessError("invalid_argument", "Invalid turn budget");
    }
    this.#assertNotTransitioningOrAborted();
    if (this.#runningGeneration !== null) {
      throw new ProcessError(
        "already_advancing",
        "Process scheduler is already advancing",
      );
    }

    const generation = this.#generation;
    this.#runningGeneration = generation;
    let spent = 0;
    let deferred: number | undefined;
    let overrunPromise: Promise<ProcessOverrunError> | null = null;
    let waveAborted = false;

    const triggerOverrun = (reason: string) => {
      if (generation !== this.#generation) return;
      if (this.#exclusiveTransition === "restoring") return;
      waveAborted = true;
      if (overrunPromise === null) {
        overrunPromise = this.#abortForOverrun(reason);
      }
    };

    try {
      let skipped = 0;
      while (
        generation === this.#generation &&
        !waveAborted &&
        this.#exclusiveTransition === null &&
        spent < budget &&
        this.#order.length > 0 &&
        skipped < this.#order.length
      ) {
        if (!parallel) {
          const id = this.#order[this.#cursor];
          this.#cursor = (this.#cursor + 1) % this.#order.length;
          const child = this.#children.get(id);
          if (!child || child.fenced || child.retirementState !== "live") {
            skipped++;
            continue;
          }
          const isInit = child.status === "starting";
          const cost = isInit ? child.policy.initWork : child.policy.stepWork;
          if (
            !isInit && (child.status !== "ready" || child.pending.size === 0)
          ) {
            skipped++;
            continue;
          }
          if (cost > budget - spent) {
            if (cost <= budget) deferred ??= id;
            skipped++;
            continue;
          }
          skipped = 0;
          spent += cost;

          const res = await this.#executeChildTurn(
            child,
            isInit,
            generation,
            triggerOverrun,
            () => waveAborted,
          );
          if (res.kind === "overrun") {
            triggerOverrun(res.reason);
          }
          if (overrunPromise !== null) {
            throw await overrunPromise;
          }
          if (
            generation !== this.#generation ||
            this.#children.get(id) !== child ||
            child.fenced ||
            child.retirementState !== "live"
          ) {
            if (child.inFlight !== null) {
              child.inFlight.completedReply = undefined;
            }
            continue;
          }
          if (res.kind === "ok_init" && child.initOnTimeCaptured) {
            child.status = "ready";
            if (child.initConfigBytesCharged > 0) {
              const cfgBytes = child.initConfigBytesCharged;
              child.initConfigBytesCharged = 0;
              child.initConfig = null;
              child.mailboxBytesUsed = Math.max(
                0,
                child.mailboxBytesUsed - cfgBytes,
              );
              this.#mailboxBytesReserved = Math.max(
                0,
                this.#mailboxBytesReserved - cfgBytes,
              );
            }
          } else if (
            res.kind === "ok_step" &&
            !res.turn.settled &&
            res.turn.onTimeCaptured
          ) {
            this.#settleInFlightTurn(child, {
              kind: "done",
              value: res.turn.completedReply!,
              logicalReplyBytes: res.turn.completedReplyBytes,
            });
          }
          continue;
        }

        // Multi-wave parallel scheduling: exact serial-equivalent ring/cost/deferred walk!
        const wave: { id: number; child: Child; isInit: boolean }[] = [];
        const inWave = new Set<number>();

        while (
          spent < budget &&
          this.#order.length > 0 &&
          skipped < this.#order.length
        ) {
          const nextId = this.#order[this.#cursor];
          // Cannot schedule the same endpoint twice in one parallel wave;
          // stop selecting for this wave (WITHOUT advancing cursor!) so the
          // next wave resumes at this exact endpoint in exact serial order!
          if (inWave.has(nextId)) break;

          const child = this.#children.get(nextId);
          if (!child || child.fenced || child.retirementState !== "live") {
            this.#cursor = (this.#cursor + 1) % this.#order.length;
            skipped++;
            continue;
          }
          const isInit = child.status === "starting";
          const cost = isInit ? child.policy.initWork : child.policy.stepWork;
          if (
            !isInit && (child.status !== "ready" || child.pending.size === 0)
          ) {
            this.#cursor = (this.#cursor + 1) % this.#order.length;
            skipped++;
            continue;
          }
          if (cost > budget - spent) {
            this.#cursor = (this.#cursor + 1) % this.#order.length;
            if (cost <= budget) deferred ??= nextId;
            skipped++;
            continue;
          }
          this.#cursor = (this.#cursor + 1) % this.#order.length;
          skipped = 0;
          spent += cost;
          inWave.add(nextId);
          wave.push({ id: nextId, child, isInit });
        }

        if (wave.length === 0) break;

        const results = await Promise.all(
          wave.map((item) =>
            this.#executeChildTurn(
              item.child,
              item.isInit,
              generation,
              triggerOverrun,
              () => waveAborted,
            )
          ),
        );

        for (const res of results) {
          if (res.kind === "overrun") {
            triggerOverrun(res.reason);
          }
        }
        if (overrunPromise !== null) {
          throw await overrunPromise;
        }
        if (
          generation !== this.#generation || this.#exclusiveTransition !== null
        ) {
          for (const item of wave) {
            if (item.child.inFlight !== null) {
              item.child.inFlight.completedReply = undefined;
            }
          }
          break;
        }

        // Publish wave results strictly from latched on-time flags (NEVER re-checking deadlines!).
        for (let i = 0; i < wave.length; i++) {
          const { id, child } = wave[i];
          const res = results[i];
          if (
            generation !== this.#generation ||
            this.#children.get(id) !== child ||
            child.fenced ||
            child.retirementState !== "live"
          ) {
            if (child.inFlight !== null) {
              child.inFlight.completedReply = undefined;
            }
            continue;
          }
          if (res.kind === "ok_init" && child.initOnTimeCaptured) {
            child.status = "ready";
            if (child.initConfigBytesCharged > 0) {
              const cfgBytes = child.initConfigBytesCharged;
              child.initConfigBytesCharged = 0;
              child.initConfig = null;
              child.mailboxBytesUsed = Math.max(
                0,
                child.mailboxBytesUsed - cfgBytes,
              );
              this.#mailboxBytesReserved = Math.max(
                0,
                this.#mailboxBytesReserved - cfgBytes,
              );
            }
          } else if (
            res.kind === "ok_step" &&
            !res.turn.settled &&
            res.turn.onTimeCaptured
          ) {
            this.#settleInFlightTurn(child, {
              kind: "done",
              value: res.turn.completedReply!,
              logicalReplyBytes: res.turn.completedReplyBytes,
            });
          }
        }
      }

      if (overrunPromise !== null) {
        throw await overrunPromise;
      }
      return spent;
    } finally {
      if (this.#hooks?.onBeforeAdvanceFinally) {
        await this.#hooks.onBeforeAdvanceFinally(generation);
      }
      if (
        generation === this.#generation &&
        !waveAborted &&
        deferred !== undefined
      ) {
        const idx = this.#order.indexOf(deferred);
        if (idx !== -1) this.#cursor = idx;
      }
      // Clear #runningGeneration ONLY if it still belongs to this generation (§5.2)!
      if (this.#runningGeneration === generation) {
        this.#runningGeneration = null;
      }
    }
  }
}
