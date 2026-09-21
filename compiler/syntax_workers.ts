import type { EncodedSyntax } from "./compact_cst.ts";
import { SourceError } from "./syntax.ts";
import { sourceDeclarationRanges, type SourceRange } from "./source_ranges.ts";

export interface SyntaxJob {
  readonly source: string;
  readonly sourceBase: number;
}
export type SyntaxReply = { readonly kind: "ready" | "syntax" } | {
  readonly kind: "encoded";
  readonly syntax: EncodedSyntax;
};
interface Lane {
  readonly worker: Worker;
  readonly ready: Promise<void>;
  starting: ((error: Error) => void) | undefined;
  active?: {
    resolve: (syntax: EncodedSyntax | undefined) => void;
    reject: (error: Error) => void;
  };
}

export class SyntaxWorkers {
  readonly #lanes: Lane[] = [];
  #closed: Error | undefined;
  #queue: Promise<void> = Promise.resolve();

  constructor(readonly count: number) {
    if (!Number.isInteger(count) || count < 1 || count > 64) {
      throw new RangeError("threads must be an integer from 1 to 64");
    }
  }

  #lane(index: number): Lane {
    if (this.#closed) throw this.#closed;
    if (this.#lanes[index]) return this.#lanes[index];
    const worker = new Worker(new URL("./syntax_worker.ts", import.meta.url), {
      type: "module",
    });
    const ready = Promise.withResolvers<void>();
    const lane: Lane = { worker, ready: ready.promise, starting: ready.reject };
    worker.onerror = (event) => {
      event.preventDefault();
      this.dispose(new Error(`Syntax worker failed: ${event.message}`));
    };
    worker.onmessageerror = () =>
      this.dispose(new Error("Unreadable syntax worker reply"));
    worker.onmessage = ({ data: reply }: MessageEvent<SyntaxReply>) => {
      if (reply.kind === "ready" && lane.starting) {
        lane.starting = undefined;
        ready.resolve();
      } else if (reply.kind !== "ready" && lane.active) {
        const active = lane.active;
        lane.active = undefined;
        active.resolve(reply.kind === "encoded" ? reply.syntax : undefined);
      } else this.dispose(new Error("Unexpected syntax worker reply"));
    };
    this.#lanes.push(lane);
    return lane;
  }

  encode(
    source: string,
    sourceBase: number,
    local: (range: SourceRange) => EncodedSyntax,
  ) {
    const task = this.#queue.then(async () => {
      if (this.#closed) throw this.#closed;
      if (this.count === 1 || source.length < 32768) return undefined;
      const ranges = sourceDeclarationRanges(source);
      if (!ranges || ranges.length < 2) return undefined;
      // Include the caller in a bounded parser pool; additional native cores
      // remain available to Bend without paying for an isolate on every core.
      const count = Math.min(
        this.count,
        4,
        Math.ceil(source.length / 32768),
      );
      const cuts = [0];
      for (let lane = 1; lane < count; lane++) {
        const target = source.length * lane / count;
        const boundary = ranges.reduce(
          (nearest, range) =>
            Math.abs(range.end - target) < Math.abs(nearest - target)
              ? range.end
              : nearest,
          0,
        );
        if (boundary > cuts.at(-1)! && boundary < source.length) {
          cuts.push(boundary);
        }
      }
      if (cuts.length < 2) return undefined;
      cuts.push(source.length);
      const slices = cuts.slice(0, -1).map((start, index) => ({
        start,
        end: cuts[index + 1],
      }));
      const remote = Promise.all(
        slices.slice(1).map(async (range, index) => {
          let lane: Lane;
          try {
            lane = this.#lane(index);
          } catch (error) {
            this.dispose(
              error instanceof Error ? error : new Error(String(error)),
            );
            throw error;
          }
          const response = new Promise<EncodedSyntax | undefined>(
            (resolve, reject) => {
              lane.active = { resolve, reject };
              const job: SyntaxJob = {
                source: source.slice(range.start, range.end),
                sourceBase: sourceBase + range.start,
              };
              try {
                lane.worker.postMessage(job);
              } catch (error) {
                this.dispose(
                  error instanceof Error ? error : new Error(String(error)),
                );
              }
            },
          );
          return (await Promise.all([lane.ready, response]))[1];
        }),
      );
      // Workers accept queued jobs during initialization, overlapping cold
      // startup with the caller's own parse and encoding work.
      let first: EncodedSyntax | undefined;
      try {
        first = local(slices[0]);
      } catch (error) {
        if (!(error instanceof SourceError)) {
          this.dispose(
            error instanceof Error ? error : new Error(String(error)),
          );
          await Promise.allSettled([remote]);
          throw error;
        }
      }
      const chunks = [first, ...await remote];
      if (this.#closed) throw this.#closed;
      const encoded: EncodedSyntax[] = [];
      let declarations = false;
      for (const chunk of chunks) {
        if (!chunk || (declarations && chunk.hasImports)) return undefined;
        declarations ||= chunk.hasDeclarations;
        encoded.push(chunk);
      }
      return encoded;
    });
    this.#queue = task.then(() => {}, () => {});
    return task;
  }

  dispose(error = new Error("Syntax workers are disposed")) {
    if (this.#closed) return;
    this.#closed = error;
    for (const lane of this.#lanes) {
      lane.starting?.(error);
      lane.starting = undefined;
      lane.active?.reject(error);
      lane.active = undefined;
      lane.worker.terminate();
    }
  }
}
