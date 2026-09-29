import {
  type Analysis,
  type AnalyzedArtifact,
  type AnalyzedArtifactOptions,
  analyzeSourceTree,
  type Artifact,
  type ArtifactOptions,
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
export interface SourceCompiler {
  analyze(source: SourceInput, options?: CompileOptions): Analysis;
  compile(
    source: SourceInput,
    options?: AnalyzedArtifactOptions,
  ): AnalyzedArtifact;
  compile(source: SourceInput, options?: ArtifactOptions): Artifact;
  dispose(): void;
}

export async function createSourceCompiler(
  options: SourceCompilerOptions = {},
): Promise<SourceCompiler> {
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
  function compile(
    source: SourceInput,
    options?: AnalyzedArtifactOptions,
  ): AnalyzedArtifact;
  function compile(source: SourceInput, options?: ArtifactOptions): Artifact;
  function compile(source: SourceInput, options: ArtifactOptions = {}) {
    return run(
      source,
      (root, count, prelude) =>
        compileSourceTree(root, count, prelude, options),
    );
  }
  return {
    analyze(source: SourceInput, options: CompileOptions = {}) {
      return run(
        source,
        (root, count, prelude) =>
          analyzeSourceTree(root, count, prelude, options),
      );
    },
    compile,
    dispose() {
      frontend.dispose();
    },
  };
}
