// Small, executed controls for width × copies × ownership. No compiler build.
import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { parseArgs } from "node:util";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const kinds = [
  "scalar",
  "branch",
  "loop",
  "shared",
  "distinct",
  "shared-unit",
  "distinct-unit",
  "shared-read",
] as const;
type Kind = typeof kinds[number];
const { values } = parseArgs({
  options: {
    compiler: { type: "string", default: "zig-native/zig-out/bin/blotc" },
    widths: { type: "string", default: "8,32,128" },
    operations: { type: "string", default: "1,8,32" },
    kinds: { type: "string", default: "scalar,branch,loop,shared,distinct" },
    repetitions: { type: "string", default: "3" },
    "timeout-ms": { type: "string", default: "5000" },
    "budget-ms": { type: "string", default: "60000" },
    profile: { type: "boolean", default: false },
    output: { type: "string", default: "build/bench/aggregate-scaling" },
  },
});
function integer(text: string, maximum: number) {
  const number = Number(text);
  assert(Number.isInteger(number) && number >= 1 && number <= maximum, text);
  return number;
}
const widths = values.widths!.split(",").map((n) => integer(n, 256));
const operations = values.operations!.split(",").map((n) => integer(n, 128));
const selected = values.kinds!.split(",") as Kind[];
assert(selected.every((kind) => kinds.includes(kind)));
const repetitions = integer(values.repetitions!, 9);
const timeoutMs = integer(values["timeout-ms"]!, 5000);
const budgetMs = integer(values["budget-ms"]!, 300000);
const executable = resolve(values.compiler!);
const field = (index: number) => `f${String(index).padStart(3, "0")}`;
const encode = (source: string) => new TextEncoder().encode(source);
async function hash(bytes: Uint8Array<ArrayBuffer>) {
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))]
    .map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
function sourceFor(kind: Kind, width: number, count: number) {
  const owned = kind.startsWith("shared") || kind.startsWith("distinct");
  const unit = kind.endsWith("-unit");
  const lines = ["const step = func row -> (flag: U32) => return do:"];
  if (owned) {
    if (kind !== "shared-read") lines.push("  row.f000[0] := @u32.add self 1");
    if (unit) lines.push("  return ()");
    else lines.push("  return row");
  } else if (kind === "branch") {
    lines.push(
      "  return if @u32.eq flag 0 then row else @record.merge row {f000: @u32.add row.f000 1}",
    );
  } else {
    lines.push("  return @record.merge row {f000: @u32.add row.f000 1}");
  }
  lines.push("const checksum = func row: U32 => return do:", "  let sum = 0");
  for (let index = 0; index < width; index++) {
    let read = `row.${field(index)}`;
    if (owned) read += "[0]";
    lines.push(`  sum := @u32.add self ${read}`);
  }
  lines.push(
    "  return sum",
    "entry const answer = func (input: U32): Array U32 => return do:",
  );
  // The identical indexed marker selects the owned backend for scalar controls.
  lines.push("  let marker: Array U32 = #[0]", "  marker[0] := input");
  if (kind.startsWith("shared")) {
    lines.push("  let values: Array U32 = #[input]");
  }
  if (kind.startsWith("distinct")) {
    for (let index = 0; index < width; index++) {
      lines.push(
        `  let values_${index}: Array U32 = #[@u32.add input ${index}]`,
      );
    }
  }
  const members: string[] = [];
  for (let index = 0; index < width; index++) {
    let value = `@u32.add input ${index}`;
    if (kind.startsWith("shared")) value = "values";
    if (kind.startsWith("distinct")) value = `values_${index}`;
    members.push(`${field(index)}: ${value}`);
  }
  lines.push(`  let row_0 = {${members.join(", ")}}`);
  let result = `row_${count}`;
  if (kind === "loop") {
    lines.push(
      "  let current = row_0",
      `  for index in 0 .. ${count}:`,
      "    current := @record.merge self {f000: @u32.add self.f000 1}",
    );
    result = "current";
  } else {
    for (let index = 0; index < count; index++) {
      if (unit) lines.push("  step row_0 (@u32.rem input 2)");
      else {lines.push(
          `  let row_${index + 1} = step row_${index} (@u32.rem input 2)`,
        );}
    }
    if (unit) result = "row_0";
  }
  lines.push(`  return #[checksum ${result}, marker[0]]`);
  return lines.join("\n") + "\n";
}
function expected(kind: Kind, width: number, count: number, input: number) {
  let sum = Math.imul(width, input) >>> 0;
  if (!kind.startsWith("shared")) sum = (sum + width * (width - 1) / 2) >>> 0;
  let increment = count;
  if (kind.startsWith("shared")) increment *= width;
  if (kind === "shared-read") increment = 0;
  if (kind === "branch" && input % 2 === 0) increment = 0;
  return new Uint32Array([(sum + increment) >>> 0, input]);
}
type Sample = {
  kind: Kind;
  width: number;
  operations: number;
  repetition: number;
  status: string;
  [key: string]: unknown;
};
const parent = resolve(values.output!);
await Deno.mkdir(parent, { recursive: true });
const output = await Deno.makeTempDir({ dir: parent, prefix: "run-" });
const compilerSha256 = await hash(await Deno.readFile(executable));
const samples: Sample[] = [];
const start = performance.now();
let incomplete = false;
for (const width of widths) {
  for (const count of operations) {
    for (const kind of selected) {
      const name = `${kind}-w${width}-n${count}`;
      const entry = `${output}/${name}.blot`;
      const source = sourceFor(kind, width, count);
      await Deno.writeTextFile(entry, source);
      const sourceSha256 = await hash(encode(source));
      for (let repetition = 0; repetition < repetitions; repetition++) {
        if (performance.now() - start >= budgetMs) {
          incomplete = true;
          break;
        }
        const sample: Sample = {
          kind,
          width,
          operations: count,
          repetition,
          status: "incomplete",
          sourceSha256,
          sourceBytes: encode(source).length,
          sourceLines: source.trimEnd().split("\n").length,
        };
        let compiler:
          | Awaited<ReturnType<typeof createZigProjectCompiler>>
          | undefined;
        const coldStart = performance.now();
        try {
          compiler = await createZigProjectCompiler({
            executable,
            entry,
            prelude: null,
            cacheDirectory: false,
            codegenTier: "optimized",
            codegenWorkers: 1,
            frontendWorkers: 1,
            profileBackend: values.profile,
            startupTimeoutMs: timeoutMs,
          });
          const buildStart = performance.now();
          sample.startupMs = buildStart - coldStart;
          sample.compilerIdentity = compiler.compilerIdentity;
          const result = await compiler.build({
            signal: AbortSignal.timeout(
              Math.max(1, timeoutMs - (buildStart - coldStart)),
            ),
            sources: { [entry]: source },
          });
          sample.buildMs = performance.now() - buildStart;
          sample.coldMs = performance.now() - coldStart;
          if (!result.success) {
            throw new Error(JSON.stringify(result.diagnostics));
          }
          sample.wasmBytes = result.bytes.length;
          sample.wasmSha256 = await hash(result.bytes);
          sample.stats = result.stats;
          if (repetition === 0) {
            await Deno.writeFile(`${output}/${name}.wasm`, result.bytes);
          }
          let checks = 0;
          for (const asynchronous of [false, true]) {
            const guest = await instantiateGuest(result.bytes, {
              asynchronous,
            });
            try {
              assert.equal(guest.abi.version, 8);
              for (const input of [0, 1, 17, 0xffffffff, 0]) {
                let actual: unknown;
                if (asynchronous) {
                  actual = await guest.callAsync("answer", input);
                } else actual = guest.call("answer", input);
                assert.deepEqual(
                  actual,
                  expected(kind, width, count, input),
                  `${name}, input ${input}`,
                );
                checks++;
              }
            } finally {
              guest.dispose();
            }
          }
          sample.executedChecks = checks;
          sample.status = "passed";
        } catch (error) {
          sample.error = String(error);
          sample.status = "failed";
          incomplete = true;
        } finally {
          await compiler?.dispose();
        }
        samples.push(sample);
        await Deno.writeTextFile(
          `${output}/samples.jsonl`,
          JSON.stringify(sample) + "\n",
          { append: true },
        );
        console.log(
          JSON.stringify({
            kind,
            width,
            operations: count,
            repetition,
            status: sample.status,
            buildMs: sample.buildMs,
            wasmBytes: sample.wasmBytes,
            error: sample.error,
          }),
        );
        if (sample.status !== "passed") break;
      }
      if (performance.now() - start >= budgetMs) break;
    }
    if (performance.now() - start >= budgetMs) break;
  }
  if (performance.now() - start >= budgetMs) break;
}
const median = (values: number[]) =>
  values.sort((a, b) => a - b)[Math.floor(values.length / 2)];
const summaries = [];
for (const width of widths) {
  for (const count of operations) {
    for (const kind of selected) {
      const rows = samples.filter((sample) =>
        sample.kind === kind && sample.width === width &&
        sample.operations === count
      );
      const passed = rows.filter((sample) => sample.status === "passed");
      if (passed.length === 0) {
        continue;
      }
      assert(
        passed.every((sample) => sample.wasmSha256 === passed[0].wasmSha256),
        "nondeterministic Wasm",
      );
      summaries.push({
        kind,
        width,
        operations: count,
        completed: passed.length,
        requested: repetitions,
        buildMs: median(passed.map((sample) => Number(sample.buildMs))),
        coldMs: median(passed.map((sample) => Number(sample.coldMs))),
        wasmBytes: passed[0].wasmBytes,
        sourceBytes: passed[0].sourceBytes,
        sourceLines: passed[0].sourceLines,
      });
    }
  }
}
const report = {
  workload: "aggregate-width-copy-owner-scaling-v1",
  output,
  executable,
  compilerSha256,
  benchmarkSha256: await hash(await Deno.readFile(new URL(import.meta.url))),
  runtime: Deno.version,
  profileBackend: values.profile,
  codegenTier: "optimized",
  workers: 1,
  cacheDirectory: false,
  timeoutMs,
  budgetMs,
  widths,
  operations,
  kinds: selected,
  repetitions,
  status: "complete",
  elapsedMs: performance.now() - start,
  executedChecks: samples.reduce(
    (total, sample) => total + Number(sample.executedChecks ?? 0),
    0,
  ),
  summaries,
};
if (
  incomplete ||
  samples.length !==
    widths.length * operations.length * selected.length * repetitions
) {
  report.status = "incomplete";
  Deno.exitCode = 1;
}
await Deno.writeTextFile(
  `${output}/result.json`,
  JSON.stringify(report, null, 2) + "\n",
);
console.log(
  JSON.stringify({
    output,
    status: report.status,
    samples: samples.length,
    executedChecks: report.executedChecks,
    elapsedMs: report.elapsedMs,
  }),
);
