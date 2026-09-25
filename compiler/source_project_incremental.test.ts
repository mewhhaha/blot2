import { deepStrictEqual as equal, ok, rejects } from "node:assert/strict";
import { createIncrementalCompiler } from "./incremental.ts";
import { createNativeIncrementalCompiler } from "./native_incremental.ts";
import { SourceError } from "./syntax.ts";

for (const backend of ["native", "javascript"] as const) {
  Deno.test(`${backend} single-file sessions reject unresolved imports without losing caches`, async () => {
    const compiler = backend === "native"
      ? await createNativeIncrementalCompiler({ prelude: "none" })
      : await createIncrementalCompiler({ prelude: "none" });
    try {
      const source = "entry const answer = fn () => 42\n";
      const previous = await compiler.compile(source);
      const invalid =
        '// keep the diagnostic local\nimport * as dependency from "./missing"\n' +
        source;
      await rejects(() => compiler.compile(invalid), (error) => {
        ok(error instanceof SourceError, String(error));
        equal(error.code, "module_loader_required");
        equal(error.start, invalid.indexOf("import"));
        return true;
      });
      const restored = await compiler.compile(source);
      equal(restored.artifact.bytes, previous.artifact.bytes);
      equal(restored.stats.declarations_lowered, 0);
      equal(restored.stats.groups_checked, 0);
      equal(restored.stats.entries_compiled, 0);
    } finally {
      await compiler.dispose();
    }
  });
}
