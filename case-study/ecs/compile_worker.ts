/// <reference lib="deno.worker" />

import { createNativeIncrementalCompiler } from "../../compiler/native_incremental.ts";
import { formatDiagnostic } from "../../compiler/source_frontend.ts";
import { SourceError } from "../../compiler/syntax.ts";
import type { CompileReply, CompileRequest } from "./compile_protocol.ts";

let initialized: ReturnType<typeof createNativeIncrementalCompiler> | undefined;
let closing = false;
const send = (reply: CompileReply) => self.postMessage(reply);
self.onmessage = async ({ data: request }: MessageEvent<CompileRequest>) => {
  if (request.kind === "initialize") {
    if (initialized || closing) {
      throw new Error("Invalid compiler initialization state");
    }
    initialized = createNativeIncrementalCompiler({
      threads: 1,
      executable: request.executable,
    });
    await initialized;
    if (!closing) send({ kind: "ready" });
    return;
  }
  if (request.kind === "close") {
    if (closing) return;
    closing = true;
    const compiler = await initialized;
    await compiler?.dispose();
    send({ kind: "closed" });
    self.close();
    return;
  }
  if (closing) return;
  try {
    const compiler = await initialized;
    if (!compiler) throw new Error("Compiler request preceded initialization");
    const compiled = await compiler.compileApp(request.source);
    if (!closing) send({ kind: "compiled", id: request.id, compiled });
  } catch (error) {
    if (!closing) {
      send({
        kind: "failed",
        id: request.id,
        diagnostic: error instanceof SourceError,
        message: error instanceof SourceError
          ? formatDiagnostic(request.filename, request.source, error)
          : error instanceof Error
          ? error.message
          : String(error),
        stack: error instanceof Error ? error.stack : undefined,
      });
    }
  }
};
send({ kind: "listening" });
