// Reachable primitive throughput, not declaration padding. No compiler build.
// --lines is a minimum; the final whole leaf and branch can exceed it.
// deno run -A scripts/bench/compiler_throughput.ts --compiler PATH --lines 50000
import { parseArgs } from "node:util";
import { dirname, resolve } from "node:path";
import { instantiateGuest } from "../../compiler/guest.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";

const { values } = parseArgs({
  options: {
    compiler: { type: "string" },
    lines: { type: "string", default: "1000" },
    "statements-per-leaf": { type: "string", default: "16" },
    "timeout-ms": { type: "string", default: "5000" },
    output: { type: "string" },
    profile: { type: "boolean", default: false },
  },
});
const lines = Number(values.lines);
const timeoutMs = Number(values["timeout-ms"]);
const statements = Number(values["statements-per-leaf"]);
if (!values.compiler) throw new Error("--compiler PATH is required");
if (!Number.isSafeInteger(lines) || lines < 4) {
  throw new Error("--lines must be an integer >= 4");
}
if (!Number.isInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 30000) {
  throw new Error("--timeout-ms must be an integer from 1 to 30000");
}
if (!Number.isSafeInteger(statements) || statements < 2) {
  throw new Error("--statements-per-leaf must be an integer >= 2");
}
const compilerPath = resolve(values.compiler);
const encoder = new TextEncoder();
async function sha256(bytes: Uint8Array<ArrayBuffer>) {
  const hash = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(
    new Uint8Array(hash),
    (b) => b.toString(16).padStart(2, "0"),
  )
    .join("");
}
function operationConstant(leaf: number, step: number) {
  const ordinal = leaf * statements + step;
  if (step % 2 === 0) return ordinal * 2 + 3;
  return Math.imul(ordinal + 1, 2654435761) >>> 0;
}
function expectedChecksum(input: number, leaves: number) {
  let sum = 0;
  for (let leaf = 0; leaf < leaves; leaf++) {
    let value = input;
    for (let step = 0; step < statements; step++) {
      const constant = operationConstant(leaf, step);
      if (step % 2 === 0) value = Math.imul(value, constant) >>> 0;
      else value = (value ^ constant) >>> 0;
    }
    sum = (sum + value) >>> 0;
  }
  return sum;
}

const report: Record<string, unknown> = {
  schema: 2,
  workload: "reachable-u32-balanced-tree-v2",
  requestedMinimumLines: lines,
  statementsPerLeaf: statements,
  timeoutMs,
  compilerPath,
  cacheDirectory: false,
  codegenTier: "optimized",
  profileBackend: values.profile,
  status: "incomplete",
};
let directory: string | undefined;
let compiler: Awaited<ReturnType<typeof createZigProjectCompiler>> | undefined;
let timer: ReturnType<typeof setTimeout> | undefined;
let failed = false;
const signal = new AbortController();
const overallStart = performance.now();
try {
  const generationStart = performance.now();
  const leafCount = Math.max(1, Math.ceil((lines - 2) / (statements + 3)));
  if (leafCount * statements > 0x7ffffffe) {
    throw new Error("workload exceeds distinct U32 operation-constant budget");
  }
  const sourceLines: string[] = [];
  let level: string[] = [];
  for (let index = 0; index < leafCount; index++) {
    const name = `leaf_${index}`;
    sourceLines.push(`const ${name} = func (input: U32): U32 => return do:`);
    let previous = "input";
    for (let step = 0; step < statements; step++) {
      const value = `value_${step}`;
      let operation = "bit_xor";
      if (step % 2 === 0) operation = "mul";
      sourceLines.push(
        `  let ${value}: U32 = @u32.${operation} ${previous} ${
          operationConstant(index, step)
        }`,
      );
      previous = value;
    }
    sourceLines.push(`  return ${previous}`);
    level.push(name);
  }
  let nodeCount = 0;
  let depth = 0;
  while (level.length > 1) {
    const next: string[] = [];
    for (let index = 0; index < level.length; index += 2) {
      if (index + 1 === level.length) {
        next.push(level[index]);
        continue;
      }
      const name = `node_${nodeCount++}`;
      sourceLines.push(
        `const ${name} = func (input: U32): U32 => return @u32.add (${
          level[index]
        } input) (${level[index + 1]} input)`,
      );
      next.push(name);
    }
    level = next;
    depth++;
  }
  sourceLines.push(
    `entry const checksum = func (input: U32): Array U32 => return do:`,
    `  let output: GrowArray U32 = #[${level[0]} input]`,
    `  return @storage.freeze output`,
  );
  const source = sourceLines.join("\n") + "\n";
  const sourceBytes = encoder.encode(source);
  const generationMs = performance.now() - generationStart;
  const exactLines = source.split("\n").length - 1;
  if (exactLines < lines) throw new Error("generator LOC below target");
  report.source = {
    lines: exactLines,
    nonblankLines: exactLines,
    overTargetLines: exactLines - lines,
    estimatedLexicalTokens:
      source.match(/@[A-Za-z0-9_.]+|[A-Za-z_][A-Za-z0-9_]*|[0-9]+|=>|->|[^\s]/g)
        ?.length ?? 0,
    tokenEstimateMethod:
      "ASCII names, intrinsics and numbers are single tokens; punctuation is split",
    bytes: sourceBytes.length,
    sha256: await sha256(sourceBytes),
    leafFunctions: leafCount,
    branchFunctions: nodeCount,
    reachableFunctions: leafCount + nodeCount + 1,
    callEdges: nodeCount * 2 + 1,
    maximumCallDepth: depth + 1,
    primitiveStatements: leafCount * statements,
    distinctLeafConstantSequences: leafCount,
    allLeavesContributeToChecksum: true,
  };
  report.compilerSha256 = await sha256(await Deno.readFile(compilerPath));
  report.generationMs = generationMs;
  directory = await Deno.makeTempDir({ prefix: "blot-throughput-" });
  const entryPath = `${directory}/main.blot`;
  const coldStart = performance.now();
  timer = setTimeout(() => signal.abort(), timeoutMs);
  compiler = await createZigProjectCompiler({
    executable: compilerPath,
    entry: entryPath,
    prelude: null,
    cacheDirectory: false,
    codegenTier: "optimized",
    profileBackend: values.profile,
    startupTimeoutMs: timeoutMs,
  });
  const startupMs = performance.now() - coldStart;
  report.compilerIdentity = compiler.compilerIdentity;
  const result = await compiler.build({
    sources: { [entryPath]: source },
    signal: signal.signal,
  });
  const coldStartupBuildMs = performance.now() - coldStart;
  clearTimeout(timer);
  report.startupMs = startupMs;
  report.coldStartupBuildMs = coldStartupBuildMs;
  report.generationPlusColdStartupBuildMs = generationMs + coldStartupBuildMs;
  report.wallThroughBuildMs = performance.now() - overallStart;
  if (!result.success) {
    report.diagnostics = result.diagnostics;
    report.attemptStats = result.attemptStats;
    throw new Error("compilation failed");
  }
  report.stats = result.stats;
  report.wasm = {
    bytes: result.bytes.length,
    sha256: await sha256(result.bytes),
  };
  const guest = await instantiateGuest(result.bytes);
  const checks: {
    input: number;
    expected: number;
    actual: number;
    passed: boolean;
  }[] = [];
  report.checks = checks;
  try {
    report.abi = guest.abi.version;
    if (guest.abi.version !== 8) {
      throw new Error("expected owned backend ABI 8");
    }
    for (const input of [0, 17, 0xffffffff]) {
      const output = guest.call("checksum", input);
      if (!(output instanceof Uint32Array) || output.length !== 1) {
        throw new Error("expected a one-element Array U32");
      }
      const expected = expectedChecksum(input, leafCount);
      checks.push({
        input,
        expected,
        actual: output[0],
        passed: output[0] === expected,
      });
      if (output[0] !== expected) {
        throw new Error(`checksum mismatch for ${input}`);
      }
    }
  } finally {
    guest.dispose();
  }
  const measuredMs = generationMs + coldStartupBuildMs;
  report.linesPerSecond = exactLines * 1000 / measuredMs;
  report.coldBuildLinesPerSecond = exactLines * 1000 / coldStartupBuildMs;
  report.status = "passed";
} catch (error) {
  failed = true;
  report.status = "failed";
  if (signal.signal.aborted) report.status = "timeout";
  report.error = String(error);
} finally {
  clearTimeout(timer);
  report.wallElapsedMs = performance.now() - overallStart;
  if (compiler) await compiler.dispose();
  if (directory) await Deno.remove(directory, { recursive: true });
  const json = JSON.stringify(report, null, 2) + "\n";
  if (values.output) {
    const path = resolve(values.output);
    await Deno.mkdir(dirname(path), { recursive: true });
    await Deno.writeTextFile(path, json);
  }
  console.log(json.trimEnd());
}
if (failed) Deno.exitCode = 1;
