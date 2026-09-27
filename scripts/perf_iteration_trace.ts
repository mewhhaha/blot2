// Import-map boundary instrumentation; the compiler and gdev host stay unchanged.
import { createSourceCompiler as originalCompiler } from "perf/source-original";
import {
  createSourceProjectLoader as originalLoader,
  type SourceProject,
} from "perf/project-original";
export * from "perf/source-original";
export * from "perf/project-original";

export const trace = {
  project_ms: 0,
  setup_ms: 0,
  compile_ms: 0,
  compiles: 0,
  project: undefined as SourceProject | undefined,
};

export function resetTrace() {
  trace.project_ms =
    trace.setup_ms =
    trace.compile_ms =
    trace.compiles =
      0;
  trace.project = undefined;
}

export async function createSourceCompiler(
  ...args: Parameters<typeof originalCompiler>
) {
  const start = performance.now();
  const compiler = await originalCompiler(...args);
  trace.setup_ms += performance.now() - start;
  const compile = compiler.compile;
  compiler.compile = ((...input: Parameters<typeof compile>) => {
    const start = performance.now();
    trace.compiles++;
    try {
      return compile(...input);
    } finally {
      trace.compile_ms += performance.now() - start;
    }
  }) as typeof compile;
  return compiler;
}

export async function createSourceProjectLoader(
  ...args: Parameters<typeof originalLoader>
) {
  const start = performance.now();
  const loader = await originalLoader(...args);
  trace.project_ms += performance.now() - start;
  const load = loader.load;
  loader.load = async (...input: Parameters<typeof load>) => {
    const start = performance.now();
    try {
      return trace.project = await load(...input);
    } finally {
      trace.project_ms += performance.now() - start;
    }
  };
  return loader;
}
