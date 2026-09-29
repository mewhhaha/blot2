import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { createNativeCompiler } from "./native.ts";
import { createNativeIncrementalCompiler } from "./native_incremental.ts";

Deno.test("native compiler diagnostics identify their owned processes without changing results", async () => {
  const compiler = await createNativeCompiler({ prelude: "none" });
  try {
    const session = await createNativeIncrementalCompiler({ prelude: "none" });
    try {
      const ids = [compiler.pid, session.pid];
      for (const id of ids) {
        ok(Number.isInteger(id) && id > 0 && id !== Deno.pid);
      }
      ok(ids[0] !== ids[1]);
      const source = "entry const answer = fn () => 42";
      const clean = await compiler.compile(source);
      const first = await session.compile(source);
      const cached = await session.compile(source);
      equal(clean.bytes, first.artifact.bytes);
      equal(clean.bytes, cached.artifact.bytes);
      equal(cached.stats.result_reused, true);
      equal([compiler.pid, session.pid], ids);
    } finally {
      await session.dispose();
    }
  } finally {
    await compiler.dispose();
  }
});
