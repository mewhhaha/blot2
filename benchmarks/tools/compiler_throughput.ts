// Reachable primitive throughput, not declaration padding. No compiler build.
// --lines is a minimum; whole leaves, branches and imports can exceed it.
// --modules counts source files including main; 1 keeps the monolithic control.
// deno run -A benchmarks/tools/compiler_throughput.ts --compiler PATH --lines 50000
import { parseArgs } from "node:util";
import { dirname, resolve } from "node:path";
import { instantiateGuest } from "../../host/guest.ts";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";

const { values } = parseArgs({
  options: {
    compiler: { type: "string" },
    modules: { type: "string", default: "16" },
    workers: { type: "string", default: "4" },
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
const requestedModules = Number(values.modules);
const workers = Number(values.workers);
if (!Number.isInteger(requestedModules) || requestedModules < 1) {
  throw new Error("--modules must be a positive integer");
}
if (!Number.isInteger(workers) || workers < 1 || workers > 16) {
  throw new Error("--workers must be an integer from 1 to 16");
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
  schema: 3,
  workload: "reachable-u32-balanced-tree-v3",
  requestedMinimumLines: lines,
  statementsPerLeaf: statements,
  requestedModules,
  codegenWorkers: workers,
  frontendWorkers: workers,
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
  const moduleCount = Math.min(requestedModules, leafCount);
  const moduleLines: string[][] = Array.from({ length: moduleCount }, () => []);
  const sourceLines = moduleLines[0];
  for (let index = 1; index < moduleCount; index++) {
    sourceLines.push(`import * as batch_${index} from "./leaves_${index}"`);
  }
  let level: string[] = [];
  for (let index = 0; index < leafCount; index++) {
    const name = `leaf_${index}`;
    const moduleIndex = index % moduleCount;
    const leafLines = moduleLines[moduleIndex];
    leafLines.push(`const ${name} = func (input: U32): U32 => return do:`);
    let previous = "input";
    for (let step = 0; step < statements; step++) {
      const value = `value_${step}`;
      let operation = "bit_xor";
      if (step % 2 === 0) operation = "mul";
      leafLines.push(
        `  let ${value}: U32 = @u32.${operation} ${previous} ${
          operationConstant(index, step)
        }`,
      );
      previous = value;
    }
    leafLines.push(`  return ${previous}`);
    let reference = name;
    if (moduleIndex > 0) reference = `batch_${moduleIndex}.${name}`;
    level.push(reference);
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
  const files = moduleLines.map((text, index) => {
    let path = `leaves_${index}.blot`;
    if (index === 0) path = "main.blot";
    const source = text.join("\n") + "\n";
    return { path, source, lines: text.length, bytes: encoder.encode(source) };
  });
  const generationMs = performance.now() - generationStart;
  const exactLines = files.reduce((sum, file) => sum + file.lines, 0);
  const exactBytes = files.reduce((sum, file) => sum + file.bytes.length, 0);
  if (exactLines < lines) throw new Error("generator LOC below target");
  const manifest = await Promise.all(files.map(async (file) => ({
    path: file.path,
    lines: file.lines,
    bytes: file.bytes.length,
    sha256: await sha256(file.bytes),
  })));
  manifest.sort((left, right) => left.path.localeCompare(right.path, "en"));
  const manifestSha256 = await sha256(encoder.encode(JSON.stringify(manifest)));
  report.source = {
    lines: exactLines,
    nonblankLines: exactLines,
    overTargetLines: exactLines - lines,
    estimatedLexicalTokens: files.reduce((sum, file) =>
      sum +
      (file.source.match(
        /@[A-Za-z0-9_.]+|[A-Za-z_][A-Za-z0-9_]*|[0-9]+|=>|->|[^\s]/g,
      )?.length ?? 0), 0),
    tokenEstimateMethod:
      "ASCII names, intrinsics and numbers are single tokens; punctuation is split",
    bytes: exactBytes,
    sha256: manifestSha256,
    hashKind: "canonical-source-manifest-sha256",
    manifestSha256,
    manifestSerialization:
      "compact JSON array sorted by relative path with path,lines,bytes,sha256 keys",
    modules: moduleCount,
    files: manifest,
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
    codegenWorkers: workers,
    frontendWorkers: workers,
    startupTimeoutMs: timeoutMs,
  });
  const startupMs = performance.now() - coldStart;
  report.compilerIdentity = compiler.compilerIdentity;
  const sources: Record<string, string> = {};
  for (const file of files) sources[`${directory}/${file.path}`] = file.source;
  const result = await compiler.build({
    sources,
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
