import { dirname, resolve } from "node:path";
import type { EcsArtifact } from "../../compiler/host.ts";
import type {
  GuestReloadPlan,
  GuestRuntime,
  GuestWorld,
} from "../../compiler/guest_runtime.ts";
import type { CompiledGame } from "./compile_protocol.ts";

export interface LiveWorld {
  readonly artifact: EcsArtifact;
  readonly runtime: GuestRuntime;
  readonly world: GuestWorld;
}

export type ReloadEvent =
  | { readonly kind: "compiling"; readonly revision: number }
  | {
    readonly kind: "ready";
    readonly revision: number;
    readonly compiled: CompiledGame;
  }
  | {
    readonly kind: "published";
    readonly revision: number;
    readonly latency_ms: number;
    readonly compiled: CompiledGame;
  }
  | {
    readonly kind: "failed";
    readonly revision: number;
    readonly error: unknown;
  };

interface Revision {
  readonly number: number;
  readonly source: string;
  readonly filename: string;
  readonly started: number;
}
interface Candidate {
  readonly revision: Revision;
  readonly compiled: CompiledGame;
  readonly owner: GuestRuntime;
  readonly plan: GuestReloadPlan;
}

/** Latest edit wins; only a validated frame-boundary transition publishes. */
export function createCodeReload(options: {
  readonly current: () => LiveWorld;
  readonly compile: (source: string, filename: string) => Promise<CompiledGame>;
  readonly report: (event: ReloadEvent) => void;
}) {
  let revision = 0;
  let queued: Revision | undefined;
  let candidate: Candidate | undefined;
  let running: Promise<void> | undefined;
  let reading: Promise<void> | undefined;
  let watcher: Deno.FsWatcher | undefined;
  let watchDone: Promise<void> | undefined;
  let timer: ReturnType<typeof setTimeout> | undefined;
  let closed = false;

  function invalidate() {
    if (closed) throw new Error("Code reload is closed");
    candidate = undefined;
    queued = undefined;
    return ++revision;
  }

  async function compileQueued() {
    while (queued && !closed) {
      const edit = queued;
      queued = undefined;
      options.report({ kind: "compiling", revision: edit.number });
      try {
        const compiled = await options.compile(edit.source, edit.filename);
        if (closed || edit.number !== revision) continue;
        const owner = options.current().runtime;
        const plan = await owner.prepareReload(compiled.artifact);
        if (closed || edit.number !== revision) continue;
        candidate = { revision: edit, compiled, owner, plan };
        options.report({ kind: "ready", revision: edit.number, compiled });
      } catch (error) {
        if (!closed && edit.number === revision) {
          options.report({ kind: "failed", revision: edit.number, error });
        }
      }
    }
  }

  function enqueue(edit: Revision) {
    if (closed || edit.number !== revision) return;
    queued = edit;
    start();
  }

  function start() {
    if (!running) {
      running = compileQueued().finally(() => {
        running = undefined;
        if (queued && !closed) start();
      });
    }
  }

  function read(number: number, filename: string, started: number) {
    reading = (async () => {
      try {
        const source = await Deno.readTextFile(filename);
        enqueue({ number, source, filename, started });
      } catch (error) {
        if (!closed && number === revision) {
          options.report({ kind: "failed", revision: number, error });
        }
      }
    })();
    return reading;
  }

  return {
    request(source: string, filename = "game.blot"): number {
      const number = invalidate();
      enqueue({ number, source, filename, started: performance.now() });
      return number;
    },
    async refresh(filename: string): Promise<void> {
      const number = invalidate();
      await read(number, resolve(filename), performance.now());
    },
    /** undefined defers publication while platform resources are becoming ready. */
    publish(
      current: LiveWorld,
      validate: (candidate: LiveWorld) => LiveWorld | undefined,
    ): LiveWorld | undefined {
      const prepared = candidate;
      if (!prepared || closed) return undefined;
      try {
        if (current.runtime !== prepared.owner) {
          throw new Error("Reload candidate belongs to a superseded runtime");
        }
        const transferred = prepared.plan.apply(current.world);
        const next = validate({
          ...transferred,
          artifact: prepared.compiled.artifact,
        });
        if (!next) return undefined;
        candidate = undefined;
        options.report({
          kind: "published",
          revision: prepared.revision.number,
          latency_ms: performance.now() - prepared.revision.started,
          compiled: prepared.compiled,
        });
        return next;
      } catch (error) {
        candidate = undefined;
        options.report({
          kind: "failed",
          revision: prepared.revision.number,
          error,
        });
        return undefined;
      }
    },
    watch(filename: string): Promise<void> {
      if (watcher || closed) {
        throw new Error("Code watcher is already running or closed");
      }
      const path = resolve(filename);
      watcher = Deno.watchFs(dirname(path), { recursive: false });
      const active = watcher;
      watchDone = (async () => {
        for await (const event of active) {
          if (
            event.kind === "access" ||
            !event.paths.some((changed) => resolve(changed) === path)
          ) continue;
          const number = invalidate();
          const started = performance.now();
          clearTimeout(timer);
          timer = setTimeout(() => {
            timer = undefined;
            void read(number, path, started);
          }, 75);
        }
      })();
      return watchDone;
    },
    async idle() {
      await reading;
      await running;
    },
    async close() {
      if (!closed) {
        closed = true;
        clearTimeout(timer);
        watcher?.close();
        queued = undefined;
        candidate = undefined;
      }
      await Promise.all([watchDone, reading, running]);
    },
  };
}
