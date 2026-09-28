// Test-only differential backend. An import map routes existing source tests
// here, while host.ts continues to call the unchanged JavaScript reference.
// We compare both results (or diagnostics) and return the actual Zig result, so
// guest/ABI tests execute Zig-produced Wasm rather than only checking a hash.
import { deepStrictEqual } from "node:assert";
import { spawnSync } from "node:child_process";
import {
  type Analysis,
  type AnalyzedArtifact,
  type AnalyzedArtifactOptions,
  analyzeSourceTree,
  type Artifact,
  type ArtifactOptions,
  type CompileOptions,
  compileSourceTree,
  constSteps,
  includesAnalysis,
} from "../compiler/host.ts";
import { CompilerError } from "../compiler/diagnostics.ts";
import {
  decodeNativeResponse,
  encodeNativeRequest,
  type NativeOperation,
  nativeProtocolMagic,
  nativeProtocolMaxWords,
  nativeProtocolVersion,
} from "../compiler/native_protocol.ts";
import {
  createSourceFrontend,
  type SourceCompilerOptions,
} from "../compiler/source_frontend.ts";
import type { SourceInput } from "../compiler/source_project.ts";

export {
  declarationOffsets,
  formatDiagnostic,
  type SourceCompilerOptions,
} from "../compiler/source_frontend.ts";

type Outcome<T> = { ok: true; value: T } | { ok: false; error: unknown };
function attempt<T>(operation: () => T): Outcome<T> {
  try {
    return { ok: true, value: operation() };
  } catch (error) {
    return { ok: false, error };
  }
}

function diagnostic(error: unknown) {
  if (error instanceof CompilerError) {
    return {
      name: error.name,
      code: error.code,
      subject: error.subject,
      detail: error.detail,
    };
  }
  if (error instanceof Error) {
    return { name: error.name, message: error.message };
  }
  return error;
}

function native(payload: Uint8Array, threads: number) {
  const input = new Uint8Array(payload.length + 4);
  new DataView(input.buffer).setUint32(0, payload.length / 4, true);
  input.set(payload, 4);
  // Native-process tests and this adapter deliberately share the same selected
  // executable. CI creates the symlink; the production default is not changed.
  const process = spawnSync("generated/compiler/blotc", [
    "--threads",
    String(threads),
  ], {
    input,
    env: {},
    timeout: 120_000,
    maxBuffer: nativeProtocolMaxWords * 4 + 16,
  });
  if (process.error) throw process.error;
  if (process.status !== 0) {
    throw new Error(
      `Zig exited with ${
        process.status ?? process.signal
      }: ${process.stderr.toString()}`,
    );
  }
  deepStrictEqual(process.stderr.length, 0, "compiler stdout/stderr isolation");
  const bytes = process.stdout;
  if (bytes.length < 16) throw new Error("truncated Zig response");
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  deepStrictEqual(
    [view.getUint32(0, true), view.getUint32(4, true), view.getUint32(8, true)],
    [2, nativeProtocolMagic, nativeProtocolVersion],
    "native handshake",
  );
  const count = view.getUint32(12, true);
  if (count > nativeProtocolMaxWords || bytes.length !== 16 + count * 4) {
    throw new Error("invalid Zig response frame length");
  }
  return decodeNativeResponse(new Uint8Array(bytes.subarray(16)));
}

export async function createSourceCompiler(
  options: SourceCompilerOptions = {},
) {
  const frontend = await createSourceFrontend(options);
  // Vary the worker count without an environment variable or a test-specific
  // native protocol extension. Each source operation compares against JS.
  let calls = 0;
  function run(
    operation: NativeOperation,
    source: SourceInput,
    options: ArtifactOptions,
  ) {
    const prepared = frontend.prepare(source);
    try {
      const reference = attempt(() =>
        operation === "analyze"
          ? analyzeSourceTree(
            prepared.root,
            prepared.nodeCount,
            prepared.prelude,
            options,
          )
          : compileSourceTree(
            prepared.root,
            prepared.nodeCount,
            prepared.prelude,
            options,
          )
      );
      const actual = attempt(() => {
        const nativeOperation =
          operation === "compile" && !includesAnalysis(options)
            ? "emit"
            : operation;
        const response = native(
          encodeNativeRequest({
            operation: nativeOperation,
            root: prepared.root,
            prelude: prepared.prelude,
            fuel: prepared.nodeCount,
            const_steps: constSteps(options),
          }),
          [1, 2, 4, 8][calls++ % 4],
        );
        deepStrictEqual(response.operation, nativeOperation);
        if (response.operation === "analyze") return response.analysis;
        if (response.operation === "compile") return response.artifact;
        return { bytes: response.bytes };
      });
      deepStrictEqual(
        actual.ok,
        reference.ok,
        `Zig/JS ${operation} acceptance mismatch: ${
          actual.ok ? "accepted" : String(actual.error)
        }`,
      );
      if (actual.ok && reference.ok) {
        deepStrictEqual(
          actual.value,
          reference.value,
          `Zig/JS ${operation} output mismatch`,
        );
        return actual.value;
      }
      if (!actual.ok && !reference.ok) {
        deepStrictEqual(
          diagnostic(actual.error),
          diagnostic(reference.error),
          `Zig/JS ${operation} diagnostic mismatch`,
        );
        throw actual.error;
      }
      throw new Error("unreachable differential outcome");
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
    return run("compile", source, options) as Artifact;
  }
  return {
    analyze(source: SourceInput, options: CompileOptions = {}): Analysis {
      return run("analyze", source, options) as Analysis;
    },
    compile,
    dispose() {
      frontend.dispose();
    },
  };
}
