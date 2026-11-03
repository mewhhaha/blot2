// Capture the actual Gdev main's private pre-outline Wasm IR under GDB.
// Usage: deno run -A scripts/bench/capture_outline.ts [--compiler PATH] [--output DIR]
// Defaults: zig-native/zig-out/bin/blotc and build/bench/outline-capture.
// Replay only with the private pinned compiler engine:
//   cd zig-native && zig build bench-outline -Doptimize=fast -Dllvm=false --prefix zig-out-native-dev
//   zig-native/zig-out-native-dev/bin/blot-outline-replay build/bench/outline-capture [verify]
// Captured IR is trusted only as output of the compiler fingerprint in manifest.json.

import { resolve } from "node:path";
import { parseArgs } from "node:util";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";

const { values } = parseArgs({
  options: {
    compiler: { type: "string", default: "zig-native/zig-out/bin/blotc" },
    output: { type: "string", default: "build/bench/outline-capture" },
  },
});

const repo = resolve(new URL("../..", import.meta.url).pathname);
const gdev = resolve(repo, "../gdev");
const output = resolve(values.output!);
const compilerPath = resolve(values.compiler!);
const entryPath = resolve(gdev, "src/main.blot");
const preludePath = resolve(repo, "std/prelude.blot");
const stdRoot = resolve(repo, "std");
const project = JSON.parse(await Deno.readTextFile(`${gdev}/pen.json`));
const settings = project.compiler.settings;

const hash = async (bytes: BufferSource) => {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  return [...digest].map((byte) => byte.toString(16).padStart(2, "0")).join("");
};

const ignoredDirectories = new Set([
  ".git",
  "node_modules",
  "build",
  ".zig-cache",
  "dist",
  ".cache",
]);
const visitedDirectories = new Set<string>();

async function captureFilesUnder(
  path: string,
  files: Set<string>,
  includeAssets = false,
): Promise<void> {
  const canonicalPath = await Deno.realPath(path);
  let info: Deno.FileInfo;
  try {
    info = await Deno.stat(canonicalPath);
  } catch (error) {
    throw new Error(`Missing source input ${path}`, { cause: error });
  }
  if (info.isFile) {
    if (includeAssets || canonicalPath.endsWith(".blot")) {
      files.add(canonicalPath);
    }
    return;
  }
  if (!info.isDirectory) {
    throw new Error(`Not a file or directory: ${path}`);
  }
  let kind = "source";
  if (includeAssets) kind = "assets";
  const visitKey = `${kind}:${canonicalPath}`;
  if (visitedDirectories.has(visitKey)) return;
  visitedDirectories.add(visitKey);
  for await (const entry of Deno.readDir(canonicalPath)) {
    if (entry.isDirectory && ignoredDirectories.has(entry.name)) continue;
    if (entry.isDirectory && entry.name.startsWith("zig-out")) continue;
    await captureFilesUnder(
      resolve(canonicalPath, entry.name),
      files,
      includeAssets,
    );
  }
}

async function sourceManifest(): Promise<{
  files: { path: string; sha256: string }[];
  sha256: string;
}> {
  visitedDirectories.clear();
  const paths = new Set<string>([
    resolve(gdev, "pen.json"),
    entryPath,
    preludePath,
  ]);
  await captureFilesUnder(stdRoot, paths);
  for (const path of Object.values(settings.imports) as string[]) {
    await captureFilesUnder(resolve(gdev, path), paths);
  }
  for (const path of settings.nativeAssets.roots as string[]) {
    await captureFilesUnder(resolve(gdev, path), paths, true);
  }
  for (
    const item of settings.nativeAssets.imports as Record<string, string>[]
  ) {
    // Native readers synthesize these module names from the pinned asset.
    try {
      await captureFilesUnder(resolve(gdev, item.module), paths);
    } catch (error) {
      if (!(error instanceof Deno.errors.NotFound)) throw error;
    }
    await captureFilesUnder(resolve(gdev, item.path), paths, true);
  }
  const files: { path: string; sha256: string }[] = [];
  for (const path of [...paths].sort()) {
    let name = path;
    if (path.startsWith(`${repo}/`)) name = path.slice(repo.length + 1);
    files.push({
      path: name,
      sha256: await hash(await Deno.readFile(path)),
    });
  }
  return {
    files,
    sha256: await hash(new TextEncoder().encode(JSON.stringify(files))),
  };
}

const source = await sourceManifest();
const compilerSha256 = await hash(await Deno.readFile(compilerPath));
const capturePython = resolve(repo, "scripts/bench/capture_outline.py");
const wrapperPath = resolve(output, "ptracer");
const controlPath = resolve(output, "control");
await Deno.mkdir(controlPath, { recursive: true });
for (
  const name of [
    "pid",
    "attached",
    "start",
    "detached",
    "ir.bin",
    "ir.json",
    "main.wasm",
    "manifest.json",
    "capture.log",
  ]
) {
  try {
    await Deno.remove(resolve(output, name));
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
  }
}
for (const name of ["pid", "attached", "start", "detached"]) {
  try {
    await Deno.remove(resolve(controlPath, name));
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
  }
}

const wrapper = `#!/usr/bin/env python3
import ctypes, os, sys
ctypes.CDLL(None).prctl(0x59616D61, ctypes.c_ulong(-1).value, 0, 0, 0)
binary = ${JSON.stringify(compilerPath)}
os.execv(binary, [binary, *sys.argv[1:]])
`;
await Deno.writeTextFile(wrapperPath, wrapper);
await Deno.chmod(wrapperPath, 0o755);

const gdb = new Deno.Command("gdb", {
  args: ["-batch", "-q", "-x", capturePython],
  env: {
    OUTLINE_CAPTURE: output,
    OUTLINE_BINARY: compilerPath,
    OUTLINE_SOURCE_SHA256: source.sha256,
    OUTLINE_COMPILER_SHA256: compilerSha256,
  },
  stdin: "null",
  stdout: "piped",
  stderr: "piped",
}).spawn();
let gdbExited = false;
const gdbStatus = gdb.status.then((status) => {
  gdbExited = true;
  return status;
});
const gdbOutput = gdb.output().then(async (result) => {
  const log = new TextDecoder().decode(result.stdout) +
    new TextDecoder().decode(result.stderr);
  await Deno.writeTextFile(resolve(output, "capture.log"), log);
  return { status: result.code, log };
});
let compiler: Awaited<ReturnType<typeof createZigProjectCompiler>> | undefined;
let failure: unknown;
const startedAt = new Date().toISOString();
const buildDeadline = performance.now() + 30_000;
const remainingBuildMs = () =>
  Math.max(1, Math.ceil(buildDeadline - performance.now()));
try {
  compiler = await createZigProjectCompiler({
    executable: wrapperPath,
    entry: entryPath,
    prelude: preludePath,
    stdRoot,
    imports: Object.fromEntries(
      Object.entries(settings.imports).map(([key, path]) => [
        key,
        resolve(gdev, path as string),
      ]),
    ),
    nativeAssets: {
      roots: settings.nativeAssets.roots.map((path: string) =>
        resolve(gdev, path)
      ),
      imports: settings.nativeAssets.imports.map((
        item: Record<string, string>,
      ) => ({
        ...item,
        module: resolve(gdev, item.module),
        path: resolve(gdev, item.path),
      })),
    },
    inferenceBudget: settings.inferenceBudget,
    storage: settings.storage,
    cacheDirectory: false,
    startupTimeoutMs: Math.min(8_000, remainingBuildMs()),
    profileBackend: true,
    codegenTier: "optimized",
    codegenWorkers: 4,
    frontendWorkers: 4,
  });
  await Deno.writeTextFile(resolve(controlPath, "pid"), String(compiler.pid));
  let attached = false;
  const attachDeadline = performance.now() +
    Math.min(8_000, remainingBuildMs());
  while (performance.now() < attachDeadline) {
    if (gdbExited) {
      throw new Error("GDB exited before attaching; see capture.log");
    }
    try {
      await Deno.stat(resolve(controlPath, "attached"));
      attached = true;
      break;
    } catch (error) {
      if (!(error instanceof Deno.errors.NotFound)) throw error;
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
  }
  if (!attached) throw new Error("GDB attach timed out; see capture.log");
  await Deno.writeTextFile(resolve(controlPath, "start"), "1");

  const buildStarted = performance.now();
  const result = await compiler.build({
    signal: AbortSignal.timeout(remainingBuildMs()),
  });
  const buildMs = performance.now() - buildStarted;
  if (!result.success) {
    throw new Error(
      `Gdev compile failed: ${JSON.stringify(result.diagnostics)}`,
    );
  }
  const after = await sourceManifest();
  if (after.sha256 !== source.sha256) {
    throw new Error("Source inputs changed during the IR capture");
  }
  const wasmSha256 = await hash(result.bytes);
  await Deno.writeFile(resolve(output, "main.wasm"), result.bytes);
  const irPath = resolve(output, "ir.json");
  const ir = JSON.parse(await Deno.readTextFile(irPath));
  ir.wasm_sha256 = wasmSha256;
  await Deno.writeTextFile(irPath, JSON.stringify(ir, null, 2) + "\n");
  const manifest = {
    format: 1,
    capturedAt: startedAt,
    compiler: compilerPath,
    compilerSha256,
    sourceSha256: source.sha256,
    sourceFiles: source.files,
    wasmBytes: result.bytes.length,
    wasmSha256,
    buildMs,
    stats: result.stats,
    captureTool: capturePython,
    replay:
      "zig-native/zig-out-native-dev/bin/blot-outline-replay <capture-dir> [verify]",
    trust:
      "Private pinned compiler engine capture; not an authority for untrusted IR.",
  };
  await Deno.writeTextFile(
    resolve(output, "manifest.json"),
    JSON.stringify(manifest, null, 2) + "\n",
  );
  const detachedDeadline = performance.now() + 8_000;
  let detached = false;
  while (performance.now() < detachedDeadline) {
    try {
      await Deno.stat(resolve(controlPath, "detached"));
      detached = true;
      break;
    } catch (error) {
      if (!(error instanceof Deno.errors.NotFound)) throw error;
      if (gdbExited) break;
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
  }
  if (!detached) {
    throw new Error("GDB did not finish capture/detach; see capture.log");
  }
  const capture = await gdbOutput;
  const status = await gdbStatus;
  if (status.code !== 0 || capture.status !== 0) {
    throw new Error(`GDB capture failed (${status.code}); see capture.log`);
  }
  console.log(
    JSON.stringify({
      success: true,
      output,
      wasmBytes: result.bytes.length,
      wasmSha256,
      sourceSha256: source.sha256,
      compilerSha256,
    }),
  );
} catch (error) {
  failure = error;
} finally {
  try {
    await compiler?.dispose();
  } catch (error) {
    failure ??= error;
  }
  if (!gdbExited) {
    try {
      gdb.kill("SIGTERM");
    } catch {
      // It exited between the status check and kill.
    }
    const stopped = await Promise.race([
      gdbStatus.then(() => true),
      new Promise<boolean>((resolve) =>
        setTimeout(() => resolve(false), 1_500)
      ),
    ]);
    if (!stopped) {
      try {
        gdb.kill("SIGKILL");
      } catch {
        // It exited between the timeout and kill.
      }
      await gdbStatus;
    }
  }
  try {
    if (!gdbExited) await gdbStatus;
    await gdbOutput;
  } catch (error) {
    failure ??= error;
  }
}
if (failure !== undefined) throw failure;
