import { type Guest, instantiateGuest, readGuestAbi } from "./guest.ts";

type Lanes = Uint32Array<ArrayBuffer> | Float32Array<ArrayBuffer>;
interface Slot {
  worker: Worker;
  pending?: { resolve: (reply: Reply) => void; reject: (error: Error) => void };
}
interface Reply {
  ready?: boolean;
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
  /** Immutable configuration words prefixed to every batch, including direct calls. */
  prefix?: Uint32Array;
  /** Worker wait cutoff. Direct recovery can take additional time. */
  waitMs?: number;
}

export class SparkPool {
  readonly #slots: Slot[] = [];
  readonly #prefix: Uint32Array<ArrayBuffer>;
  #attempt = 0;
  #busy = false;
  #closed = false;
  #width: number;
  #entry: string;
  #waitMs: number;
  #output: Uint32ArrayConstructor | Float32ArrayConstructor;
  #fallbacks = 0;

  get fallbacks(): number {
    return this.#fallbacks;
  }

  private constructor(
    private readonly guest: Guest,
    options: SparkOptions,
    prefix: Uint32Array<ArrayBuffer>,
  ) {
    this.#prefix = prefix;
    this.#width = options.width;
    this.#entry = options.entry;
    this.#waitMs = options.waitMs ?? 100;
    const result =
      guest.abi.functions.find((f) => f.name === options.entry)!.result;
    this.#output = Uint32Array;
    if (result === "Array F32") this.#output = Float32Array;
  }

  static async open(
    module: WebAssembly.Module,
    options: SparkOptions,
  ): Promise<SparkPool> {
    options = { ...options };
    const f = readGuestAbi(module).functions.find((f) =>
      f.name === options.entry
    );
    if (
      f?.parameter !== "Array U32" ||
      !["Array F32", "Array U32"].includes(String(f.result)) ||
      f.multiplicity === "once"
    ) throw new Error("Invalid spark batch signature");
    if (
      !Number.isSafeInteger(options.width) || options.width < 1 ||
      options.width > 16384 ||
      !Number.isSafeInteger(options.workers) || options.workers < 0 ||
      options.workers > 8 ||
      (options.prefix?.length ?? 0) > 16384 ||
      options.prefix?.buffer instanceof SharedArrayBuffer ||
      (options.waitMs !== undefined &&
        !(Number.isFinite(options.waitMs) && options.waitMs > 0))
    ) {
      throw new RangeError("Invalid spark pool configuration");
    }
    const prefix = new Uint32Array(options.prefix ?? []);
    const pool = new SparkPool(await instantiateGuest(module), options, prefix);
    try {
      await Promise.all(Array.from({ length: options.workers }, async () => {
        const slot: Slot = {
          worker: new Worker(
            new URL("./spark_worker.ts", import.meta.url).href,
            { type: "module" },
          ),
        };
        pool.#slots.push(slot);
        slot.worker.onmessage = ({ data }: MessageEvent<Reply>) => {
          const pending = slot.pending;
          if (!pending) return;
          slot.pending = undefined;
          if (data.error) pending.reject(new Error(data.error));
          else pending.resolve(data);
        };
        slot.worker.onerror = (e) => {
          e.preventDefault();
          pool.retireWorkers();
        };
        const reply = await pool.#ask(
          slot,
          { module, entry: options.entry },
          [],
          10000,
        );
        if (!reply.ready) {
          throw new Error("Worker did not acknowledge the compiled module");
        }
      }));
    } catch {
      pool.retireWorkers();
      pool.#fallbacks++;
    }
    return pool;
  }

  #ask(
    slot: Slot,
    message: object,
    transfer: Transferable[],
    timeout: number,
  ): Promise<Reply> {
    return new Promise((resolve, reject) => {
      const timer = setTimeout(
        () => reject(new Error("Spark wait expired")),
        timeout,
      );
      slot.pending = {
        resolve(reply) {
          clearTimeout(timer);
          resolve(reply);
        },
        reject(error) {
          clearTimeout(timer);
          reject(error);
        },
      };
      try {
        slot.worker.postMessage(message, transfer);
      } catch (error) {
        clearTimeout(timer);
        slot.pending = undefined;
        reject(error);
      }
    });
  }

  #packet(rows: Uint32Array): Uint32Array<ArrayBuffer> {
    const packet = new Uint32Array(this.#prefix.length + rows.length);
    packet.set(this.#prefix);
    packet.set(rows, this.#prefix.length);
    return packet;
  }

  #check(value: unknown, count: number): Lanes {
    if (
      !(value instanceof this.#output) || value.length !== count * this.#width
    ) {
      throw new Error("Spark result does not cover its assigned rows");
    }
    return value as Lanes;
  }

  direct(rows: Uint32Array): Lanes {
    if (this.#closed) throw new Error("Closed spark pool");
    this.#bound(rows);
    let input = rows;
    if (this.#prefix.length) input = this.#packet(rows);
    return this.#check(this.guest.call(this.#entry, input), rows.length);
  }

  #bound(rows: Uint32Array) {
    if (
      rows.length * this.#width > 4 * 1024 * 1024 ||
      rows.buffer instanceof SharedArrayBuffer
    ) {
      throw new RangeError(
        "Expected private input within the spark result limit",
      );
    }
  }

  async run(rows: Uint32Array): Promise<Lanes> {
    if (this.#closed || this.#busy) throw new Error("Spark pool unavailable");
    this.#bound(rows);
    const count = Math.min(rows.length, this.#slots.length);
    if (!count) return this.direct(rows);
    const saved = rows.slice();
    const output = new this.#output(rows.length * this.#width);
    const outputBits = new Uint32Array(output.buffer);
    const attempt = ++this.#attempt;
    this.#busy = true;
    try {
      await Promise.all(
        this.#slots.slice(0, count).map(async (slot, i) => {
          const start = Math.floor(i * saved.length / count);
          const end = Math.floor((i + 1) * saved.length / count);
          const input = this.#packet(saved.subarray(start, end));
          const reply = await this.#ask(slot, { attempt, start, input }, [
            input.buffer,
          ], this.#waitMs);
          if (
            reply.attempt !== attempt || reply.start !== start
          ) throw new Error("Stale spark reply");
          const values = this.#check(reply.values, end - start);
          // Copy raw lanes so signed zero and NaN payload bits survive assembly.
          outputBits.set(
            new Uint32Array(values.buffer, values.byteOffset, values.length),
            start * this.#width,
          );
        }),
      );
      return output;
    } catch {
      this.retireWorkers();
      this.#fallbacks++;
      return this.direct(saved);
    } finally {
      this.#busy = false;
    }
  }

  /** Retire the prepared generation and use its original direct kernel for recovery. */
  retireWorkers(): void {
    for (const slot of this.#slots.splice(0)) {
      slot.worker.terminate();
      slot.pending?.reject(new Error("Spark worker retired"));
      slot.pending = undefined;
    }
  }

  close(): void {
    this.retireWorkers();
    this.#closed = true;
    this.guest.dispose();
  }
}
