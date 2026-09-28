/** Test-only adapter: run existing synchronous source tests through native Carp.
 * Every compile/analyze request is sent to the Carp executable. This module is
 * selected by an import map in run_suite.py; production source.ts is unchanged.
 */
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { constSteps, includesAnalysis } from "../../host_model.ts";
import type {
  Analysis,
  AnalyzedArtifact,
  AnalyzedArtifactOptions,
  Artifact,
  ArtifactOptions,
  CompileOptions,
} from "../../host_model.ts";
import {
  createSourceFrontend,
  type SourceCompilerOptions,
} from "../../source_frontend.ts";
import {
  decodeNativeResponse,
  encodeNativeRequest,
  type NativeOperation,
  nativeProtocolMagic,
  nativeProtocolMaxWords,
  nativeProtocolVersion,
} from "../../native_protocol.ts";
import type { SourceInput } from "../../source_project.ts";
export {
  declarationOffsets,
  formatDiagnostic,
  type SourceCompilerOptions,
} from "../../source_frontend.ts";

const executable = fileURLToPath(
  new URL("../../../generated/compiler/blotc", import.meta.url),
);

let executions = 0;
globalThis.addEventListener("unload", () => {
  if (executions) console.error(`CARP_SOURCE_EXECUTIONS=${executions}`);
});
export async function createSourceCompiler(
  options: SourceCompilerOptions = {},
) {
  const frontend = await createSourceFrontend(options);
  function run(
    operation: NativeOperation,
    source: SourceInput,
    options: CompileOptions,
  ) {
    const prepared = frontend.prepare(source);
    try {
      const payload = encodeNativeRequest({
        operation,
        root: prepared.root,
        prelude: prepared.prelude,
        fuel: prepared.nodeCount,
        const_steps: constSteps(options),
      });
      const input = new Uint8Array(payload.length + 4);
      new DataView(input.buffer).setUint32(0, payload.length / 4, true);
      input.set(payload, 4);
      const result = spawnSync(executable, ["--threads", "1"], {
        input,
        env: {},
        timeout: 120_000,
        maxBuffer: nativeProtocolMaxWords * 4 + 1024,
      });
      if (result.error) throw result.error;
      executions++;
      if (result.status !== 0) {
        throw new Error(
          `Carp process failed (${result.status}): ${result.stderr.toString()}`,
        );
      }
      const bytes = new Uint8Array(result.stdout);
      const view = new DataView(
        bytes.buffer,
        bytes.byteOffset,
        bytes.byteLength,
      );
      if (
        bytes.length < 16 || view.getUint32(0, true) !== 2 ||
        view.getUint32(4, true) !== nativeProtocolMagic ||
        view.getUint32(8, true) !== nativeProtocolVersion
      ) {
        throw new Error("invalid Carp handshake");
      }
      const length = view.getUint32(12, true) * 4;
      if (length > nativeProtocolMaxWords * 4 || bytes.length !== 16 + length) {
        throw new Error("invalid Carp response length");
      }
      const response = decodeNativeResponse(bytes.slice(16));
      if (response.operation !== operation) {
        throw new Error("unexpected Carp response operation");
      }
      return response;
    } catch (error) {
      return prepared.translate(error);
    }
  }
  function compile(
    source: SourceInput,
    options?: AnalyzedArtifactOptions,
  ): AnalyzedArtifact;
  function compile(source: SourceInput, options?: ArtifactOptions): Artifact;
  function compile(
    source: SourceInput,
    options: ArtifactOptions = {},
  ): Artifact {
    const response = run(
      includesAnalysis(options) ? "compile" : "emit",
      source,
      options,
    );
    if (response.operation === "analyze") {
      throw new Error("expected compiled artifact");
    }
    return response.operation === "emit"
      ? { bytes: response.bytes }
      : response.artifact;
  }
  return {
    analyze(source: SourceInput, options: CompileOptions = {}): Analysis {
      const response = run("analyze", source, options);
      if (response.operation !== "analyze") {
        throw new Error("expected analysis");
      }
      return response.analysis;
    },
    compile,
    dispose: () => frontend.dispose(),
  };
}
