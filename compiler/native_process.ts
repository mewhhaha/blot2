import { fileURLToPath } from "node:url";
import {
  nativeProtocolMagic as magic,
  nativeProtocolMaxWords as maxWords,
  nativeProtocolVersion as version,
} from "./native_protocol.ts";

export interface NativeProcessOptions {
  readonly executable?: string | URL;
  readonly threads?: number;
  /**
   * `"normal"` (default): on Linux, blotc moves every thread that runs under
   * SCHED_IDLE, at a positive nice value, or in the idle IO class to
   * SCHED_OTHER, nice 0 and best-effort IO before it starts work (best
   * effort). `"inherit"` keeps the launcher's scheduling
   * (`--inherit-priority`). See compiler/README.md, "Scheduling".
   */
  readonly priority?: "normal" | "inherit";
}

// One process owns one ordered request stream. Concurrent callers are queued;
// no revision can consume another revision's response.
export class NativeProcess {
  readonly #child: Deno.ChildProcess;
  readonly #reader: ReadableStreamDefaultReader<Uint8Array<ArrayBuffer>>;
  readonly #writer: WritableStreamDefaultWriter<Uint8Array<ArrayBuffer>>;
  readonly #status: Promise<Deno.CommandStatus>;
  readonly #stderrDone: Promise<void>;
  #stderr = "";
  #exit: Deno.CommandStatus | undefined;
  #buffer = new Uint8Array(0);
  #position = 0;
  #queue: Promise<void> = Promise.resolve();
  #closed: Error | undefined;
  #closing: Promise<void> | undefined;

  private constructor(command: Deno.Command) {
    this.#child = command.spawn();
    this.#reader = this.#child.stdout.getReader();
    this.#writer = this.#child.stdin.getWriter();
    this.#status = this.#child.status.then((status) => {
      this.#exit = status;
      return status;
    });
    this.#stderrDone = this.#collectStderr();
  }

  /** Owned child identifier for diagnostic CPU/RSS measurements. */
  get pid(): number {
    return this.#child.pid;
  }

  static async start(options: NativeProcessOptions = {}) {
    const threads = options.threads ?? 1;
    if (!Number.isInteger(threads) || threads < 1 || threads > 64) {
      throw new RangeError("threads must be an integer from 1 to 64");
    }
    const priority = options.priority ?? "normal";
    if (priority !== "normal" && priority !== "inherit") {
      throw new RangeError('priority must be "normal" or "inherit"');
    }
    const executable = options.executable ??
      new URL("../generated/compiler/blotc", import.meta.url);
    const process = new NativeProcess(
      new Deno.Command(
        executable instanceof URL ? fileURLToPath(executable) : executable,
        {
          args: [
            "--threads",
            String(threads),
            ...priority === "inherit" ? ["--inherit-priority"] : [],
          ],
          // The owned compiler needs no ambient environment. In particular,
          // a desktop libxdo shim must not change its loader or require broad run permissions.
          clearEnv: true,
          stdin: "piped",
          stdout: "piped",
          stderr: "piped",
        },
      ),
    );
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      const greeting = await Promise.race([
        process.#readFrame(),
        new Promise<never>((_, reject) => {
          timer = setTimeout(
            () => reject(new Error("Native compiler startup timed out")),
            30_000,
          );
        }),
      ]);
      const words = new DataView(greeting.buffer);
      if (
        greeting.length !== 8 || words.getUint32(0, true) !== magic ||
        words.getUint32(4, true) !== version
      ) {
        throw new Error(
          "Native compiler protocol version mismatch; run just build",
        );
      }
      return process;
    } catch (error) {
      await process.dispose();
      throw process.#failure(error);
    } finally {
      clearTimeout(timer);
    }
  }

  async #collectStderr() {
    const decoder = new TextDecoder();
    for await (const chunk of this.#child.stderr) {
      this.#stderr = (this.#stderr + decoder.decode(chunk, { stream: true }))
        .slice(-65_536);
    }
    this.#stderr = (this.#stderr + decoder.decode()).slice(-65_536);
  }

  #failure(error: unknown): Error {
    const message = error instanceof Error ? error.message : String(error);
    const exit = this.#exit ? ` (exit ${this.#exit.code})` : "";
    return new Error(
      `Native compiler${exit}: ${message}${
        this.#stderr ? `\n${this.#stderr.trimEnd()}` : ""
      }`,
      { cause: error },
    );
  }

  async #readExact(length: number): Promise<Uint8Array<ArrayBuffer>> {
    const bytes = new Uint8Array(length);
    let written = 0;
    while (written < length) {
      if (this.#position === this.#buffer.length) {
        const next = await this.#reader.read();
        if (next.done) {
          throw new Error("Unexpected EOF in native compiler response");
        }
        this.#buffer = next.value;
        this.#position = 0;
      }
      const count = Math.min(
        length - written,
        this.#buffer.length - this.#position,
      );
      bytes.set(
        this.#buffer.subarray(this.#position, this.#position + count),
        written,
      );
      this.#position += count;
      written += count;
    }
    return bytes;
  }

  async #readFrame(): Promise<Uint8Array<ArrayBuffer>> {
    const header = await this.#readExact(4);
    const words = new DataView(header.buffer).getUint32(0, true);
    if (words > maxWords) {
      throw new Error("Native compiler response exceeds 64 MiB");
    }
    return await this.#readExact(words * 4);
  }

  request(payload: Uint8Array<ArrayBuffer>): Promise<Uint8Array<ArrayBuffer>> {
    if (payload.length % 4 || payload.length / 4 > maxWords) {
      return Promise.reject(
        new RangeError("Native request must contain at most 16M u32 words"),
      );
    }
    const snapshot = payload.slice();
    const operation = this.#queue.then(async () => {
      if (this.#closed) throw this.#closed;
      try {
        const header = new Uint8Array(4);
        new DataView(header.buffer).setUint32(0, snapshot.length / 4, true);
        await this.#writer.write(header);
        await this.#writer.write(snapshot);
        return await this.#readFrame();
      } catch (error) {
        await this.dispose();
        this.#closed = this.#failure(error);
        throw this.#closed;
      }
    });
    // A failed operation is returned to its caller; it must not leave an
    // unobserved rejection on the ordering chain.
    this.#queue = operation.then(() => {}, () => {});
    return operation;
  }

  dispose(): Promise<void> {
    if (this.#closing) return this.#closing;
    this.#closed ??= new Error("Native compiler is disposed");
    this.#closing = this.#stop();
    return this.#closing;
  }

  async #stop() {
    if (!this.#exit) {
      try {
        this.#child.kill("SIGTERM");
      } catch (error) {
        if (!(error instanceof Deno.errors.NotFound)) throw error;
      }
    }
    // Killing an owned subprocess can reject its pending pipe operations.
    // Those failures already reach request(); cleanup must still reap it.
    await Promise.allSettled([this.#writer.abort(), this.#reader.cancel()]);
    await this.#status;
    await this.#stderrDone;
    this.#writer.releaseLock();
    this.#reader.releaseLock();
  }
}
