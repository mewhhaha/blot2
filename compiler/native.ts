import {
  type Analysis,
  type AnalyzedArtifact,
  type AnalyzedArtifactOptions,
  type Artifact,
  type ArtifactOptions,
  type CompileOptions,
  includesAnalysis,
} from "./host.ts";
import type { SourceInput } from "./source_project.ts";
import { NativeProcess, type NativeProcessOptions } from "./native_process.ts";
import {
  decodeNativeResponse,
  type NativeOperation,
  NativeProtocolError,
} from "./native_protocol.ts";
import {
  createSourceFrontend,
  type SourceCompilerOptions,
} from "./source_frontend.ts";

export interface NativeCompilerOptions
  extends SourceCompilerOptions, NativeProcessOptions {}

export async function createNativeCompiler(
  options: NativeCompilerOptions = {},
) {
  const frontend = await createSourceFrontend(options);
  let process: NativeProcess;
  try {
    process = await NativeProcess.start(options);
  } catch (error) {
    frontend.dispose();
    throw error;
  }
  let closed = false;
  async function run(
    operation: NativeOperation,
    source: SourceInput,
    options: CompileOptions,
  ) {
    if (closed) throw new Error("Native compiler is disposed");
    const steps = options.const_steps ?? 10_000n;
    if (typeof steps !== "bigint" || steps < 0n || steps > 0xFFFFFFFFFFFFn) {
      throw new RangeError("const_steps must be a Nat (0..2^48-1)");
    }
    const prepared = await frontend.prepareNative(source);
    if (closed) throw new Error("Native compiler is disposed");
    try {
      const payload = prepared.encode(operation, steps);
      const response = decodeNativeResponse(await process.request(payload));
      if (response.operation !== operation) {
        await process.dispose();
        closed = true;
        frontend.dispose();
        throw new Error("Native compiler returned a different operation");
      }
      return response;
    } catch (error) {
      if (error instanceof NativeProtocolError) {
        closed = true;
        frontend.dispose();
        await process.dispose();
      }
      return prepared.translate(error);
    }
  }
  /**
   * Compiles `source` to Wasm. With `analysis: false` the native side skips
   * encoding the analysis and the artifact carries only the Wasm bytes.
   */
  function compile(
    source: SourceInput,
    options?: AnalyzedArtifactOptions,
  ): Promise<AnalyzedArtifact>;
  function compile(
    source: SourceInput,
    options?: ArtifactOptions,
  ): Promise<Artifact>;
  async function compile(
    source: SourceInput,
    options: ArtifactOptions = {},
  ): Promise<Artifact> {
    if (!includesAnalysis(options)) {
      const response = await run("emit", source, options);
      if (response.operation !== "emit") {
        throw new Error("Expected native Wasm");
      }
      return { bytes: response.bytes };
    }
    const response = await run("compile", source, options);
    if (response.operation !== "compile") {
      throw new Error("Expected native artifact");
    }
    return response.artifact;
  }
  return {
    async analyze(
      source: SourceInput,
      options: CompileOptions = {},
    ): Promise<Analysis> {
      const response = await run("analyze", source, options);
      if (response.operation !== "analyze") {
        throw new Error("Expected native analysis");
      }
      return response.analysis;
    },
    compile,
    async dispose() {
      if (!closed) {
        closed = true;
        frontend.dispose();
      }
      await process.dispose();
    },
  };
}
