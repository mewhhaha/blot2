// Bounded storage-bearing DAGs. Each reported build executes independent checks.
// deno run -A benchmarks/tools/storage_calls.ts --blotc PATH --sizes 1,4,8 --depth 10
import { resolve } from "node:path";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

export type Workload = "reader" | "writer";

export function storageCallSource(
  kind: Workload,
  repeats: number,
  depth: number,
): string {
  const lines: string[] = [];
  if (kind === "reader") {
    lines.push(
      "const stage_0 = func (rows: GrowArray U32) -> (index: U32): U32 => return @storage.read rows index",
    );
    for (let level = 1; level <= depth; level++) {
      lines.push(
        `const stage_${level} = func (rows: GrowArray U32) -> (index: U32): U32 => return`,
        `  @u32.add (stage_${level - 1} rows index) (stage_${
          level - 1
        } rows index)`,
      );
    }
  } else {
    lines.push(
      "const stage_0 = func (rows: GrowArray U32) -> (amount: U32): Unit => return do:",
      "  rows[0] := @u32.add rows[0] amount",
    );
    for (let level = 1; level <= depth; level++) {
      lines.push(
        `const stage_${level} = func (rows: GrowArray U32) -> (amount: U32): Unit => return do:`,
        `  stage_${level - 1} rows amount`,
        `  stage_${level - 1} rows (@u32.add amount 1)`,
      );
    }
  }
  lines.push(
    "entry const answer = func (input: U32) => return do:",
    "  let first: GrowArray U32 = #[input, @u32.add input 11]",
    "  let second: GrowArray U32 = #[@u32.add input 101, @u32.add input 211]",
    "  let index = @u32.rem input 2",
    "  let total: U32 = 0",
  );
  for (let call = 0; call < repeats; call++) {
    if (kind === "reader") {
      lines.push(
        `  total := @u32.add total (stage_${depth} first index)`,
        `  total := @u32.add total (stage_${depth} second index)`,
        "  first[index] := @u32.add first[index] 3",
      );
    } else {
      lines.push(
        `  stage_${depth} first (@u32.add input ${call})`,
        `  stage_${depth} second (@u32.add input ${call + 7})`,
        "  total := @u32.add total (@u32.add first[0] second[0])",
      );
    }
  }
  lines.push("  return #[total, first[0], first[1], second[0], second[1]]");
  return `${lines.join("\n")}\n`;
}

// Closed-form graph multiplicities, deliberately independent of source generation.
export function storageCallExpected(
  kind: Workload,
  repeats: number,
  depth: number,
  input: number,
): Uint32Array {
  const first = [input, (input + 11) >>> 0];
  const second = [(input + 101) >>> 0, (input + 211) >>> 0];
  const leaves = 2 ** depth;
  const extra = depth * leaves / 2;
  const index = input % 2;
  let total = 0;
  for (let call = 0; call < repeats; call++) {
    if (kind === "reader") {
      total = (total + leaves * (first[index] + second[index])) >>> 0;
      first[index] = (first[index] + 3) >>> 0;
    } else {
      first[0] = (first[0] + leaves * (input + call) + extra) >>> 0;
      second[0] = (second[0] + leaves * (input + call + 7) + extra) >>> 0;
      total = (total + first[0] + second[0]) >>> 0;
    }
  }
  return new Uint32Array([total, ...first, ...second]);
}

export function codeFunctionCount(bytes: Uint8Array): number {
  let at = 8;
  const leb = () => {
    let value = 0;
    let shift = 0;
    while (at < bytes.length) {
      const byte = bytes[at++];
      value += (byte & 127) * 2 ** shift;
      if ((byte & 128) === 0) return value;
      shift += 7;
      if (shift > 35) throw new Error("Invalid Wasm section length");
    }
    throw new Error("Truncated Wasm section");
  };
  while (at < bytes.length) {
    const id = bytes[at++];
    const length = leb();
    if (id === 10) return leb();
    at += length;
  }
  throw new Error("Wasm has no code section");
}

async function main() {
  const args = new Map<string, string>();
  for (let at = 0; at < Deno.args.length; at++) {
    const key = Deno.args[at];
    if (
      !["--blotc", "--sizes", "--depth", "--timeout-ms", "--workloads"]
        .includes(key)
    ) {
      throw new Error(`Unexpected argument ${key}`);
    }
    const value = Deno.args[++at];
    if (!value || value.startsWith("--")) {
      throw new Error(`${key} needs a value`);
    }
    args.set(key, value);
  }
  const repeats = (args.get("--sizes") ?? "1,4,8").split(",").map(Number);
  const depth = Number(args.get("--depth") ?? "10");
  const timeoutMs = Number(args.get("--timeout-ms") ?? "5000");
  const workloads = (args.get("--workloads") ?? "reader,writer").split(",");
  if (
    !repeats.length ||
    repeats.some((n) => !Number.isInteger(n) || n < 1 || n > 16)
  ) throw new Error("--sizes must be integers from 1 to 16");
  if (!Number.isInteger(depth) || depth < 1 || depth > 12) {
    throw new Error("--depth must be from 1 to 12");
  }
  if (!Number.isInteger(timeoutMs) || timeoutMs < 100 || timeoutMs > 5000) {
    throw new Error("--timeout-ms must be from 100 to 5000");
  }
  if (
    !workloads.length ||
    workloads.some((kind) => kind !== "reader" && kind !== "writer")
  ) throw new Error("--workloads must contain reader or writer");
  const repo = resolve(new URL("../..", import.meta.url).pathname);
  const blotc = resolve(
    args.get("--blotc") ?? `${repo}/compiler/zig-out-native-dev/bin/blotc`,
  );
  const hash = async (bytes: Uint8Array<ArrayBuffer>) =>
    [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map((
      byte,
    ) => byte.toString(16).padStart(2, "0")).join("");
  const compilerSha256 = await hash(await Deno.readFile(blotc));
  for (const kind of workloads as Workload[]) {
    for (const repeat of repeats) {
      const source = storageCallSource(kind, repeat, depth);
      const sourceSha256 = await hash(new TextEncoder().encode(source));
      const entry = `${repo}/build/bench/storage-call-profile.blot`;
      const started = performance.now();
      let compiler:
        | Awaited<ReturnType<typeof createZigProjectCompiler>>
        | undefined;
      let guest: Awaited<ReturnType<typeof instantiateGuest>> | undefined;
      try {
        compiler = await createZigProjectCompiler({
          executable: blotc,
          entry,
          stdRoot: `${repo}/std`,
          prelude: `${repo}/std/prelude.blot`,
          cacheDirectory: false,
          startupTimeoutMs: timeoutMs,
          profileBackend: true,
        });
        const buildStarted = performance.now();
        const result = await compiler.build({
          sources: { [entry]: source },
          signal: AbortSignal.timeout(timeoutMs),
        });
        const buildMs = performance.now() - buildStarted;
        if (!result.success) {
          throw new Error(JSON.stringify(result.diagnostics.slice(0, 2)));
        }
        guest = await instantiateGuest(result.bytes);
        for (const input of [0, 1, 7, 41, 0xfffffffd, 3, 0]) {
          const actual = guest.call("answer", input);
          const expected = storageCallExpected(kind, repeat, depth, input);
          if (
            !(actual instanceof Uint32Array) ||
            actual.length !== expected.length || actual.some((value, at) =>
              value !== expected[at]
            )
          ) {
            throw new Error(
              `answer(${input})=${String(actual)}; expected ${
                String(expected)
              }`,
            );
          }
        }
        console.log(
          JSON.stringify({
            status: "complete",
            workload: `storage_${kind}_dag`,
            repeats: repeat,
            depth,
            latency_ms: performance.now() - started,
            build_ms: buildMs,
            wasm_bytes: result.bytes.length,
            code_functions: codeFunctionCount(result.bytes),
            work_counters: result.stats.workCounters,
            phase_profile: result.stats.phaseProfile,
            backend_timing: result.stats.backendTiming,
            source_sha256: sourceSha256,
            compiler_sha256: compilerSha256,
          }),
        );
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        let status = "failed";
        if (/abort|timed out/i.test(message)) status = "timeout_incomplete";
        console.log(
          JSON.stringify({
            status,
            workload: `storage_${kind}_dag`,
            repeats: repeat,
            depth,
            latency_ms: performance.now() - started,
            timeout_ms: timeoutMs,
            error: message,
            source_sha256: sourceSha256,
            compiler_sha256: compilerSha256,
          }),
        );
        Deno.exitCode = 1;
      } finally {
        guest?.dispose();
        await compiler?.dispose();
      }
    }
  }
}

if (import.meta.main) await main();
