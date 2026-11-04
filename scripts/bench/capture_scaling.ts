// Bounded callback-capture transport probe. No compiler build is performed.
// deno run -A scripts/bench/capture_scaling.ts --compiler PATH
import { strict as assert } from "node:assert";
import { parseArgs } from "node:util";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const root = resolve(fileURLToPath(new URL("../..", import.meta.url)));
const { values } = parseArgs({
  args: Deno.args,
  options: {
    compiler: {
      type: "string",
      default: "zig-native/zig-out-native-dev/bin/blotc",
    },
    widths: { type: "string", default: "32,128" },
    captures: { type: "string", default: "1,4" },
    calls: { type: "string", default: "1,8" },
    owners: { type: "string", default: "shared,distinct" },
    reads: { type: "string", default: "one,all" },
    repetitions: { type: "string", default: "1" },
    "timeout-ms": { type: "string", default: "5000" },
    "budget-ms": { type: "string", default: "60000" },
    output: { type: "string", default: "build/bench/capture-scaling" },
  },
});

function numbers(input: string, maximum: number, name: string): number[] {
  const result = input.split(",").map(Number);
  assert(result.length > 0, `${name} is empty`);
  assert(
    result.every((value) =>
      Number.isInteger(value) && value >= 1 && value <= maximum
    ),
    name,
  );
  return result;
}
function choices<T extends string>(
  input: string,
  allowed: readonly T[],
  name: string,
): T[] {
  const result = input.split(",") as T[];
  assert(
    result.length > 0 && result.every((value) => allowed.includes(value)),
    name,
  );
  return result;
}
const widths = numbers(values.widths!, 128, "--widths");
const captures = numbers(values.captures!, 4, "--captures");
const calls = numbers(values.calls!, 8, "--calls");
const owners = choices(values.owners!, ["shared", "distinct"], "--owners");
const reads = choices(values.reads!, ["one", "all"], "--reads");
const repetitions = numbers(values.repetitions!, 9, "--repetitions")[0];
const timeoutMs = numbers(values["timeout-ms"]!, 5000, "--timeout-ms")[0];
const budgetMs = numbers(values["budget-ms"]!, 300000, "--budget-ms")[0];
const compilerPath = resolve(root, values.compiler!);
const requestedOutputRoot = resolve(root, values.output!);
await Deno.mkdir(requestedOutputRoot, { recursive: true });
const outputRoot = await Deno.makeTempDir({
  dir: requestedOutputRoot,
  prefix: "run-",
});

async function sha256(bytes: BufferSource): Promise<string> {
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))]
    .map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
const field = (index: number) => `f${String(index).padStart(3, "0")}`;

type OwnerMode = "shared" | "distinct";
type ReadMode = "one" | "all";
function sourceFor(
  width: number,
  captureCount: number,
  ownerMode: OwnerMode,
  readMode: ReadMode,
  callCount: number,
): string {
  const fields = Array.from(
    { length: width },
    (_, index) => `${field(index)}: Array U32`,
  );
  const lines = [
    `type Bundle is data = $Bundle {${fields.join(", ")}}`,
    "const checksum = func (bundle: Bundle): U32 => return do:",
    "  let result = 0",
  ];
  let readIndices = Array.from({ length: width }, (_, index) => index);
  if (readMode === "one") readIndices = [0];
  for (const index of readIndices) {
    lines.push(`  result := @u32.add self bundle.${field(index)}[0]`);
  }
  lines.push("  return result");

  const parameterTypes: string[] = [];
  for (let index = 0; index < captureCount; index++) {
    parameterTypes.push(`(callback_${index}: Unit -> U32 ! {})`);
  }
  lines.push(
    `const visit = func (bundle: Bundle) -> ${
      parameterTypes.join(" -> ")
    }: U32 => return do:`,
    "  let result = checksum bundle",
  );
  for (let index = 0; index < captureCount; index++) {
    lines.push(`  result := @u32.add self (callback_${index} ())`);
  }
  lines.push("  return result");
  lines.push("entry const answer = func (input: U32): U32 => return do:");
  lines.push("  let marker: Array U32 = #[0]", "  marker[0] := input");

  const bundleNames: string[] = [];
  let bundleCount = captureCount;
  if (ownerMode === "shared") bundleCount = 1;
  for (let owner = 0; owner < bundleCount; owner++) {
    const name = `base_${owner}`;
    bundleNames.push(name);
    const members: string[] = [];
    for (let index = 0; index < width; index++) {
      const value = owner * width + index;
      const arrayName = `owner_${owner}_${index}`;
      lines.push(`  let ${arrayName}: Array U32 = #[@u32.add input ${value}]`);
      members.push(`${field(index)}: ${arrayName}`);
    }
    lines.push(`  let ${name} = $Bundle {${members.join(", ")}}`);
  }
  const callbackNames: string[] = [];
  for (let index = 0; index < captureCount; index++) {
    const callbackName = `callback_${index}`;
    let baseIndex = index;
    if (ownerMode === "shared") baseIndex = 0;
    const baseName = bundleNames[baseIndex];
    callbackNames.push(callbackName);
    lines.push(
      `  let ${callbackName} = func (): U32 => return checksum ${baseName}`,
    );
  }
  let accumulated = "0";
  for (let index = 0; index < callCount; index++) {
    const name = `visit_${index}`;
    lines.push(
      `  let ${name} = visit ${bundleNames[0]} ${callbackNames.join(" ")}`,
    );
    const previous = `sum_${index}`;
    lines.push(`  let ${previous} = @u32.add ${accumulated} ${name}`);
    accumulated = previous;
  }
  lines.push(`  return ${accumulated}`);
  return lines.join("\n") + "\n";
}

function expected(
  width: number,
  captureCount: number,
  ownerMode: OwnerMode,
  readMode: ReadMode,
  callCount: number,
  input: number,
): number {
  let readWidth = width;
  if (readMode === "one") readWidth = 1;
  let total = Math.imul(readWidth, input) >>> 0;
  if (readMode === "all") total = (total + width * (width - 1) / 2) >>> 0;
  total = Math.imul(total, captureCount + 1) >>> 0;
  if (ownerMode === "distinct") {
    const ownerOffset = readWidth * width * captureCount * (captureCount - 1) /
      2;
    total = (total + ownerOffset) >>> 0;
  }
  return Math.imul(total, callCount) >>> 0;
}

const executable = resolve(compilerPath);
const compilerSha256 = await sha256(await Deno.readFile(executable));
const harnessSha256 = await sha256(
  await Deno.readFile(fileURLToPath(import.meta.url)),
);
const rows: Record<string, unknown>[] = [];
const started = performance.now();
let incomplete = false;
const requested = widths.length * captures.length * calls.length *
  owners.length * reads.length * repetitions;

caseLoop:
for (const width of widths) {
  for (const captureCount of captures) {
    for (const callCount of calls) {
      for (const ownerMode of owners) {
        for (const readMode of reads) {
          for (let repetition = 0; repetition < repetitions; repetition++) {
            if (performance.now() - started >= budgetMs) {
              incomplete = true;
              break caseLoop;
            }
            const name =
              `w${width}-c${captureCount}-n${callCount}-${ownerMode}-${readMode}-r${repetition}`;
            const directory = resolve(outputRoot, name);
            await Deno.mkdir(directory, { recursive: true });
            const entry = resolve(directory, "main.blot");
            const source = sourceFor(
              width,
              captureCount,
              ownerMode,
              readMode,
              callCount,
            );
            await Deno.writeTextFile(entry, source);
            const sourceSha256 = await sha256(new TextEncoder().encode(source));
            const row: Record<string, unknown> = {
              name,
              width,
              captures: captureCount,
              calls: callCount,
              ownerMode,
              readMode,
              repetition,
              sourceSha256,
              sourceBytes: new TextEncoder().encode(source).length,
              status: "incomplete",
            };
            let compiler:
              | Awaited<ReturnType<typeof createZigProjectCompiler>>
              | undefined;
            let guest: Awaited<ReturnType<typeof instantiateGuest>> | undefined;
            const caseStarted = performance.now();
            try {
              const remaining = Math.max(
                1,
                budgetMs - (performance.now() - started),
              );
              const deadline = Math.min(timeoutMs, remaining);
              compiler = await createZigProjectCompiler({
                executable,
                entry,
                prelude: null,
                cacheDirectory: false,
                codegenTier: "optimized",
                codegenWorkers: 1,
                frontendWorkers: 1,
                profileBackend: true,
                startupTimeoutMs: deadline,
              });
              const buildStarted = performance.now();
              const result = await compiler.build({
                sources: { [entry]: source },
                signal: AbortSignal.timeout(
                  Math.max(1, deadline - (buildStarted - caseStarted)),
                ),
              });
              row.buildMs = performance.now() - buildStarted;
              if (!result.success) {
                throw new Error(JSON.stringify(result.diagnostics));
              }
              row.wasmBytes = result.bytes.length;
              row.wasmSha256 = await sha256(result.bytes);
              await Deno.writeFile(
                resolve(directory, "main.wasm"),
                result.bytes,
              );
              row.stats = result.stats;
              const counters = result.stats.workCounters as
                | Record<string, unknown>
                | undefined;
              row.inputAliasWordsAvoided =
                counters?.scoped_input_alias_words_avoided ?? null;
              row.ownerGraphInputs = counters?.scoped_owner_graph_inputs ??
                null;
              row.packedPlansPromoted =
                counters?.scoped_packed_plans_promoted ?? null;
              guest = await instantiateGuest(result.bytes);
              assert.equal(guest.abi.version, 8);
              let checks = 0;
              for (const input of [0, 1, 17, 0xffffffff]) {
                const actual: unknown = guest.call("answer", input);
                const want = expected(
                  width,
                  captureCount,
                  ownerMode,
                  readMode,
                  callCount,
                  input,
                );
                assert.equal(actual, want, `${name}, input ${input}`);
                checks++;
              }
              row.executedChecks = checks;
              row.status = "passed";
            } catch (error) {
              row.error = String(error);
              row.status = "failed";
              incomplete = true;
            } finally {
              guest?.dispose();
              await compiler?.dispose();
            }
            row.coldMs = performance.now() - caseStarted;
            rows.push(row);
            await Deno.writeTextFile(
              resolve(outputRoot, "samples.jsonl"),
              `${JSON.stringify(row)}\n`,
              { append: true },
            );
            console.log(JSON.stringify({
              name,
              status: row.status,
              buildMs: row.buildMs,
              wasmBytes: row.wasmBytes,
              inputAliasWordsAvoided: row.inputAliasWordsAvoided,
              ownerGraphInputs: row.ownerGraphInputs,
              packedPlansPromoted: row.packedPlansPromoted,
              error: row.error,
            }));
            if (row.status !== "passed") break caseLoop;
          }
        }
      }
    }
  }
}

const completed = rows.filter((row) => row.status === "passed");
let status = "complete";
if (incomplete || rows.length !== requested) status = "incomplete";
const result = {
  workload: "callback-capture-input-alias-scaling-v1",
  status,
  outputRoot,
  compiler: executable,
  compilerSha256,
  harnessSha256,
  runtime: Deno.version,
  timeoutMs,
  budgetMs,
  requested,
  completed: completed.length,
  elapsedMs: performance.now() - started,
  executedChecks: completed.reduce(
    (sum, row) => sum + Number(row.executedChecks ?? 0),
    0,
  ),
  axes: { widths, captures, calls, owners, reads, repetitions },
  rows,
};
await Deno.writeTextFile(
  resolve(outputRoot, "result.json"),
  `${JSON.stringify(result, null, 2)}\n`,
);
if (status !== "complete") Deno.exitCode = 1;
