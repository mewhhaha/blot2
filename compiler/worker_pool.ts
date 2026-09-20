import { CompilerError } from "./host.ts";
import {
  type CheckedGroup,
  type CompilerJob,
  type EntryCode,
  executeJob,
} from "./pipeline.ts";

type JobResult = CheckedGroup | EntryCode;
interface Pending {
  readonly id: number;
  readonly job: CompilerJob;
  readonly resolve: (result: JobResult) => void;
  readonly reject: (error: Error) => void;
}

type Reply = { ready: true } | {
  id: number;
  value?: JobResult;
  error?: {
    kind: "diagnostic" | "internal";
    code: string;
    subject: string;
    message: string;
    stack?: string;
  };
};

export class CompilerWorkers {
  readonly #workers: Worker[] = [];
  readonly #idle: Worker[] = [];
  readonly #active = new Map<Worker, Pending>();
  readonly #queue: Pending[] = [];
  readonly #starting = new Map<Worker, (error: Error) => void>();
  #next = 0;
  #closed: Error | undefined;
  readonly ready: Promise<void>;

  constructor(readonly count: number) {
    if (!Number.isInteger(count) || count < 1 || count > 64) {
      throw new RangeError("workers must be an integer from 1 to 64");
    }
    // A single lane runs inline. More lanes use persistent isolated workers;
    // neither mode spawns a process or reloads the compiler per declaration.
    this.ready = Promise.all(
      Array.from(
        { length: count === 1 ? 0 : count },
        () =>
          new Promise<void>((resolve, reject) => {
            const worker = new Worker(new URL("./worker.ts", import.meta.url), {
              type: "module",
            });
            this.#workers.push(worker);
            this.#starting.set(worker, reject);
            worker.onerror = (event) => {
              event.preventDefault();
              const error = new Error(
                `Compiler worker failed: ${event.message}`,
              );
              reject(error);
              this.dispose(error);
            };
            worker.onmessageerror = () => {
              const error = new Error(
                "Compiler worker returned an unreadable term",
              );
              reject(error);
              this.dispose(error);
            };
            worker.onmessage = ({ data: reply }: MessageEvent<Reply>) => {
              if ("ready" in reply) {
                this.#starting.delete(worker);
                this.#idle.push(worker);
                resolve();
                this.#dispatch();
                return;
              }
              const pending = this.#active.get(worker);
              if (!pending || pending.id !== reply.id) {
                this.dispose(
                  new Error("Compiler worker returned the wrong job"),
                );
                return;
              }
              this.#active.delete(worker);
              this.#idle.push(worker);
              if (reply.error) {
                const error = reply.error.kind === "diagnostic"
                  ? new CompilerError(reply.error)
                  : new Error(reply.error.message);
                if (reply.error.stack) error.stack = reply.error.stack;
                pending.reject(error);
              } else if (reply.value) {
                pending.resolve(reply.value);
              } else {
                pending.reject(new Error("Compiler worker omitted its result"));
              }
              this.#dispatch();
            };
          }),
      ),
    ).then(() => {});
  }

  run(job: Extract<CompilerJob, { kind: "check" }>): Promise<CheckedGroup>;
  run(job: Extract<CompilerJob, { kind: "codegen" }>): Promise<EntryCode>;
  async run(job: CompilerJob): Promise<JobResult> {
    await this.ready;
    if (this.#closed) throw this.#closed;
    if (this.count === 1) return executeJob(job);
    return await new Promise<JobResult>((resolve, reject) => {
      this.#queue.push({ id: this.#next++, job, resolve, reject });
      this.#dispatch();
    });
  }

  #dispatch() {
    while (this.#idle.length && this.#queue.length && !this.#closed) {
      const worker = this.#idle.pop()!;
      const pending = this.#queue.shift()!;
      this.#active.set(worker, pending);
      try {
        worker.postMessage({ id: pending.id, job: pending.job });
      } catch (error) {
        this.dispose(error instanceof Error ? error : new Error(String(error)));
      }
    }
  }

  dispose(error = new Error("Compiler session is disposed")) {
    if (this.#closed) return;
    this.#closed = error;
    for (const reject of this.#starting.values()) reject(error);
    this.#starting.clear();
    for (const pending of [...this.#queue, ...this.#active.values()]) {
      pending.reject(error);
    }
    this.#queue.length = 0;
    this.#active.clear();
    this.#idle.length = 0;
    for (const worker of this.#workers) worker.terminate();
  }
}
