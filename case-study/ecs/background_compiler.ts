import {
  CompilationFailure,
  type CompiledGame,
  type CompileReply,
  type CompileRequest,
} from "./compile_protocol.ts";

/** Parsing and native IPC both live off the presentation event loop. */
export function createBackgroundCompiler(
  options: { readonly executable?: string } = {},
) {
  const worker = new Worker(new URL("./compile_worker.ts", import.meta.url), {
    type: "module",
  });
  const startup = Promise.withResolvers<void>();
  const stopped = Promise.withResolvers<void>();
  const pending = new Map<
    number,
    ReturnType<typeof Promise.withResolvers<CompiledGame>>
  >();
  let next = 0;
  let failure: Error | undefined;
  let closing: Promise<void> | undefined;
  let listening = false;
  const send = (request: CompileRequest) => worker.postMessage(request);
  // Observe initialization even when the owner closes before making a request.
  void startup.promise.catch(() => {});

  function fail(error: Error) {
    failure ??= error;
    startup.reject(error);
    for (const request of pending.values()) request.reject(error);
    pending.clear();
  }

  worker.onerror = (event) => {
    event.preventDefault();
    fail(new Error(`Compilation worker failed: ${event.message}`));
    stopped.resolve();
    worker.terminate();
  };
  worker.onmessageerror = () => {
    fail(new Error("Compilation worker returned an unreadable message"));
    send({ kind: "close" });
  };
  worker.onmessage = ({ data: reply }: MessageEvent<CompileReply>) => {
    if (reply.kind === "listening") {
      listening = true;
      send(
        closing || failure
          ? { kind: "close" }
          : { kind: "initialize", executable: options.executable },
      );
      return;
    }
    if (reply.kind === "ready") {
      startup.resolve();
      return;
    }
    if (reply.kind === "closed") {
      stopped.resolve();
      return;
    }
    if (closing || failure) return;
    const request = pending.get(reply.id);
    if (!request) {
      fail(new Error("Compilation worker returned an unknown revision"));
      send({ kind: "close" });
      return;
    }
    pending.delete(reply.id);
    if (reply.kind === "compiled") request.resolve(reply.compiled);
    else {
      const error = new CompilationFailure(reply.message, reply.diagnostic);
      if (!reply.diagnostic && reply.stack) error.stack = reply.stack;
      request.reject(error);
    }
  };

  return {
    async compile(
      source: string,
      filename = "game.blot",
    ): Promise<CompiledGame> {
      if (closing || failure) {
        throw failure ?? new Error("Background compiler is closed");
      }
      await startup.promise;
      if (closing || failure) {
        throw failure ?? new Error("Background compiler is closed");
      }
      const id = next++;
      const request = Promise.withResolvers<CompiledGame>();
      pending.set(id, request);
      try {
        send({ kind: "compile", id, source, filename });
      } catch (error) {
        pending.delete(id);
        request.reject(error);
      }
      return await request.promise;
    },
    close(): Promise<void> {
      if (closing) return closing;
      fail(new Error("Background compiler is closed"));
      closing = (async () => {
        if (listening) send({ kind: "close" });
        let timeout: ReturnType<typeof setTimeout> | undefined;
        try {
          await Promise.race([
            stopped.promise,
            new Promise<never>((_, reject) =>
              timeout = setTimeout(
                () =>
                  reject(
                    new Error(
                      "Compilation worker did not close within 5 seconds",
                    ),
                  ),
                5000,
              )
            ),
          ]);
        } finally {
          clearTimeout(timeout);
          worker.terminate();
        }
      })();
      return closing;
    },
  };
}
