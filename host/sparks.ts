import { Worker } from "node:worker_threads";
import {
  type Guest,
  instantiateGuest,
  type NumericArrayCopySite,
  numericArrayCopySites,
  readGuestAbi,
} from "./guest.ts";

type Lanes = Uint32Array<ArrayBuffer> | Float32Array<ArrayBuffer>;

export type SparkCopySite =
  | NumericArrayCopySite
  | "prepare"
  | "install"
  | "snapshot"
  | "dispatch"
  | "assemble";

/** A shared allowance for numeric payload copies in a host frame. */
export class SparkCopyBudget {
  #reserved = 0;
  #outstanding = 0;
  #workers = 0;
  #linearBytes = 0;
  readonly #workerSlots: number;
  readonly #workerBytes: number;

  constructor(
    readonly ceiling: number,
    limits: { workers?: number; linearBytes?: number } = {},
  ) {
    this.#workerSlots = limits.workers ?? 8;
    this.#workerBytes = limits.linearBytes ?? 512 * 1024 * 1024;
    if (
      [ceiling, this.#workerSlots, this.#workerBytes].some((n) =>
        !Number.isSafeInteger(n) || n < 0
      )
    ) {
      throw new RangeError("Invalid spark copy or worker limit");
    }
  }

  get reserved(): number {
    return this.#reserved;
  }

  get workersInUse(): number {
    return this.#workers;
  }

  get workerLinearBytes(): number {
    return this.#linearBytes;
  }

  beginFrame(): void {
    this.#reserved = this.#outstanding;
  }

  reserve(bytes: number): (() => void) | undefined {
    if (!Number.isSafeInteger(bytes) || bytes < 0) {
      throw new RangeError("Invalid copy reservation");
    }
    if (bytes > this.ceiling - this.#reserved) return undefined;
    this.#reserved += bytes;
    this.#outstanding += bytes;
    let live = true;
    return () => {
      if (!live) return;
      this.#outstanding -= bytes;
      live = false;
    };
  }

  reserveWorkers(count: number, bytes: number): (() => void) | undefined {
    const total = count * bytes;
    if (
      !Number.isSafeInteger(count) || count < 0 ||
      !Number.isSafeInteger(total) || total < 0
    ) {
      throw new RangeError("Invalid spark worker reservation");
    }
    if (
      count > this.#workerSlots - this.#workers ||
      total > this.#workerBytes - this.#linearBytes
    ) {
      return undefined;
    }
    this.#workers += count;
    this.#linearBytes += total;
    let live = true;
    return () => {
      if (!live) return;
      this.#workers -= count;
      this.#linearBytes -= total;
      live = false;
    };
  }
}

interface Slot {
  worker: Worker;
  identity: number;
  copies: Uint32Array<SharedArrayBuffer>;
  exited: Promise<void>;
  pending?: { resolve: (reply: Reply) => void; reject: (error: Error) => void };
}

interface Reply {
  ready?: boolean;
  identity?: number;
  attempt?: number;
  start?: number;
  values?: Lanes;
  error?: string;
}

export interface SparkOptions {
  /** A registered independent batch entry. One U32 query produces width result words. */
  entry: string;
  width: number;
  workers: number;
  /** Immutable configuration words installed once per prepared worker. */
  prefix?: Uint32Array;
  /** Worker wait cutoff. Direct recovery can take additional time. */
  waitMs?: number;
  /** Includes preparation, worker attempts and direct guest transport. */
  copyBudget?: SparkCopyBudget;
}

let nextWorker = 1;

export class SparkPool {
  readonly #slots: Slot[] = [];
  #retiring?: Promise<void>;
  #finishWorkers?: () => void;
  #attempt = 0;
  #busy = false;
  #closed = false;
  #waitMs: number;
  #maxReturnPacketCopy = 0;
  #output: Uint32ArrayConstructor | Float32ArrayConstructor;
  #fallbacks = 0;
  #copies: Record<SparkCopySite, number> = {
    prepare: 0,
    install: 0,
    snapshot: 0,
    dispatch: 0,
    guestInput: 0,
    guestUnpack: 0,
    guestPack: 0,
    guestOutput: 0,
    assemble: 0,
  };

  get fallbacks(): number {
    return this.#fallbacks;
  }

  /** Worker copies join these totals after a reply or physical retirement. */
  get copiedBytes(): Readonly<Record<SparkCopySite, number>> {
    return { ...this.#copies };
  }

  private constructor(
    private readonly guest: Guest,
    private readonly options: SparkOptions,
    private readonly prefix: Uint32Array<ArrayBuffer>,
  ) {
    this.#waitMs = options.waitMs ?? 100;
    if (options.copyBudget) {
      this.#maxReturnPacketCopy = guest.numericPacketCapacity();
    }
    const result = guest.abi.functions.find((f) => f.name === options.entry)!
      .result;
    this.#output = Uint32Array;
    if (result === "Array F32") this.#output = Float32Array;
  }

  static async open(
    module: WebAssembly.Module,
    options: SparkOptions,
  ): Promise<SparkPool> {
    const { entry, width, prefix: source, waitMs, copyBudget } = options;
    let { workers } = options;
    const abi = readGuestAbi(module);
    const f = abi.functions.find((f) => f.name === entry);
    if (
      abi.version !== 8 || f?.parameter !== "Array U32" ||
      !["Array F32", "Array U32"].includes(String(f.result)) ||
      f.multiplicity === "once"
    ) throw new Error("Invalid spark batch signature");
    if (
      !Number.isSafeInteger(width) || width < 1 || width > 16384 ||
      !Number.isSafeInteger(workers) || workers < 0 || workers > 8 ||
      (source?.length ?? 0) > 16384 ||
      source?.buffer instanceof SharedArrayBuffer ||
      (waitMs !== undefined && !(Number.isFinite(waitMs) && waitMs > 0))
    ) throw new RangeError("Invalid spark pool configuration");

    const prefixBytes = source?.byteLength ?? 0;
    let finish = copyBudget?.reserve(prefixBytes * (workers + 1));
    if (copyBudget && !finish) {
      workers = 0;
      finish = copyBudget.reserve(prefixBytes);
      if (!finish) {
        throw new RangeError("Spark preparation exceeds copy allowance");
      }
    }
    let pool: SparkPool;
    try {
      const prefix = new Uint32Array(source ?? []);
      const guest = await instantiateGuest(module);
      pool = new SparkPool(guest, {
        entry,
        width,
        workers,
        waitMs,
        copyBudget,
      }, prefix);
      pool.#copies.prepare += prefixBytes;
      if (copyBudget && workers) {
        pool.#finishWorkers = copyBudget.reserveWorkers(
          workers,
          guest.memoryBytes(),
        );
        if (!pool.#finishWorkers) workers = 0;
      }
    } catch (error) {
      finish?.();
      throw error;
    }
    try {
      await Promise.all(
        Array.from({ length: workers }, () => pool.#prepare(module)),
      );
      finish?.();
    } catch {
      const retired = pool.retireWorkers();
      if (finish) void retired.then(finish);
      pool.#fallbacks++;
    }
    return pool;
  }

  async #prepare(module: WebAssembly.Module): Promise<void> {
    const copies = new Uint32Array(
      new SharedArrayBuffer(numericArrayCopySites.length * 4),
    );
    const worker = new Worker(new URL("./spark_worker.ts", import.meta.url));
    const exit = Promise.withResolvers<void>();
    const slot: Slot = {
      worker,
      identity: nextWorker++,
      copies,
      exited: exit.promise,
    };
    this.#slots.push(slot);
    worker.on("message", (data: unknown) => {
      const pending = slot.pending;
      if (!pending) return;
      slot.pending = undefined;
      if (!data || typeof data !== "object") {
        pending.reject(new Error("Malformed spark reply"));
        return;
      }
      const reply = data as Reply;
      if (reply.error) pending.reject(new Error(reply.error));
      else pending.resolve(reply);
    });
    worker.on("messageerror", () => void this.retireWorkers());
    worker.on("error", () => void this.retireWorkers());
    worker.once("exit", () => {
      exit.resolve();
      void this.retireWorkers();
    });
    const prefix = this.prefix.slice();
    this.#copies.install += prefix.byteLength;
    const reply = await this.#ask(
      slot,
      {
        module,
        entry: this.options.entry,
        identity: slot.identity,
        prefix,
        copies: slot.copies,
      },
      [prefix.buffer],
      10000,
    );
    if (!reply.ready || reply.identity !== slot.identity) {
      throw new Error("Worker did not acknowledge its preparation");
    }
  }

  #ask(
    slot: Slot,
    message: object,
    transfer: ArrayBuffer[],
    timeout: number,
  ): Promise<Reply> {
    const pending = Promise.withResolvers<Reply>();
    const timer = setTimeout(
      () => pending.reject(new Error("Spark wait expired")),
      timeout,
    );
    slot.pending = pending;
    try {
      slot.worker.postMessage(message, transfer);
    } catch (error) {
      pending.reject(error);
    }
    return pending.promise.finally(() => {
      clearTimeout(timer);
      if (slot.pending === pending) slot.pending = undefined;
    });
  }

  #check(value: unknown, count: number): Lanes {
    if (
      !(value instanceof this.#output) ||
      !(value.buffer instanceof ArrayBuffer) ||
      value.length !== count * this.options.width
    ) {
      throw new Error("Spark result does not cover its assigned rows");
    }
    return value as Lanes;
  }

  #direct(rows: Uint32Array): Lanes {
    if (this.#closed) throw new Error("Closed spark pool");
    return this.#check(
      this.guest.call(this.options.entry, rows, {
        prefix: this.prefix,
        resultLength: rows.length * this.options.width,
        observeCopy: (site, bytes) => this.#copies[site] += bytes,
      }),
      rows.length,
    );
  }

  direct(rows: Uint32Array): Lanes {
    this.#bound(rows);
    const budget = this.options.copyBudget;
    const finish = budget?.reserve(this.#directBytes(rows));
    if (budget && !finish) throw new RangeError("Spark exceeds copy allowance");
    try {
      return this.#direct(rows);
    } finally {
      finish?.();
    }
  }

  #bound(rows: Uint32Array) {
    if (
      !(rows instanceof Uint32Array) ||
      !(rows.buffer instanceof ArrayBuffer) ||
      rows.length * this.options.width > 4 * 1024 * 1024
    ) {
      throw new RangeError(
        "Expected private input within the spark result limit",
      );
    }
  }

  #directBytes(rows: Uint32Array): number {
    return 2 * (this.prefix.byteLength + rows.byteLength) +
      this.#maxReturnPacketCopy + rows.byteLength * this.options.width;
  }

  async run(rows: Uint32Array): Promise<Lanes> {
    if (this.#closed || this.#busy) throw new Error("Spark pool unavailable");
    this.#bound(rows);
    const slots = this.#slots.slice(0, rows.length);
    if (!slots.length) return this.direct(rows);
    const results = rows.length * this.options.width;
    // Snapshot, shard packing, host input and guest unpacking, worst-case
    // guest result packet, matching host output and ordered assembly.
    const workerCopies = 4 * rows.byteLength +
      slots.length *
        (2 * this.prefix.byteLength + this.#maxReturnPacketCopy) +
      8 * results;
    const budget = this.options.copyBudget;
    const finish = budget?.reserve(workerCopies + this.#directBytes(rows));
    if (budget && !finish) return this.direct(rows);

    let retired: Promise<void> | undefined;
    let live = true;
    this.#busy = true;
    try {
      const saved = rows.slice();
      this.#copies.snapshot += saved.byteLength;
      const output = new this.#output(results);
      const outputBits = new Uint32Array(output.buffer);
      const attempt = ++this.#attempt;
      for (const slot of slots) {
        for (const index of numericArrayCopySites.keys()) {
          Atomics.store(slot.copies, index, 0);
        }
      }
      try {
        await Promise.all(slots.map(async (slot, i) => {
          const start = Math.floor(i * saved.length / slots.length);
          const end = Math.floor((i + 1) * saved.length / slots.length);
          const input = saved.slice(start, end);
          this.#copies.dispatch += input.byteLength;
          const reply = await this.#ask(
            slot,
            {
              identity: slot.identity,
              attempt,
              start,
              input,
              resultLength: (end - start) * this.options.width,
            },
            [input.buffer],
            this.#waitMs,
          );
          if (
            !live || reply.identity !== slot.identity ||
            reply.attempt !== attempt || reply.start !== start
          ) throw new Error("Stale spark reply");
          const values = this.#check(reply.values, end - start);
          outputBits.set(
            new Uint32Array(values.buffer, values.byteOffset, values.length),
            start * this.options.width,
          );
          this.#copies.assemble += values.byteLength;
        }));
        return output;
      } catch {
        live = false;
        retired = this.retireWorkers();
        this.#fallbacks++;
        return this.#direct(saved);
      } finally {
        const record = () => {
          for (const slot of slots) {
            for (const [index, site] of numericArrayCopySites.entries()) {
              this.#copies[site] += Atomics.load(slot.copies, index);
            }
          }
        };
        if (retired) void retired.then(record);
        else record();
      }
    } finally {
      if (retired && finish) void retired.then(finish);
      else finish?.();
      this.#busy = false;
    }
  }

  /** Stop the prepared generation without waiting on the calling frame. */
  retireWorkers(): Promise<void> {
    if (this.#retiring) return this.#retiring;
    const slots = this.#slots.splice(0);
    const finish = this.#finishWorkers;
    this.#finishWorkers = undefined;
    this.#retiring = Promise.all(slots.map((slot) => slot.exited)).then(
      () => finish?.(),
    );
    for (const slot of slots) {
      slot.pending?.reject(new Error("Spark worker retired"));
      slot.pending = undefined;
      void slot.worker.terminate().catch(
        () => {/* Wait for the exit event. */},
      );
    }
    return this.#retiring;
  }

  close(): Promise<void> {
    const retired = this.retireWorkers();
    if (!this.#closed) {
      this.#closed = true;
      this.guest.dispose();
    }
    return retired;
  }
}
