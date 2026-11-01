// Actual Gdev main: bounded owned.emit CPU attribution, including incomplete builds.
import { resolve } from "node:path";
import { parseArgs } from "node:util";
import { type ZigProjectCompilerOptions } from "../../compiler/zig_project_client.ts";
import { createSampledCompiler } from "./engine_sampling.ts";

const { values } = parseArgs({
  options: {
    compiler: {
      type: "string",
      default: "zig-native/zig-out-native-dev/bin/blotc",
    },
    output: { type: "string", default: "build/bench/gdev-emission" },
    "timeout-ms": { type: "string", default: "30000" },
  },
});
const timeoutMs = Number(values["timeout-ms"]);
if (!Number.isInteger(timeoutMs) || timeoutMs < 100 || timeoutMs > 30000) {
  throw new Error("--timeout-ms must be 100..30000");
}
const repo = resolve(new URL("../..", import.meta.url).pathname);
const root = resolve(repo, "../gdev");
const parent = resolve(values.output!);
await Deno.mkdir(parent, { recursive: true });
const output = await Deno.makeTempDir({ dir: parent, prefix: "main-" });
const settings =
  JSON.parse(await Deno.readTextFile(`${root}/pen.json`)).compiler.settings;
const hash = async (bytes: Uint8Array<ArrayBuffer>) =>
  [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map((b) =>
    b.toString(16).padStart(2, "0")
  ).join("");
const options: ZigProjectCompilerOptions = {
  executable: resolve(values.compiler!),
  entry: resolve(root, "src/main.blot"),
  prelude: resolve(repo, "std/prelude.blot"),
  stdRoot: resolve(repo, "std"),
  imports: Object.fromEntries(
    Object.entries(settings.imports).map(([key, path]) => [
      key,
      resolve(root, path as string),
    ]),
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
  storage: settings.storage,
  inferenceBudget: settings.inferenceBudget,
  cacheDirectory: false,
  profileTrace: true,
  profileBackend: true,
  codegenTier: "optimized",
  frontendWorkers: 4,
  codegenWorkers: 4,
  startupTimeoutMs: Math.min(timeoutMs, 5000),
};
const filePins = Object.fromEntries(
  await Promise.all([
    String(options.executable),
    String(options.entry),
    String(options.prelude),
    `${root}/pen.json`,
  ].map(async (path) => [path, await hash(await Deno.readFile(path))])),
);
const git = async (cwd: string, args: string[]) => {
  const result = await new Deno.Command("git", {
    cwd,
    args,
    stdout: "piped",
    stderr: "piped",
    signal: AbortSignal.timeout(5000),
  }).output();
  if (!result.success) throw new Error(new TextDecoder().decode(result.stderr));
  return result.stdout;
};
const sourcePins = await Promise.all([repo, root, resolve(repo, "../ink")].map(
  async (path) => {
    const [head, status, diff] = await Promise.all([
      git(path, ["rev-parse", "HEAD"]),
      git(path, ["status", "--porcelain"]),
      git(path, ["diff", "--binary", "HEAD"]),
    ]);
    return {
      path,
      head: new TextDecoder().decode(head).trim(),
      status: new TextDecoder().decode(status),
      trackedDiffSha256: await hash(diff),
    };
  },
));
await Deno.writeTextFile(
  `${output}/sampling.json`,
  JSON.stringify(
    {
      diagnostic:
        "Actual main CPU attribution; incomplete builds do not qualify latency or output",
      options,
      timeoutMs,
      sampleFocus: "emission",
      filePins,
      sourcePins,
      summarize: ["python3", "scripts/bench/summarize_stacks.py", output],
      cpuWindow:
        "sampling-window.json excludes frontend CPU; builds.jsonl covers the whole build",
    },
    null,
    2,
  ) + "\n",
);
console.log(JSON.stringify({ output, status: "starting", timeoutMs }));
let sampling: Awaited<ReturnType<typeof createSampledCompiler>> | undefined;
let buildStarted: number | undefined;
let report: Record<string, unknown> = { success: false, compiled: false };
try {
  sampling = await createSampledCompiler(options, output, repo, "emission");
  buildStarted = performance.now();
  const result = await sampling.build({
    signal: AbortSignal.timeout(timeoutMs),
  });
  if (result.success) {
    await Deno.writeFile(`${output}/main.wasm`, result.bytes);
    report = {
      success: true,
      compiled: true,
      status: "complete",
      wasmBytes: result.bytes.length,
      stats: result.stats,
    };
  } else {
    report.status = "failed";
    report.diagnostics = result.diagnostics;
    Deno.exitCode = 1;
  }
} catch (error) {
  report.status = "failed";
  if (error instanceof DOMException && error.name === "AbortError") {
    report.status = "timeout_incomplete";
  }
  report.error = String(error);
  Deno.exitCode = 1;
} finally {
  let buildMs: number | null = null;
  if (buildStarted !== undefined) buildMs = performance.now() - buildStarted;
  try {
    await sampling?.dispose();
  } catch (error) {
    report.cleanupError = String(error);
    Deno.exitCode = 1;
  }
  const profileProgress = sampling?.compiler.profileProgress ?? null;
  await Deno.writeTextFile(
    `${output}/profile-progress.json`,
    JSON.stringify(profileProgress, null, 2) + "\n",
  );
  const result = {
    output,
    ...report,
    buildMs,
    deadlineMs: timeoutMs,
    compilerIdentity: sampling?.compiler.compilerIdentity ?? null,
    profileProgress,
  };
  await Deno.writeTextFile(
    `${output}/result.json`,
    JSON.stringify(result, null, 2) + "\n",
  );
  console.log(JSON.stringify(result));
}
