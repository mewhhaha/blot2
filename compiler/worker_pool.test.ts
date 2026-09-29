import { deepStrictEqual as equal, rejects } from "node:assert/strict";
import { CompilerWorkers } from "./worker_pool.ts";
import { bendList, type CompilerJob } from "./pipeline.ts";

// Exercise a backlog large enough to compact the FIFO through real workers.
const emptyJob: Extract<CompilerJob, { kind: "check" }> = {
  kind: "check",
  module: {
    $: "model.Module",
    functions: bendList([]),
    constants: bendList([]),
    data_types: bendList([]),
    operations: bendList([]),
  },
  dependencies: bendList([]),
};

Deno.test("compiler worker FIFO settles every queued job and remains reusable", async () => {
  const workers = new CompilerWorkers(2);
  try {
    await workers.ready;
    const expected = await workers.run(emptyJob);
    const results = await Promise.all(
      Array.from({ length: 4096 }, () => workers.run(emptyJob)),
    );
    equal(results.length, 4096);
    for (const result of results) equal(result, expected);
    equal(await workers.run(emptyJob), expected);
  } finally {
    workers.dispose();
  }
});

Deno.test("compiler worker FIFO disposal rejects active and queued jobs without hanging", async () => {
  const workers = new CompilerWorkers(2);
  try {
    await workers.ready;
    const tasks = Array.from({ length: 4096 }, () => workers.run(emptyJob));
    const settled = Promise.all(tasks.map((task) => rejects(task, /disposed/)));
    // Let run() dispatch the first jobs and enqueue the remainder, but do not
    // give worker messages a turn before closing the pool.
    await Promise.resolve();
    workers.dispose();
    await settled;
    await rejects(workers.run(emptyJob), /disposed/);
  } finally {
    workers.dispose();
  }
});
