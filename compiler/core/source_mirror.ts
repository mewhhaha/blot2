/** Test-only synchronous adapter: every semantic result must match the oracle.
 *
 * test_existing.py redirects the exact source.ts URL to this file in an
 * isolated workspace. The query suffix deliberately loads the unmodified
 * reference module without re-entering that import-map entry. Neither the
 * tests nor production modules nor generated Bend output are rewritten.
 *
 * The source API is synchronous, so this adapter uses one bounded native
 * subprocess per operation. Production uses the persistent asynchronous
 * NativeProcess API instead; these timings are NOT throughput benchmarks.
 */
import { deepStrictEqual, strictEqual } from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

import { includesAnalysis } from "../host.ts";
import type {
  Analysis,
  AnalyzedArtifact,
  AnalyzedArtifactOptions,
  Artifact,
  ArtifactOptions,
  CompileOptions,
} from "../host.ts";
import {
  decodeNativeResponse,
  encodeNativeRequest,
  type NativeOperation,
  nativeProtocolMagic,
  nativeProtocolMaxWords,
  nativeProtocolVersion,
} from "../native_protocol.ts";
import {
  createSourceFrontend,
  type SourceCompilerOptions,
} from "../source_frontend.ts";
import type { SourceInput } from "../source_project.ts";
import { createSourceCompiler as createReferenceCompiler } from "../source.ts?core-oracle";
export {
  declarationOffsets,
  formatDiagnostic,
  type SourceCompilerOptions,
} from "../source_frontend.ts";

const executable = fileURLToPath(
  new URL("../../generated/compiler/blotc", import.meta.url),
);
const threads = Number(Deno.env.get("BLOT_CORE_MIRROR_THREADS") ?? "1");
if (!Number.isInteger(threads) || threads < 1 || threads > 64) {
  throw new RangeError(
    "BLOT_CORE_MIRROR_THREADS must be an integer in [1,64]",
  );
}
const counts = {
  operations: 0,
  native_requests: 0,
  successes: 0,
  diagnostics: 0,
  mismatches: 0,
};
globalThis.addEventListener("unload", () => {
  console.log(`CORE_MIRROR ${JSON.stringify({ threads, ...counts })}`);
});

type Outcome<T> = { ok: true; value: T } | { ok: false; error: unknown };
function capture<T>(run: () => T): Outcome<T> {
  try {
    return { ok: true, value: run() };
  } catch (error) {
    return { ok: false, error };
  }
}
function diagnostic(error: unknown): unknown {
  if (!(error instanceof Error)) return error;
  // Stack traces name different implementations; all diagnostic fields count.
  return {
    name: error.name,
    message: error.message,
    ...Object.fromEntries(
      Object.entries(error).filter(([key]) => key !== "stack"),
    ),
  };
}
function compare<T>(reference: () => T, native: () => T, label: string): T {
  counts.operations++;
  const expected = capture(reference);
  const actual = capture(native);
  try {
    deepStrictEqual(
      actual.ok
        ? { ok: true, value: actual.value }
        : { ok: false, error: diagnostic(actual.error) },
      expected.ok
        ? { ok: true, value: expected.value }
        : { ok: false, error: diagnostic(expected.error) },
      `Native core/reference mismatch: ${label}`,
    );
  } catch (error) {
    // A negative test may catch any Error. Record failures independently so
    // the outer runner cannot accidentally count a swallowed mismatch as a pass.
    counts.mismatches++;
    console.error(`CORE_MISMATCH ${label}`);
    throw error;
  }
  if (actual.ok) {
    counts.successes++;
    return actual.value;
  }
  counts.diagnostics++;
  throw actual.error;
}

function request(payload: Uint8Array<ArrayBuffer>) {
  const input = new Uint8Array(payload.length + 4);
  new DataView(input.buffer).setUint32(0, payload.length / 4, true);
  input.set(payload, 4);
  counts.native_requests++;
  const result = spawnSync(executable, [
    "--threads",
    String(threads),
    "--inherit-priority",
  ], {
    input,
    env: {},
    timeout: 120_000,
    maxBuffer: nativeProtocolMaxWords * 4 + 1024,
  });
  if (result.error) throw result.error;
  strictEqual(
    result.status,
    0,
    `Native exit ${result.signal ?? result.status}: ${result.stderr}`,
  );
  const output = new Uint8Array(result.stdout);
  const view = new DataView(output.buffer);
  let offset = 0;
  function frame() {
    if (offset + 4 > output.length) {
      throw new Error("Missing native frame header");
    }
    const words = view.getUint32(offset, true);
    offset += 4;
    if (words > nativeProtocolMaxWords || words * 4 > output.length - offset) {
      throw new Error("Malformed native frame length");
    }
    const bytes = output.slice(offset, offset + words * 4);
    offset += bytes.length;
    return bytes;
  }
  const greeting = frame();
  strictEqual(greeting.length, 8, "Native handshake length");
  const header = new DataView(greeting.buffer);
  deepStrictEqual(
    [header.getUint32(0, true), header.getUint32(4, true)],
    [nativeProtocolMagic, nativeProtocolVersion],
    "Native handshake",
  );
  const response = frame();
  strictEqual(offset, output.length, "Trailing native output");
  return decodeNativeResponse(response);
}

export async function createSourceCompiler(
  options: SourceCompilerOptions = {},
) {
  const reference = await createReferenceCompiler(options);
  let frontend: Awaited<ReturnType<typeof createSourceFrontend>>;
  try {
    frontend = await createSourceFrontend(options);
  } catch (error) {
    reference.dispose();
    throw error;
  }
  function run(
    operation: NativeOperation,
    source: SourceInput,
    options: CompileOptions,
  ) {
    const steps = options.const_steps ?? 10_000n;
    if (typeof steps !== "bigint" || steps < 0n || steps > 0xFFFFFFFFFFFFn) {
      throw new RangeError("const_steps must be a Nat (0..2^48-1)");
    }
    const prepared = frontend.prepare(source);
    try {
      const result = request(encodeNativeRequest({
        ...prepared,
        operation,
        fuel: prepared.nodeCount,
        const_steps: steps,
      }));
      strictEqual(result.operation, operation, "Native operation");
      return result;
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
    return compare(() => reference.compile(source, options), () => {
      if (!includesAnalysis(options)) {
        const response = run("emit", source, options);
        if (response.operation !== "emit") throw new Error("Expected Wasm");
        return { bytes: response.bytes };
      }
      const response = run("compile", source, options);
      if (response.operation !== "compile") {
        throw new Error("Expected artifact");
      }
      return response.artifact;
    }, "compile");
  }
  return {
    analyze(source: SourceInput, options: CompileOptions = {}): Analysis {
      return compare(() => reference.analyze(source, options), () => {
        const response = run("analyze", source, options);
        if (response.operation !== "analyze") {
          throw new Error("Expected analysis");
        }
        return response.analysis;
      }, "analyze");
    },
    compile,
    dispose() {
      reference.dispose();
      frontend.dispose();
    },
  };
}
