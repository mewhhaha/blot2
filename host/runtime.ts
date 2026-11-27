/**
 * Unified Deno host coordinator for Squid's in-language `std/runtime`,
 * `std/kernel`, and `std/process` coordination API.
 *
 * Bridges versioned `SRT1` `#[U32] -> #[U32]` ABI 8 packets directly onto
 * Squid's real `KernelPool` and `Processes` runtimes while preserving ABI 8,
 * schema/binding-hash verification, determinism, and isolation.
 */
import {
  type CompiledModuleReceipt,
  compileKernelModule,
  copyPrivateBytes,
  type Guest,
  type GuestOwner,
  type GuestValue,
  type HostCapability,
  instantiateGuest,
  type KernelManifest,
  type ProcessManifest,
  readGuestAbi,
  type WireSchema,
} from "./guest.ts";
import { KernelError, KernelPool, type KernelPoolConfig } from "./kernels.ts";
import {
  Processes,
  type ProcessEvent,
  type ProcessHandle,
  type ProcessPolicy,
  type ProcessValue,
} from "./processes.ts";
import { encodeText } from "./text.ts";

export const RUNTIME_MAGIC = 0x5352_5431;
export const RUNTIME_VERSION = 1;

const OP_KERNEL_RUN = 1;
const OP_KERNEL_PREPARE = 2;
const OP_KERNEL_RUN_PREPARED = 3;
const OP_KERNEL_CLEAR = 4;
const OP_KERNEL_SUBMIT = 5;
const OP_KERNEL_SUBMIT_PREPARED = 6;
const OP_KERNEL_POLL = 7;
const OP_KERNEL_AWAIT = 8;
const OP_PROC_SPAWN = 9;
const OP_PROC_CALL = 10;
const OP_PROC_SEND = 11;
const OP_PROC_POLL = 12;
const OP_PROC_ADVANCE = 13;
const OP_PROC_CLOSE = 14;

const STATUS_OK = 0;
const ERR_OOM = 1;
const ERR_TRAP = 2;
const ERR_TIMEOUT = 3;
const ERR_BUDGET = 4;
const ERR_INVALID_HANDLE = 5;
const ERR_HOST = 6;
const ERR_PROC_FAILED = 10;
const ERR_PROC_CANCELLED = 11;
const ERR_PROC_OVERRUN = 12;
const ERR_PROC_INVALID_HANDLE = 13;
const ERR_PROC_HOST = 14;

const FNV_OFFSET = 0xcbf2_9ce4_8422_2325n;
const FNV_PRIME = 0x0000_0100_0000_01b3n;
const MASK_64 = 0xffff_ffff_ffff_ffffn;

function fnvByte(h: bigint, b: number): bigint {
  return ((h ^ BigInt(b & 0xff)) * FNV_PRIME) & MASK_64;
}

function fnvU64Le(h: bigint, v: bigint): bigint {
  let out = h;
  for (let i = 0; i < 8; i++) {
    out = fnvByte(out, Number((v >> BigInt(i * 8)) & 0xffn));
  }
  return out;
}

/** Matches compiler-goose `wire_schema.goose` process binding hash (tag 0x13). */
export function computeProcessBindingHash(manifest: ProcessManifest): bigint {
  let h = FNV_OFFSET;
  h = fnvByte(h, 0x13);
  h = fnvU64Le(h, manifest.configSchema.schemaHash);
  h = fnvU64Le(h, manifest.cmdSchema.schemaHash);
  h = fnvU64Le(h, manifest.replySchema.schemaHash);
  return h;
}

function u64FromWords(lo: number, hi: number): bigint {
  return (BigInt(hi >>> 0) << 32n) | BigInt(lo >>> 0);
}

function okResponse(words: readonly number[] | Uint32Array = []): Uint32Array {
  const out = new Uint32Array(2 + words.length);
  out[0] = RUNTIME_MAGIC;
  out[1] = STATUS_OK;
  out.set(words, 2);
  return out;
}

function errResponse(code: number, message = ""): Uint32Array {
  const msgWords = message ? encodeText(message) : new Uint32Array(0);
  const out = new Uint32Array(2 + msgWords.length);
  out[0] = RUNTIME_MAGIC;
  out[1] = code >>> 0;
  out.set(msgWords, 2);
  return out;
}

function mapKernelError(err: unknown): { code: number; message: string } {
  if (err instanceof KernelError) {
    switch (err.code) {
      case "out_of_memory":
        return { code: ERR_OOM, message: err.message };
      case "run_trap":
      case "cleanup_trap":
        return { code: ERR_TRAP, message: err.message };
      case "timeout":
        return { code: ERR_TIMEOUT, message: err.message };
      case "input_snapshot_budget_exceeded":
      case "output_budget_exceeded":
      case "single_item_output_overflow":
        return { code: ERR_BUDGET, message: err.message };
      case "unknown_kernel":
      case "context_not_prepared":
      case "revision_content_mismatch":
        return { code: ERR_INVALID_HANDLE, message: err.message };
      default:
        return { code: ERR_HOST, message: err.message };
    }
  }
  return {
    code: ERR_HOST,
    message: err instanceof Error ? err.message : String(err),
  };
}

function wordsToKernelView(
  schema: WireSchema,
  words: Uint32Array,
): Uint32Array | Float32Array {
  if (schema.wireTag === "Array F32") {
    const copy = new Uint32Array(words);
    return new Float32Array(copy.buffer, copy.byteOffset, copy.length);
  }
  return new Uint32Array(words);
}

function wordsToProcessValue(
  schema: WireSchema,
  words: Uint32Array,
): ProcessValue {
  switch (schema.wireTag) {
    case "Unit":
      return null;
    case "U32":
      return words.length > 0 ? words[0] >>> 0 : 0;
    case "Bool":
      return words.length > 0 ? words[0] !== 0 : false;
    case "F32": {
      const dv = new DataView(new ArrayBuffer(4));
      dv.setUint32(0, words.length > 0 ? words[0] >>> 0 : 0, true);
      return dv.getFloat32(0, true);
    }
    case "Array F32": {
      const copy = new Uint32Array(words);
      return new Float32Array(copy.buffer, copy.byteOffset, copy.length);
    }
    case "Array U32":
      return new Uint32Array(words);
    default:
      throw new Error(`Unsupported process wire tag ${schema.wireTag}`);
  }
}

function processValueToWords(
  schema: WireSchema,
  value: ProcessValue,
): Uint32Array {
  switch (schema.wireTag) {
    case "Unit":
      return new Uint32Array(0);
    case "U32":
      return new Uint32Array([(value as number) >>> 0]);
    case "Bool":
      return new Uint32Array([value ? 1 : 0]);
    case "F32": {
      const dv = new DataView(new ArrayBuffer(4));
      dv.setFloat32(0, Math.fround(value as number), true);
      return new Uint32Array([dv.getUint32(0, true)]);
    }
    case "Array F32": {
      const arr = value as Float32Array;
      return new Uint32Array(
        arr.buffer.slice(arr.byteOffset, arr.byteOffset + arr.byteLength),
      );
    }
    case "Array U32":
      return new Uint32Array(value as Uint32Array);
    default:
      throw new Error(`Unsupported process wire tag ${schema.wireTag}`);
  }
}

export interface SquidRuntimeOptions {
  /** Number of worker threads/subprocesses per KernelPool (default: 1; 0 runs direct). */
  workers?: number;
  /** Per-kernel pool config overrides. */
  kernelPool?: Omit<KernelPoolConfig, "workers">;
  /** Maximum live process instances across all `#process` declarations (default: 32). */
  processSlots?: number;
  /** Default per-process policy overrides. */
  processPolicy?: Partial<Omit<ProcessPolicy, "name">>;
}

interface KernelJobState {
  done: boolean;
  ok: boolean;
  words?: Uint32Array;
  errCode?: number;
  errMsg?: string;
  promise: Promise<void>;
}

interface ManagedKernel {
  manifest: KernelManifest;
  poolPromise: Promise<KernelPool>;
  queue: Promise<void>;
  activeSlot: number;
  preparedCtxWords?: Uint32Array;
}

interface ManagedProcess {
  handle: ProcessHandle;
  manifest: ProcessManifest;
  completedEvents: Map<number, ProcessEvent>;
}

export class SquidRuntime {
  readonly #wasmBytes: Uint8Array<ArrayBuffer>;
  readonly #receipt: CompiledModuleReceipt;
  readonly #kernels: readonly KernelManifest[];
  readonly #processesManifests: readonly ProcessManifest[];
  readonly #options: SquidRuntimeOptions;
  readonly #managedKernels = new Map<number, ManagedKernel>();
  readonly #jobs = new Map<number, KernelJobState>();
  readonly #managedProcesses = new Map<string, ManagedProcess>();
  #processesScheduler: Processes | null = null;
  #nextSlot = 1;
  #nextJobId = 1;
  #disposed = false;

  constructor(
    wasmBytes: Uint8Array,
    options: SquidRuntimeOptions = {},
  ) {
    this.#wasmBytes = copyPrivateBytes(wasmBytes);
    this.#receipt = compileKernelModule(this.#wasmBytes);
    const abi = readGuestAbi(new WebAssembly.Module(this.#wasmBytes));
    this.#kernels = abi.kernels ?? [];
    this.#processesManifests = abi.processes ?? [];
    this.#options = options;
  }

  #getKernel(
    kernelId: number,
    hashLo: number,
    hashHi: number,
  ): ManagedKernel | null {
    const manifest = this.#kernels[kernelId];
    if (!manifest) return null;
    if (manifest.bindingHash !== u64FromWords(hashLo, hashHi)) return null;
    let managed = this.#managedKernels.get(kernelId);
    if (!managed) {
      const poolPromise = KernelPool.open(this.#receipt, manifest.name, {
        workers: this.#options.workers ?? 1,
        ...this.#options.kernelPool,
      });
      managed = {
        manifest,
        poolPromise,
        queue: Promise.resolve(),
        activeSlot: 0,
      };
      this.#managedKernels.set(kernelId, managed);
    }
    return managed;
  }

  #enqueueKernelOp<T>(
    managed: ManagedKernel,
    fn: (pool: KernelPool) => Promise<T>,
  ): Promise<T> {
    const next = managed.queue.then(async () => {
      const pool = await managed.poolPromise;
      return await fn(pool);
    });
    managed.queue = next.then(() => undefined, () => undefined);
    return next;
  }

  #ensureProcesses(): Processes {
    if (!this.#processesScheduler) {
      const defaults = this.#options.processPolicy ?? {};
      const policies: ProcessPolicy[] = this.#processesManifests.map((m) => ({
        name: m.name,
        initWork: defaults.initWork ?? 1,
        stepWork: defaults.stepWork ?? 1,
        deadlineMs: defaults.deadlineMs,
        memory: defaults.memory,
        mailbox: defaults.mailbox ?? 64,
        mailboxBytes: defaults.mailboxBytes ?? 1_048_576,
        maxReplyBytes: defaults.maxReplyBytes ?? 262_144,
        slots: defaults.slots,
      }));
      this.#processesScheduler = new Processes(this.#receipt, policies, {
        slots: this.#options.processSlots ?? 32,
      });
    }
    return this.#processesScheduler;
  }

  #procKey(endpoint: number, epoch: number): string {
    return `${endpoint >>> 0}:${epoch >>> 0}`;
  }

  #drainInto(proc: ManagedProcess): void {
    const scheduler = this.#processesScheduler;
    if (!scheduler) return;
    while (true) {
      const ev = scheduler.poll(proc.handle);
      if (!ev) break;
      proc.completedEvents.set(ev.ticket, ev);
    }
  }

  async #executeKernelBatch(
    managed: ManagedKernel,
    itemCount: number,
    payload: Uint32Array,
    requiredSlot?: number,
  ): Promise<Uint32Array> {
    return await this.#enqueueKernelOp(managed, async (pool) => {
      if (requiredSlot !== undefined && managed.activeSlot !== requiredSlot) {
        throw new KernelError(
          "context_not_prepared",
          "Prepared kernel context slot is stale or cleared",
        );
      }
      if (itemCount === 0) {
        return new Uint32Array(0);
      }
      const inView = wordsToKernelView(managed.manifest.inSchema, payload);
      if (managed.manifest.variableOutput) {
        return await pool.runVariable(inView);
      }
      return await pool.runFixed(inView);
    });
  }

  /** Handle one `SRT1` `#[U32] -> #[U32]` coordination packet from Squid guest code. */
  async handlePacket(req: Uint32Array): Promise<Uint32Array> {
    if (this.#disposed) {
      return errResponse(ERR_HOST, "SquidRuntime is disposed");
    }
    if (
      req.length < 3 || req[0] !== RUNTIME_MAGIC || req[1] !== RUNTIME_VERSION
    ) {
      return errResponse(ERR_HOST, "Invalid SRT1 runtime packet header");
    }
    const op = req[2] >>> 0;

    switch (op) {
      case OP_KERNEL_RUN: {
        if (req.length < 7) {
          return errResponse(ERR_HOST, "Truncated KERNEL_RUN");
        }
        const managed = this.#getKernel(req[3] >>> 0, req[4], req[5]);
        if (!managed) {
          return errResponse(ERR_INVALID_HANDLE, "Invalid kernel handle");
        }
        const itemCount = req[6] >>> 0;
        const payload = req.subarray(7);
        try {
          const out = await this.#executeKernelBatch(
            managed,
            itemCount,
            payload,
          );
          return okResponse(out);
        } catch (err) {
          const mapped = mapKernelError(err);
          return errResponse(mapped.code, mapped.message);
        }
      }

      case OP_KERNEL_PREPARE: {
        if (req.length < 6) {
          return errResponse(ERR_HOST, "Truncated KERNEL_PREPARE");
        }
        const managed = this.#getKernel(req[3] >>> 0, req[4], req[5]);
        if (
          !managed || !managed.manifest.hasContext ||
          !managed.manifest.ctxSchema
        ) {
          return errResponse(
            ERR_INVALID_HANDLE,
            "Invalid prepared kernel handle",
          );
        }
        const ctxWords = new Uint32Array(req.subarray(6));
        const ctxView = wordsToKernelView(managed.manifest.ctxSchema, ctxWords);
        const slot = this.#nextSlot++;
        try {
          await this.#enqueueKernelOp(managed, async (pool) => {
            await pool.setContext(slot, ctxView);
            managed.activeSlot = slot;
            managed.preparedCtxWords = ctxWords;
          });
          return okResponse([slot]);
        } catch (err) {
          const mapped = mapKernelError(err);
          return errResponse(mapped.code, mapped.message);
        }
      }

      case OP_KERNEL_RUN_PREPARED: {
        if (req.length < 8) {
          return errResponse(ERR_HOST, "Truncated KERNEL_RUN_PREPARED");
        }
        const managed = this.#getKernel(req[3] >>> 0, req[5], req[6]);
        const slot = req[4] >>> 0;
        if (!managed) {
          return errResponse(ERR_INVALID_HANDLE, "Invalid kernel handle");
        }
        const itemCount = req[7] >>> 0;
        const payload = req.subarray(8);
        try {
          const out = await this.#executeKernelBatch(
            managed,
            itemCount,
            payload,
            slot,
          );
          return okResponse(out);
        } catch (err) {
          const mapped = mapKernelError(err);
          return errResponse(mapped.code, mapped.message);
        }
      }

      case OP_KERNEL_CLEAR: {
        if (req.length < 5) {
          return errResponse(ERR_HOST, "Truncated KERNEL_CLEAR");
        }
        const kernelId = req[3] >>> 0;
        const slot = req[4] >>> 0;
        const managed = this.#managedKernels.get(kernelId);
        if (managed && managed.activeSlot === slot) {
          await this.#enqueueKernelOp(managed, async (pool) => {
            if (managed.activeSlot === slot) {
              await pool.clearContext();
              managed.activeSlot = 0;
              managed.preparedCtxWords = undefined;
            }
          }).catch(() => {});
        }
        return okResponse();
      }

      case OP_KERNEL_SUBMIT:
      case OP_KERNEL_SUBMIT_PREPARED: {
        const isPrep = op === OP_KERNEL_SUBMIT_PREPARED;
        const minLen = isPrep ? 8 : 7;
        if (req.length < minLen) {
          return errResponse(ERR_HOST, "Truncated KERNEL_SUBMIT");
        }
        const managed = isPrep
          ? this.#getKernel(req[3] >>> 0, req[5], req[6])
          : this.#getKernel(req[3] >>> 0, req[4], req[5]);
        if (!managed) {
          return errResponse(ERR_INVALID_HANDLE, "Invalid kernel handle");
        }
        const requiredSlot = isPrep ? (req[4] >>> 0) : undefined;
        const itemCount = (isPrep ? req[7] : req[6]) >>> 0;
        const payload = new Uint32Array(req.subarray(minLen));
        const jobId = this.#nextJobId++;
        const state: KernelJobState = {
          done: false,
          ok: false,
          promise: Promise.resolve(),
        };
        state.promise = this.#executeKernelBatch(
          managed,
          itemCount,
          payload,
          requiredSlot,
        ).then(
          (words) => {
            state.done = true;
            state.ok = true;
            state.words = words;
          },
          (err) => {
            const mapped = mapKernelError(err);
            state.done = true;
            state.ok = false;
            state.errCode = mapped.code;
            state.errMsg = mapped.message;
          },
        );
        this.#jobs.set(jobId, state);
        return okResponse([jobId]);
      }

      case OP_KERNEL_POLL: {
        if (req.length < 4) {
          return errResponse(ERR_HOST, "Truncated KERNEL_POLL");
        }
        const jobId = req[3] >>> 0;
        const job = this.#jobs.get(jobId);
        if (!job) return errResponse(ERR_INVALID_HANDLE, "Unknown kernel job");
        if (!job.done) {
          // Yield a microtask so already-settled inline promises become visible
          await Promise.resolve();
        }
        if (!job.done) return okResponse([0]);
        this.#jobs.delete(jobId);
        if (job.ok && job.words) {
          const out = new Uint32Array(1 + job.words.length);
          out[0] = 1;
          out.set(job.words, 1);
          return okResponse(out);
        }
        const msg = job.errMsg ? encodeText(job.errMsg) : new Uint32Array(0);
        const out = new Uint32Array(2 + msg.length);
        out[0] = 2;
        out[1] = job.errCode ?? ERR_HOST;
        out.set(msg, 2);
        return okResponse(out);
      }

      case OP_KERNEL_AWAIT: {
        if (req.length < 4) {
          return errResponse(ERR_HOST, "Truncated KERNEL_AWAIT");
        }
        const jobId = req[3] >>> 0;
        const job = this.#jobs.get(jobId);
        if (!job) return errResponse(ERR_INVALID_HANDLE, "Unknown kernel job");
        await job.promise;
        this.#jobs.delete(jobId);
        if (job.ok && job.words) {
          return okResponse(job.words);
        }
        return errResponse(job.errCode ?? ERR_HOST, job.errMsg ?? "");
      }

      case OP_PROC_SPAWN: {
        if (req.length < 6) {
          return errResponse(ERR_PROC_HOST, "Truncated PROC_SPAWN");
        }
        const procIdx = req[3] >>> 0;
        const manifest = this.#processesManifests[procIdx];
        if (
          !manifest ||
          computeProcessBindingHash(manifest) !== u64FromWords(req[4], req[5])
        ) {
          return errResponse(ERR_PROC_INVALID_HANDLE, "Invalid process handle");
        }
        try {
          const scheduler = this.#ensureProcesses();
          const cfgVal = wordsToProcessValue(
            manifest.configSchema,
            req.subarray(6),
          );
          const handle = scheduler.admit(manifest.name, cfgVal);
          if (!handle) {
            return errResponse(
              ERR_PROC_HOST,
              "Process admission rejected (slots or mailbox full)",
            );
          }
          // Drive init deterministically so the spawned process is immediately ready
          await scheduler.advance(1024);
          if (scheduler.status(handle) !== "ready") {
            return errResponse(
              ERR_PROC_FAILED,
              "Process initialization failed",
            );
          }
          this.#managedProcesses.set(
            this.#procKey(handle.endpoint, handle.epoch),
            { handle, manifest, completedEvents: new Map() },
          );
          return okResponse([handle.endpoint, handle.epoch]);
        } catch (err) {
          return errResponse(
            ERR_PROC_HOST,
            err instanceof Error ? err.message : String(err),
          );
        }
      }

      case OP_PROC_CALL: {
        if (req.length < 5) {
          return errResponse(ERR_PROC_HOST, "Truncated PROC_CALL");
        }
        const key = this.#procKey(req[3], req[4]);
        const proc = this.#managedProcesses.get(key);
        if (!proc || !this.#processesScheduler) {
          return errResponse(
            ERR_PROC_INVALID_HANDLE,
            "Unknown or closed process handle",
          );
        }
        try {
          const cmdVal = wordsToProcessValue(
            proc.manifest.cmdSchema,
            req.subarray(5),
          );
          const ticket = this.#processesScheduler.send(proc.handle, cmdVal);
          if (typeof ticket !== "number") {
            return errResponse(
              ERR_PROC_HOST,
              `Process send rejected: ${ticket}`,
            );
          }
          for (let guard = 0; guard < 1024; guard++) {
            this.#drainInto(proc);
            const hit = proc.completedEvents.get(ticket);
            if (hit) {
              proc.completedEvents.delete(ticket);
              if (hit.status === "done") {
                return okResponse(
                  processValueToWords(proc.manifest.replySchema, hit.value),
                );
              }
              return errResponse(
                hit.status === "cancelled"
                  ? ERR_PROC_CANCELLED
                  : ERR_PROC_FAILED,
                `Process turn ${hit.status}`,
              );
            }
            const progressed = await this.#processesScheduler.advance(16);
            this.#drainInto(proc);
            const hitAfter = proc.completedEvents.get(ticket);
            if (hitAfter) {
              proc.completedEvents.delete(ticket);
              if (hitAfter.status === "done") {
                return okResponse(
                  processValueToWords(
                    proc.manifest.replySchema,
                    hitAfter.value,
                  ),
                );
              }
              return errResponse(
                hitAfter.status === "cancelled"
                  ? ERR_PROC_CANCELLED
                  : ERR_PROC_FAILED,
                `Process turn ${hitAfter.status}`,
              );
            }
            if (progressed === 0) break;
          }
          return errResponse(ERR_PROC_FAILED, "Process did not complete turn");
        } catch (err) {
          return errResponse(
            ERR_PROC_HOST,
            err instanceof Error ? err.message : String(err),
          );
        }
      }

      case OP_PROC_SEND: {
        if (req.length < 5) {
          return errResponse(ERR_PROC_HOST, "Truncated PROC_SEND");
        }
        const key = this.#procKey(req[3], req[4]);
        const proc = this.#managedProcesses.get(key);
        if (!proc || !this.#processesScheduler) {
          return errResponse(
            ERR_PROC_INVALID_HANDLE,
            "Unknown or closed process handle",
          );
        }
        try {
          const cmdVal = wordsToProcessValue(
            proc.manifest.cmdSchema,
            req.subarray(5),
          );
          const ticket = this.#processesScheduler.send(proc.handle, cmdVal);
          if (typeof ticket !== "number") {
            return errResponse(
              ERR_PROC_HOST,
              `Process send rejected: ${ticket}`,
            );
          }
          return okResponse([ticket]);
        } catch (err) {
          return errResponse(
            ERR_PROC_HOST,
            err instanceof Error ? err.message : String(err),
          );
        }
      }

      case OP_PROC_POLL: {
        if (req.length < 6) {
          return errResponse(ERR_PROC_HOST, "Truncated PROC_POLL");
        }
        const key = this.#procKey(req[3], req[4]);
        const ticket = req[5] >>> 0;
        const proc = this.#managedProcesses.get(key);
        if (!proc) {
          return errResponse(
            ERR_PROC_INVALID_HANDLE,
            "Unknown or closed process handle",
          );
        }
        this.#drainInto(proc);
        const hit = proc.completedEvents.get(ticket);
        if (!hit) return okResponse([0]);
        proc.completedEvents.delete(ticket);
        if (hit.status === "done") {
          const replyWords = processValueToWords(
            proc.manifest.replySchema,
            hit.value,
          );
          const out = new Uint32Array(1 + replyWords.length);
          out[0] = 1;
          out.set(replyWords, 1);
          return okResponse(out);
        }
        const code = hit.status === "cancelled"
          ? ERR_PROC_CANCELLED
          : ERR_PROC_FAILED;
        return okResponse([2, code]);
      }

      case OP_PROC_ADVANCE: {
        if (req.length < 4) {
          return errResponse(ERR_PROC_HOST, "Truncated PROC_ADVANCE");
        }
        const budget = req[3] >>> 0;
        if (!this.#processesScheduler || budget === 0) return okResponse([0]);
        try {
          const completed = await this.#processesScheduler.advanceAllParallel(
            budget,
          );
          for (const proc of this.#managedProcesses.values()) {
            this.#drainInto(proc);
          }
          return okResponse([completed]);
        } catch (err) {
          const isOverrun = err instanceof Error &&
            err.name === "ProcessOverrunError";
          return errResponse(
            isOverrun ? ERR_PROC_OVERRUN : ERR_PROC_HOST,
            err instanceof Error ? err.message : String(err),
          );
        }
      }

      case OP_PROC_CLOSE: {
        if (req.length < 5) {
          return errResponse(ERR_PROC_HOST, "Truncated PROC_CLOSE");
        }
        const key = this.#procKey(req[3], req[4]);
        const proc = this.#managedProcesses.get(key);
        if (proc && this.#processesScheduler) {
          this.#managedProcesses.delete(key);
          await this.#processesScheduler.close(proc.handle).catch(() => {});
          this.#processesScheduler.release(proc.handle);
        }
        return okResponse();
      }

      default:
        return errResponse(ERR_HOST, `Unknown SRT1 runtime opcode ${op}`);
    }
  }

  /** Bind this runtime as an ABI 8 `Array U32 -> Array U32` async host capability. */
  capabilityAsync(guest: Guest): HostCapability {
    return guest.capabilityAsync({
      parameter: "Array U32",
      result: "Array U32",
      call: (packet) => this.handlePacket(packet),
    });
  }

  /** Run a Squid coordinator entrypoint (`entryName`) backed by this runtime. */
  async run(entryName = "main"): Promise<GuestValue | GuestOwner> {
    const guest = await instantiateGuest(this.#wasmBytes, {
      asynchronous: true,
    });
    try {
      const cap = this.capabilityAsync(guest);
      return await guest.callAsync(entryName, cap);
    } finally {
      guest.dispose();
    }
  }

  /** Shut down all kernel worker pools and isolated process instances. */
  async dispose(): Promise<void> {
    if (this.#disposed) return;
    this.#disposed = true;
    const tasks: Promise<unknown>[] = [];
    for (const managed of this.#managedKernels.values()) {
      tasks.push(
        managed.poolPromise.then((p) => p.close()).catch(() => {}),
      );
    }
    this.#managedKernels.clear();
    if (this.#processesScheduler) {
      for (const proc of this.#managedProcesses.values()) {
        tasks.push(
          this.#processesScheduler.close(proc.handle).catch(() => {}),
        );
      }
      this.#managedProcesses.clear();
      this.#processesScheduler = null;
    }
    await Promise.all(tasks);
  }
}

/** Create a SquidRuntime coordinator over a compiled Squid `.wasm` module. */
export function createRuntime(
  wasmBytes: Uint8Array,
  options: SquidRuntimeOptions = {},
): SquidRuntime {
  return new SquidRuntime(wasmBytes, options);
}
