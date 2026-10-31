// Frontend/API inventory only. Original exports are demoted in source overlays;
// the scalar sentinel avoids emitting every large game fixture. This does not
// qualify original export ABI, storage admission, effects at use sites or runtime.
import { dirname, isAbsolute, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  createZigProjectCompiler,
  type ZigProjectDiagnostic,
} from "../compiler/zig_project_client.ts";

export function demoteEntries(source: string): string {
  return source.replace(/^([ \t]*)entry[ \t]+(const|let)(?=[ \t])/gm, "$1$2");
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
  milliseconds: number;
  diagnostics: readonly ZigProjectDiagnostic[];
};
type Options = {
  project: string;
  paths: string[];
  report: string;
  compiler?: string;
  expectations?: Record<string, Expected>;
};

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
  const compilerRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
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
      resolve(compilerRoot, "zig-native/zig-out-dev/bin/blotc"),
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
    for (const file of selected) {
      sources[entry] = 'import * as target from "__migration_repo/' + file +
        '"\nentry const migration_frontend_probe = func () : U32 => return 0\n';
      const start = performance.now();
      const result = await compiler.build({ sources });
      const diagnostics = result.success ? [] : result.diagnostics;
      const expected = expectations[file];
      const matches = expected && !result.success &&
        diagnostics.some((diagnostic) =>
          diagnostic.code === expected.code &&
          resolve(diagnostic.filename) ===
            resolve(project, expected.filename ?? file) &&
          (!expected.stage || diagnostic.stage === expected.stage)
        );
      const status = matches
        ? "expected-rejection"
        : result.success && !expected
        ? "passed"
        : "failed";
      const row: Row = {
        file,
        status,
        milliseconds: performance.now() - start,
        diagnostics,
      };
      report.results.push(row);
      if (status === "passed") report.passed++;
      else if (status === "expected-rejection") report.expectedRejections++;
      else report.unexpectedFailures++;
      console.log(JSON.stringify(row));
      await save();
    }
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
  const paths: string[] = [];
  while (args.length) {
    const arg = args.shift()!;
    if (arg === "--project") project = resolve(args.shift()!);
    else if (arg === "--report") report = resolve(args.shift()!);
    else if (arg === "--compiler") compiler = resolve(args.shift()!);
    else if (arg === "--expectations") {
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
