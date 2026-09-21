/// <reference lib="deno.worker" />
import { createFrontend, SourceError } from "./syntax.ts";
import type { SyntaxJob, SyntaxReply } from "./syntax_workers.ts";

// Worker event callbacks do not await async handlers. Surface rejected startup
// or encoding work through the parent's existing fatal-error channel.
self.onunhandledrejection = (event) => {
  event.preventDefault();
  queueMicrotask(() => {
    throw event.reason;
  });
};

const initialized = createFrontend().then((frontend) => {
  self.postMessage({ kind: "ready" } satisfies SyntaxReply);
  return frontend;
});
// Install before awaiting IO: cold callers may already have posted a job.
self.onmessage = async ({ data: job }: MessageEvent<SyntaxJob>) => {
  const frontend = await initialized;
  try {
    const syntax = frontend.encodePrepared(
      frontend.prepare(job.source),
      job.sourceBase,
    );
    self.postMessage({ kind: "encoded", syntax } satisfies SyntaxReply, [
      syntax.cst.words.buffer,
    ]);
  } catch (error) {
    if (!(error instanceof SourceError)) throw error;
    self.postMessage({ kind: "syntax" } satisfies SyntaxReply);
  }
};
