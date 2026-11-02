import { resolve } from "node:path";
import { parseArgs } from "node:util";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";

const { values, positionals } = parseArgs({
  allowPositionals: true,
  options: {
    compiler: { type: "string" },
    entry: { type: "string" },
    "timeout-ms": { type: "string", default: "5000" },
    profile: { type: "boolean", default: false },
    trace: { type: "boolean", default: false },
    tier: { type: "string", default: "optimized" },
    workers: { type: "string", default: "1" },
    "frontend-workers": { type: "string", default: "4" },
    "measure-total": { type: "boolean", default: false },
  },
});
if (values.tier !== "development" && values.tier !== "optimized") {
  throw new Error("--tier must be development or optimized");
}
const workers = Number(values.workers);
if (!Number.isInteger(workers) || workers < 1 || workers > 16) {
  throw new Error("--workers must be an integer from 1 to 16");
}
const frontendWorkers = Number(values["frontend-workers"]);
if (
  !Number.isInteger(frontendWorkers) || frontendWorkers < 1 ||
  frontendWorkers > 16
) {
  throw new Error("--frontend-workers must be an integer from 1 to 16");
}
const parentArg = positionals[0] ?? "build/gdev-first-frame";
if (positionals.length > 1) {
  throw new Error("Expected at most one output directory");
}
const timeoutMs = Number(values["timeout-ms"]);
let maximumMs = 30_000;
if (values["measure-total"]) maximumMs = 300_000;
if (!Number.isInteger(timeoutMs) || timeoutMs < 100 || timeoutMs > maximumMs) {
  throw new Error(`--timeout-ms must be an integer from 100 to ${maximumMs}`);
}

const parent = resolve(parentArg);
await Deno.mkdir(parent, { recursive: true });
const evidence = await Deno.makeTempDir({ dir: parent, prefix: "main-" });
const root = resolve("../gdev");
const project = JSON.parse(await Deno.readTextFile(`${root}/pen.json`));
const settings = project.compiler.settings;
const compilerPath = resolve(
  values.compiler ??
    resolve(root, project.plugins[project.compiler.plugin].run.blotc),
);
const entryPath = resolve(root, values.entry ?? "src/main.blot");
const entryBytes = await Deno.readFile(entryPath);
const penBytes = await Deno.readFile(`${root}/pen.json`);
const sha256 = async (bytes: BufferSource) =>
  [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))]
    .map((byte) => byte.toString(16).padStart(2, "0")).join("");
const compilerSha256 = await sha256(await Deno.readFile(compilerPath));
let buildMs: number | null = null;
let buildStarted: number | null = null;
let compiler: Awaited<ReturnType<typeof createZigProjectCompiler>> | undefined;
let report: Record<string, unknown>;
try {
  compiler = await createZigProjectCompiler({
    executable: compilerPath,
    entry: entryPath,
    prelude: resolve("std/prelude.blot"),
    stdRoot: resolve("std"),
    imports: Object.fromEntries(
      Object.entries(settings.imports).map((
        [key, path],
      ) => [key, resolve(root, path as string)]),
    ),
    nativeAssets: {
      roots: settings.nativeAssets.roots.map((path: string) =>
        resolve(root, path)
      ),
      imports: settings.nativeAssets.imports.map((
        item: Record<string, string>,
      ) => ({
        ...item,
        module: resolve(root, item.module),
        path: resolve(root, item.path),
      })),
    },
    inferenceBudget: settings.inferenceBudget,
    storage: settings.storage,
    cacheDirectory: false,
    startupTimeoutMs: timeoutMs,
    profileBackend: values.profile || values.trace,
    profileTrace: values.trace,
    codegenTier: values.tier,
    codegenWorkers: workers,
    frontendWorkers,
  });
  buildStarted = performance.now();
  const result = await compiler.build({
    signal: AbortSignal.timeout(timeoutMs),
  });
  buildMs = performance.now() - buildStarted;
  if (result.success) {
    report = {
      success: true,
      compiled: true,
      wasmBytes: result.bytes.length,
      assetCount: result.assets?.length ?? 0,
      stats: result.stats,
    };
    await Deno.writeFile(`${evidence}/main.wasm`, result.bytes);
  } else {
    report = {
      success: false,
      compiled: false,
      status: "failed",
      diagnostics: result.diagnostics,
    };
    Deno.exitCode = 1;
  }
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  const timedOut = /abort|timed out/i.test(message);
  let status = "failed";
  if (timedOut) status = "timeout_incomplete";
  report = {
    success: false,
    compiled: false,
    status,
    error: message,
  };
  if (timedOut && buildStarted !== null) {
    buildMs = performance.now() - buildStarted;
  }
  Deno.exitCode = 1;
} finally {
  await compiler?.dispose();
}

const output = {
  evidence,
  identity: compiler?.compilerIdentity ?? null,
  compiler: compilerPath,
  compilerSha256,
  entry: entryPath,
  sourceCheckpoint: {
    entrySha256: await sha256(entryBytes),
    penJsonSha256: await sha256(penBytes),
  },
  deadlineMs: timeoutMs,
  fullTimingMeasurement: values["measure-total"],
  codegenTier: values.tier,
  codegenWorkers: workers,
  frontendWorkers,
  buildMs,
  profileBackend: values.profile || values.trace,
  profileTrace: values.trace,
  profileProgress: compiler?.profileProgress ?? null,
  ...report!,
};
await Deno.writeTextFile(
  `${evidence}/result.json`,
  JSON.stringify(output, null, 2) + "\n",
);
console.log(JSON.stringify(output));
