import {
  analyzeSourceTree,
  type CompileOptions,
  compileSourceTree,
} from "./host.ts";
import {
  createSourceFrontend,
  type SourceCompilerOptions,
} from "./source_frontend.ts";
import type { Cst } from "./syntax.ts";
import type { SourceInput } from "./source_project.ts";

export {
  declarationOffsets,
  formatDiagnostic,
  type SourceCompilerOptions,
} from "./source_frontend.ts";

// Synchronous JavaScript reference backend. User-facing native compilation is
// asynchronous and lives in native.ts.
export async function createSourceCompiler(
  options: SourceCompilerOptions = {},
) {
  const frontend = await createSourceFrontend(options);
  function run<T>(
    source: SourceInput,
    operation: (root: Cst, nodeCount: bigint, preludeRoot: Cst) => T,
  ): T {
    const prepared = frontend.prepare(source);
    try {
      return operation(prepared.root, prepared.nodeCount, prepared.prelude);
    } catch (error) {
      return prepared.translate(error);
    }
  }
  return {
    analyze(source: SourceInput, options: CompileOptions = {}) {
      return run(
        source,
        (root, count, prelude) =>
          analyzeSourceTree(root, count, prelude, options),
      );
    },
    compile(source: SourceInput, options: CompileOptions = {}) {
      return run(
        source,
        (root, count, prelude) =>
          compileSourceTree(root, count, prelude, options),
      );
    },
    dispose() {
      frontend.dispose();
    },
  };
}
