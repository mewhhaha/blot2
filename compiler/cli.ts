import { basename, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { extractStandardLibrary } from "./packaged_native.ts";

const usage = `Usage: blot guide | fmt SOURCE [--check]
       blot check ENTRY [project options]
       blot build ENTRY [OUTPUT.wasm] [project options]
       blot dependencies ENTRY OUTPUT.blotdep [project options]
Project options: --prelude PATH|none, --std-root DIR, --alias PREFIX=DIR,
                 --dependencies FILE, --input-mode project|source, --json`;

export async function runCli(
  executable: string | URL = new URL(
    "../zig-native/zig-out/bin/blotc",
    import.meta.url,
  ),
  args: string[] = Deno.args,
): Promise<number> {
  const [command, filename, ...rest] = args;
  if (["--help", "-h"].includes(command)) {
    console.log(usage);
    return 0;
  }
  if (command === "guide" && args.length === 1) {
    console.log(
      await Deno.readTextFile(new URL("./guide.md", import.meta.url)),
    );
    return 0;
  }
  let library: Awaited<ReturnType<typeof extractStandardLibrary>> | undefined;
  try {
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
    if (command === "build") {
      destination ??= `build/${basename(filename, ".blot")}.wasm`;
    }
    if (destination) {
      await Deno.mkdir(dirname(destination), { recursive: true });
    }
    const result = await new Deno.Command(executable, {
      args: [
        command === "check" ? "check-project" : command,
        filename,
        ...(destination ? [destination] : []),
        ...options,
      ],
      stdout: "piped",
      stderr: "piped",
    }).output();
    const stdout = new TextDecoder().decode(result.stdout);
    const stderr = new TextDecoder().decode(result.stderr);
    if (json) await Deno.stdout.write(result.stdout);
    else {
      for (const line of stdout.trim().split("\n").filter(Boolean)) {
        const record = JSON.parse(line);
        if (record.kind === "diagnostic") {
          console.error(
            `${record.filename}:${record.start}-${record.end}: ${record.code}: ${record.message}`,
          );
        }
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
