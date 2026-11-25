import { basename, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import {
  enrichDiagnostics,
  formatDiagnosticCodeList,
  formatDiagnosticReport,
  formatExplanation,
  type RawDiagnosticRecord,
} from "./diagnostics.ts";
import { expandGeneratorRules } from "./generators.ts";
import type { ZigProjectCompilerOptions } from "./zig_project_client.ts";
import {
  extractStandardLibrary,
  findCheckoutCompiler,
} from "./packaged_native.ts";
import { resolveProject } from "./packages.ts";
import {
  formatTestRunReport,
  runBlotTests,
  type TestRunOptions,
} from "./test_runner.ts";

const usage =
  `Usage: blot guide [--cheatsheet] | explain <CODE|--list> | fmt SOURCE [--check]
       blot check ENTRY [project options]
       blot build ENTRY [OUTPUT.wasm] [--test] [project options]
       blot dependencies ENTRY OUTPUT.blotdep [project options]
       blot test [PATHS...] [--filter TEXT] [--jobs N] [--bail] [--release]
                 [--deadline SEC] [--json] [project options]
Project options: --prelude PATH|none, --std-root DIR, --alias PREFIX=DIR,
                 --dependencies FILE, --input-mode project|source,
                 --relaxed-simd, --tail-calls, --wasm3, --json`;

async function runTestCli(
  executable: string | URL | undefined,
  args: string[],
): Promise<number> {
  const paths: string[] = [];
  const imports: Record<string, string> = Object.create(null);
  const options: TestRunOptions = { executable, paths, imports };
  let json = false;
  const invalid = (message: string) => {
    console.error(message);
    return 2;
  };
  for (let i = 0; i < args.length; i++) {
    const argument = args[i];
    if (argument === "--") {
      paths.push(...args.slice(i + 1));
      break;
    }
    switch (argument) {
      case "--help":
      case "-h":
        console.log(usage);
        return 0;
      case "--bail":
        options.bail = true;
        continue;
      case "--release":
        options.release = true;
        continue;
      case "--json":
        json = true;
        continue;
      case "--wasm3":
        options.wasm3 = true;
        continue;
      case "--relaxed-simd":
        options.relaxedSimd = true;
        continue;
      case "--tail-calls":
        options.tailCalls = true;
        continue;
    }
    if (!argument.startsWith("-")) {
      paths.push(argument);
      continue;
    }
    if (
      ![
        "--filter",
        "--jobs",
        "--deadline",
        "--prelude",
        "--std-root",
        "--alias",
        "--dependencies",
        "--input-mode",
      ].includes(argument)
    ) return invalid(`Unexpected argument: ${argument}\n${usage}`);
    const value = args[++i];
    if (!value || value.startsWith("--")) {
      return invalid(`Missing value for ${argument}`);
    }
    switch (argument) {
      case "--filter":
        options.filter = value;
        break;
      case "--jobs":
        options.jobs = Number(value);
        if (
          !/^\d+$/.test(value) || !Number.isSafeInteger(options.jobs) ||
          options.jobs < 1
        ) {
          return invalid("--jobs must be a positive integer");
        }
        break;
      case "--deadline":
        options.deadline = Number(value);
        if (
          !Number.isFinite(options.deadline) || options.deadline <= 0 ||
          options.deadline * 1000 > 2_147_483_647
        ) {
          return invalid(
            "--deadline must be positive seconds within the timer limit",
          );
        }
        break;
      case "--prelude":
        options.prelude = value === "none" ? null : value;
        break;
      case "--std-root":
        options.stdRoot = value;
        break;
      case "--dependencies":
        options.dependencies = value;
        break;
      case "--alias": {
        const separator = value.indexOf("=");
        const prefix = value.slice(0, separator);
        const path = value.slice(separator + 1);
        if (separator < 1 || !prefix.endsWith("/") || !path) {
          return invalid("--alias must be PREFIX/=DIR");
        }
        imports[prefix] = path;
        break;
      }
      case "--input-mode":
        if (value !== "project" && value !== "source") {
          return invalid("--input-mode must be project or source");
        }
        options.inputMode = value;
        break;
    }
  }
  const report = await runBlotTests(options);
  console.log(
    json ? JSON.stringify(report) : await formatTestRunReport(report),
  );
  return report.success ? 0 : 1;
}

function isNoEntryDiagnostic(
  diag: { code?: string; message?: string },
): boolean {
  return diag.code === "no_entry" ||
    (diag.code === "storage_unsupported" &&
      typeof diag.message === "string" &&
      diag.message.includes("exports nothing"));
}

async function runGeneratorProject(
  executable: string | URL | undefined,
  entry: string,
  command: string,
  destination: string | undefined,
  args: string[],
  root: string,
  rules: Parameters<typeof expandGeneratorRules>[1],
  json: boolean,
): Promise<number> {
  const { createCompiler } = await import("../mod.ts");
  const imports: Record<string, string> = Object.create(null);
  const config: Omit<ZigProjectCompilerOptions, "executable"> = {
    entry,
    stdRoot: null,
    imports,
  };
  for (let index = 0; index < args.length; index++) {
    switch (args[index]) {
      case "--alias": {
        const alias = args[++index];
        const split = alias.indexOf("=");
        const prefix = alias.slice(0, split);
        const path = alias.slice(split + 1);
        if (
          split < 1 || !prefix.endsWith("/") || !path ||
          Object.hasOwn(imports, prefix)
        ) {
          throw new Error(`Invalid or duplicate --alias: ${alias}`);
        }
        imports[prefix] = path;
        break;
      }
      case "--prelude":
        config.prelude = args[++index] === "none" ? null : args[index];
        break;
      case "--std-root":
        config.stdRoot = args[++index];
        break;
      case "--dependencies":
        config.dependencies = args[++index];
        break;
      case "--input-mode":
        if (args[++index] !== "project") {
          throw new Error("Generator projects require --input-mode project");
        }
        break;
      case "--relaxed-simd":
        config.relaxedSimd = true;
        break;
      case "--tail-calls":
        config.tailCalls = true;
        break;
      case "--wasm3":
        config.wasm3 = true;
        break;
      case "--test":
        config.testMode = true;
        break;
    }
  }
  const assets = await expandGeneratorRules(root, rules, {
    ...config,
    executable,
  });
  const compiler = await createCompiler({ ...config, executable, assets });
  try {
    const result = await compiler.build();
    const noEntryOnly = command === "check" &&
      !result.success &&
      result.diagnostics.length > 0 &&
      result.diagnostics.every((diag) => isNoEntryDiagnostic(diag));
    const succeeded = result.success || noEntryOnly;
    const diagnostics = succeeded
      ? []
      : result.diagnostics.map((diagnostic) => ({
        kind: "diagnostic" as const,
        ...diagnostic,
      }));
    if (result.success && destination) {
      await Deno.writeFile(destination, result.bytes);
    }
    if (json) {
      const enriched = diagnostics.length > 0
        ? await enrichDiagnostics(diagnostics as RawDiagnosticRecord[])
        : [];
      const compilation = result.success
        ? {
          ...result.stats,
          wasm_bytes: command === "build" ? result.bytes.length : 0,
          kind: "compilation",
          filename: entry,
          stage: command === "check" ? "check-project" : "build-project",
          success: true,
        }
        : noEntryOnly
        ? {
          kind: "compilation",
          filename: entry,
          stage: "check-project",
          success: true,
          wasm_bytes: 0,
        }
        : {
          kind: "compilation",
          filename: entry,
          stage: command === "check" ? "check-project" : "build-project",
          success: false,
        };
      const records = [...enriched, compilation];
      await Deno.stdout.write(
        new TextEncoder().encode(
          records.map((record) => JSON.stringify(record)).join("\n") + "\n",
        ),
      );
    } else if (!succeeded) {
      console.error(
        await formatDiagnosticReport(diagnostics as RawDiagnosticRecord[]),
      );
    } else {
      console.log(
        destination && result.success
          ? `${destination}: ${result.bytes.length} bytes`
          : `${entry}: checked`,
      );
    }
    return succeeded ? 0 : 1;
  } finally {
    await compiler.dispose();
  }
}

export async function runCli(
  executable?: string | URL,
  args: string[] = Deno.args,
): Promise<number> {
  const [command, filename, ...rest] = args;
  if (["--help", "-h"].includes(command)) {
    console.log(usage);
    return 0;
  }
  if (command === "guide") {
    if (args.length === 1) {
      console.log(
        await Deno.readTextFile(
          new URL("../docs/language/guide.md", import.meta.url),
        ),
      );
      return 0;
    }
    if (args.length === 2 && filename === "--cheatsheet") {
      console.log(
        await Deno.readTextFile(
          new URL("../CHEATSHEET.md", import.meta.url),
        ),
      );
      return 0;
    }
    console.error(usage);
    return 2;
  }
  if (command === "explain") {
    if (args.length === 1 || (args.length === 2 && filename === "--list")) {
      console.log(formatDiagnosticCodeList());
      return 0;
    }
    if (args.length === 2 && filename) {
      const text = formatExplanation(filename);
      if (!text) {
        console.error(
          `Unknown diagnostic code: ${filename}\n\n${formatDiagnosticCodeList()}`,
        );
        return 1;
      }
      console.log(text);
      return 0;
    }
    console.error(usage);
    return 2;
  }
  let library: Awaited<ReturnType<typeof extractStandardLibrary>> | undefined;
  try {
    if (command === "test") return await runTestCli(executable, args.slice(1));
    if (
      command === "fmt" && filename &&
      (rest.length === 0 || rest.length === 1 && rest[0] === "--check")
    ) {
      const { formatSource } = await import("./format.ts");
      const source = await Deno.readTextFile(filename);
      const formatted = await formatSource(source);
      if (rest[0] === "--check") {
        if (source !== formatted) {
          console.error(`${filename}: needs formatting`);
          return 1;
        }
      } else if (source !== formatted) {
        await Deno.writeTextFile(filename, formatted);
      }
      return 0;
    }
    if (
      !["check", "build", "dependencies"].includes(command) || !filename ||
      filename.startsWith("--")
    ) {
      console.error(usage);
      return 2;
    }
    const options: string[] = [];
    let destination: string | undefined;
    let json = false;
    for (let i = 0; i < rest.length; i++) {
      const value = rest[i];
      if (value === "--json") {
        json = true;
        continue;
      }
      if (
        command === "build" &&
        ["--relaxed-simd", "--tail-calls", "--wasm3", "--test"].includes(value)
      ) {
        options.push(value);
        continue;
      }
      if (
        ["--prelude", "--std-root", "--alias", "--dependencies", "--input-mode"]
          .includes(value)
      ) {
        if (!rest[i + 1] || rest[i + 1].startsWith("--")) {
          console.error(`Missing value for ${value}`);
          return 2;
        }
        options.push(value, rest[++i]);
      } else if (i === 0 && command !== "check" && !value.startsWith("--")) {
        destination = value;
      } else {
        console.error(`Unexpected argument: ${value}\n${usage}`);
        return 2;
      }
    }
    if (command === "dependencies" && !destination) {
      console.error(usage);
      return 2;
    }
    const packageProject = await resolveProject(filename);
    if (packageProject) {
      const explicitPrelude = options.includes("--prelude");
      const explicitStdRoot = options.includes("--std-root");
      const explicitAliases = new Set<string>();
      for (let i = 0; i < options.length; i++) {
        if (options[i] !== "--alias") continue;
        const separator = options[i + 1].indexOf("=");
        if (separator >= 0) {
          explicitAliases.add(options[i + 1].slice(0, separator));
        }
        i++;
      }
      if (!explicitPrelude) {
        options.push("--prelude", packageProject.prelude ?? "none");
      }
      for (
        const [prefix, directory] of Object.entries(packageProject.imports)
      ) {
        if (explicitAliases.has(prefix)) continue;
        if (prefix === "std/" && explicitStdRoot) continue;
        options.push("--alias", `${prefix}=${directory}`);
      }
    } else {
      if (
        Deno.build.standalone &&
        (!options.includes("--prelude") || !options.includes("--std-root"))
      ) library = await extractStandardLibrary();
      const standardRoot = library?.path ??
        fileURLToPath(new URL("../std/", import.meta.url));
      if (!options.includes("--prelude")) {
        options.push(
          "--prelude",
          join(standardRoot, "prelude.blot"),
        );
      }
      if (!options.includes("--std-root")) {
        options.push(
          "--std-root",
          standardRoot,
        );
      }
    }
    if (command === "build") {
      destination ??= `build/${basename(filename, ".blot")}.wasm`;
    }
    if (destination) {
      await Deno.mkdir(dirname(destination), { recursive: true });
    }
    if (packageProject?.generators?.length && command !== "dependencies") {
      return await runGeneratorProject(
        executable ??
          await findCheckoutCompiler(),
        filename,
        command,
        destination,
        options,
        packageProject.root,
        packageProject.generators,
        json,
      );
    }
    const result = await new Deno.Command(
      executable ?? new URL(
        "../compiler-goose/build/blotc-goose",
        import.meta.url,
      ),
      {
        args: [
          command === "check" ? "check-project" : command,
          filename,
          ...(destination ? [destination] : []),
          ...options,
        ],
        stdout: "piped",
        stderr: "piped",
      },
    ).output();
    const stdout = new TextDecoder().decode(result.stdout);
    const stderr = new TextDecoder().decode(result.stderr);
    if (json) {
      const parsed: Array<
        { rawLine: string; record?: Record<string, unknown> }
      > = [];
      const rawDiagnostics: RawDiagnosticRecord[] = [];
      for (const rawLine of stdout.split("\n")) {
        if (!rawLine.trim()) continue;
        try {
          const record = JSON.parse(rawLine) as Record<string, unknown>;
          parsed.push({ rawLine, record });
          if (record.kind === "diagnostic") {
            rawDiagnostics.push(record as unknown as RawDiagnosticRecord);
          }
        } catch {
          parsed.push({ rawLine });
        }
      }
      const enriched = rawDiagnostics.length > 0
        ? await enrichDiagnostics(rawDiagnostics)
        : [];
      let diagIndex = 0;
      const outLines = parsed.map((entry) =>
        entry.record?.kind === "diagnostic"
          ? JSON.stringify(enriched[diagIndex++])
          : entry.rawLine
      );
      if (outLines.length > 0) {
        await Deno.stdout.write(
          new TextEncoder().encode(outLines.join("\n") + "\n"),
        );
      }
    } else {
      const diagnostics: RawDiagnosticRecord[] = [];
      for (const line of stdout.trim().split("\n").filter(Boolean)) {
        const record = JSON.parse(line);
        if (record.kind === "diagnostic") {
          diagnostics.push(record as RawDiagnosticRecord);
        }
      }
      if (diagnostics.length > 0) {
        console.error(await formatDiagnosticReport(diagnostics));
      }
      if (result.success) {
        console.log(
          destination
            ? `${destination}: ${(await Deno.stat(destination)).size} bytes`
            : `${filename}: checked`,
        );
      }
    }
    if (stderr) console.error(stderr.trimEnd());
    return result.success ? 0 : 1;
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    return 1;
  } finally {
    await library?.dispose();
  }
}

if (import.meta.main) Deno.exitCode = await runCli();
