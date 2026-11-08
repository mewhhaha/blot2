// Frontend/API inventory only. Original exports are demoted in source overlays;
// the scalar sentinel avoids emitting every large game fixture. This does not
// qualify original export ABI, storage admission, effects at use sites or runtime.
import { dirname, isAbsolute, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  createZigProjectCompiler,
  type ZigProjectDiagnostic,
} from "../../host/zig_project_client.ts";

export function demoteEntries(source: string): string {
  return source.replace(
    /^([ \t]*)entry[ \t]+(const|let|func)(?=[ \t])/gm,
    "$1$2",
  );
}

type Expected = {
  code: string;
  reason: string;
  filename?: string;
  stage?: string;
};
type Row = {
  file: string;
  status: "passed" | "expected-rejection" | "failed";
  milliseconds: number | null;
  batchId: number;
  diagnostics: readonly ZigProjectDiagnostic[];
};
type Options = {
  project: string;
  paths: string[];
  report: string;
  compiler?: string;
  expectations?: Record<string, Expected>;
  batchSize?: number;
  buildTimeoutMs?: number;
};

type BatchResult = {
  success: boolean;
  diagnostics: readonly ZigProjectDiagnostic[];
};
type Batch = {
  id: number;
  files: string[];
  milliseconds: number;
  success: boolean;
  split: boolean;
};

/** A failed shared import never determines an individual module's outcome. */
export async function auditBatches(options: {
  selected: string[];
  batchSize: number;
  expectedFiles: ReadonlySet<string>;
  build(files: string[]): Promise<BatchResult>;
  batch(batch: Batch): Promise<void>;
  result(files: string[], result: BatchResult, batch: Batch): Promise<void>;
}): Promise<void> {
  if (!Number.isSafeInteger(options.batchSize) || options.batchSize < 1) {
    throw new Error("Batch size must be a positive integer");
  }
  let nextId = 0;
  const visit = async (files: string[]): Promise<void> => {
    const id = nextId++;
    const start = performance.now();
    const result = await options.build(files);
    const split = !result.success && files.length > 1;
    const batch: Batch = {
      id,
      files,
      milliseconds: performance.now() - start,
      success: result.success,
      split,
    };
    await options.batch(batch);
    if (split) {
      const middle = Math.floor(files.length / 2);
      await visit(files.slice(0, middle));
      await visit(files.slice(middle));
    } else {
      await options.result(files, result, batch);
    }
  };
  let pending: string[] = [];
  const flush = async () => {
    if (!pending.length) return;
    const files = pending;
    pending = [];
    await visit(files);
  };
  for (const file of options.selected) {
    if (options.expectedFiles.has(file)) {
      await flush();
      await visit([file]);
    } else {
      pending.push(file);
      if (pending.length === options.batchSize) await flush();
    }
  }
  await flush();
}

async function sourceFiles(root: string): Promise<string[]> {
  const command = await new Deno.Command("git", {
    args: [
      "ls-files",
      "-z",
      "--cached",
      "--others",
      "--exclude-standard",
      "--",
      "*.blot",
    ],
    cwd: root,
    stdout: "piped",
    stderr: "piped",
  }).output();
  if (!command.success) {
    throw new Error(new TextDecoder().decode(command.stderr));
  }
  const files: string[] = [];
  for (
    const path of new Set(new TextDecoder().decode(command.stdout).split("\0"))
  ) {
    if (!path.endsWith(".blot")) continue;
    try {
      if ((await Deno.stat(resolve(root, path))).isFile) files.push(path);
    } catch (error) {
      if (!(error instanceof Deno.errors.NotFound)) throw error;
    }
  }
  return files.sort();
}

export function selectPaths(files: string[], paths: string[]): string[] {
  return files.filter((file) =>
    paths.length === 0 ||
    paths.some((path) =>
      file === path || file.startsWith(path.replace(/\/$/, "") + "/")
    )
  );
}

export async function auditProject(options: Options) {
  const project = resolve(options.project);
  const config = JSON.parse(
    await Deno.readTextFile(resolve(project, "pen.json")),
  );
  const settings = config.compiler.settings;
  const files = await sourceFiles(project);
  const paths = options.paths.map((path) => {
    const name = relative(project, resolve(project, path)).replaceAll(
      "\\",
      "/",
    );
    if (name === ".." || name.startsWith("../") || isAbsolute(name)) {
      throw new Error("Audit path outside project: " + path);
    }
    return name === "" || name === "." ? "" : name;
  });
  const selected = paths.includes("") ? files : selectPaths(files, paths);
  if (!selected.length) throw new Error("No Blot sources selected");
  const expectations = options.expectations ?? {};
  for (const [file, expected] of Object.entries(expectations)) {
    if (!expected.reason?.trim() || !expected.code) {
      throw new Error("Expected rejection requires code and reason: " + file);
    }
  }
  const sources: Record<string, string> = {};
  const digestInputs: string[] = [];
  for (const file of files) {
    const original = await Deno.readTextFile(resolve(project, file));
    sources[resolve(project, file)] = demoteEntries(original);
    digestInputs.push(file + "\0" + original);
  }
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(digestInputs.join("\0")),
  );
  const inputDigest = Array.from(
    new Uint8Array(digest),
    (b) => b.toString(16).padStart(2, "0"),
  ).join("");
  const compilerRoot = resolve(
    dirname(fileURLToPath(import.meta.url)),
    "../..",
  );
  const entry = resolve(project, ".migration-frontend-audit.blot");
  const imports = Object.fromEntries(
    Object.entries(settings.imports ?? {}).map((
      [prefix, path],
    ) => [prefix, resolve(project, path as string)]),
  );
  if ("__migration_repo/" in imports) {
    throw new Error("Reserved audit import prefix");
  }
  imports["__migration_repo/"] = project;
  const stdRoot = resolve(
    project,
    settings.std ?? resolve(compilerRoot, "std"),
  );
  const compiler = await createZigProjectCompiler({
    executable: options.compiler ??
      resolve(compilerRoot, "compiler/zig-out-dev/bin/blotc"),
    entry,
    prelude: resolve(stdRoot, "prelude.blot"),
    stdRoot,
    imports,
    nativeAssets: settings.nativeAssets
      ? {
        roots: settings.nativeAssets.roots.map((path: string) =>
          resolve(project, path)
        ),
        imports: settings.nativeAssets.imports.map((
          item: Record<string, string>,
        ) => ({
          ...item,
          module: resolve(project, item.module),
          path: resolve(project, item.path),
        })),
      }
      : undefined,
    inferenceBudget: settings.inferenceBudget,
    storage: settings.storage,
    cacheDirectory: false,
    codegenTier: "development",
  });
  const report = {
    mode: "frontend-api-only",
    project,
    compilerIdentity: compiler.compilerIdentity,
    sourceDigest: inputDigest,
    overlayFiles: files.length,
    selectedFiles: selected.length,
    complete: false,
    passed: 0,
    expectedRejections: 0,
    unexpectedFailures: 0,
    batchSize: options.batchSize ?? 1,
    buildTimeoutMs: options.buildTimeoutMs ?? 30_000,
    batches: [] as Batch[],
    interruptedBatch: null as { files: string[]; message: string } | null,
    results: [] as Row[],
  };
  const save = async () => {
    await Deno.mkdir(dirname(resolve(options.report)), { recursive: true });
    await Deno.writeTextFile(
      options.report,
      JSON.stringify(report, null, 2) + "\n",
    );
  };
  try {
    if (
      !Number.isSafeInteger(report.buildTimeoutMs) || report.buildTimeoutMs < 1
    ) {
      throw new Error("Build timeout must be a positive integer");
    }
    await save();
    await auditBatches({
      selected,
      batchSize: report.batchSize,
      expectedFiles: new Set(Object.keys(expectations)),
      build: async (group) => {
        sources[entry] = group.map((file, index) =>
          `import * as target_${index} from "__migration_repo/${file}"\n`
        ).join("") +
          "entry func migration_frontend_probe () : U32 => return 0\n";
        try {
          const result = await compiler.build({
            sources,
            signal: AbortSignal.timeout(report.buildTimeoutMs),
          });
          if (result.success) {
            return { success: true, diagnostics: [] };
          }
          return { success: false, diagnostics: result.diagnostics };
        } catch (error) {
          report.interruptedBatch = { files: group, message: String(error) };
          await save();
          // Aborting the client closes its compiler process. Leave coverage
          // incomplete rather than scheduling more work on a dead transport.
          throw error;
        }
      },
      batch: async (batch) => {
        report.batches.push(batch);
        await save();
      },
      result: async (group, result, batch) => {
        for (const file of group) {
          const diagnostics = result.diagnostics;
          const expected = expectations[file];
          const matches = expected && !result.success &&
            diagnostics.some((diagnostic) =>
              diagnostic.code === expected.code &&
              resolve(diagnostic.filename) ===
                resolve(project, expected.filename ?? file) &&
              (!expected.stage || diagnostic.stage === expected.stage)
            );
          let status: Row["status"] = "failed";
          if (matches) {
            status = "expected-rejection";
          } else if (result.success && !expected) {
            status = "passed";
          }
          let milliseconds: number | null = null;
          if (group.length === 1) {
            milliseconds = batch.milliseconds;
          }
          const row: Row = {
            file,
            status,
            milliseconds,
            batchId: batch.id,
            diagnostics,
          };
          report.results.push(row);
          if (status === "passed") {
            report.passed++;
          } else if (status === "expected-rejection") {
            report.expectedRejections++;
          } else report.unexpectedFailures++;
          console.log(JSON.stringify(row));
        }
        await save();
      },
    });
    report.complete = true;
    await save();
    return report;
  } finally {
    await compiler.dispose();
  }
}

if (import.meta.main) {
  const args = [...Deno.args];
  let project = Deno.cwd();
  let report = resolve("build/migration-audit.json");
  let compiler: string | undefined;
  let expectations: Record<string, Expected> | undefined;
  let batchSize = 1;
  let buildTimeoutMs = 30_000;
  const paths: string[] = [];
  while (args.length) {
    const arg = args.shift()!;
    if (arg === "--project") project = resolve(args.shift()!);
    else if (arg === "--report") report = resolve(args.shift()!);
    else if (arg === "--compiler") compiler = resolve(args.shift()!);
    else if (arg === "--batch-size") batchSize = Number(args.shift());
    else if (arg === "--build-timeout-ms") {
      buildTimeoutMs = Number(args.shift());
    } else if (arg === "--expectations") {
      expectations = JSON.parse(await Deno.readTextFile(args.shift()!));
    } else if (arg.startsWith("--")) throw new Error("Unknown option: " + arg);
    else paths.push(arg);
  }
  const result = await auditProject({
    project,
    paths,
    report,
    compiler,
    expectations,
    batchSize,
    buildTimeoutMs,
  });
  console.log(JSON.stringify({
    complete: result.complete,
    passed: result.passed,
    expectedRejections: result.expectedRejections,
    unexpectedFailures: result.unexpectedFailures,
    report,
  }));
  Deno.exitCode = result.unexpectedFailures ? 1 : 0;
}
