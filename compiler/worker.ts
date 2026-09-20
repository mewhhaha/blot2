/// <reference lib="deno.worker" />

import { CompilerError } from "./host.ts";
import { type CompilerJob, executeJob } from "./pipeline.ts";

self.onmessage = (event: MessageEvent<{ id: number; job: CompilerJob }>) => {
  const { id, job } = event.data;
  try {
    self.postMessage({ id, value: executeJob(job) });
  } catch (error) {
    self.postMessage({
      id,
      error: error instanceof CompilerError
        ? {
          kind: "diagnostic",
          code: error.code,
          subject: error.subject,
          message: error.detail,
        }
        : {
          kind: "internal",
          message: error instanceof Error ? error.message : String(error),
          stack: error instanceof Error ? error.stack : undefined,
        },
    });
  }
};
self.postMessage({ ready: true });
