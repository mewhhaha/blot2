import { fileURLToPath } from "node:url";

import {
  type CompilerFixture,
  compilerFixtures,
  parseCompilerFixtures,
} from "./compiler_fixtures.ts";

const directory = new URL("../zig-native/", import.meta.url);
let development = false;
let incremental = false;
let timeReport = false;
let fixtures: CompilerFixture[] | undefined;
let jobs: number | undefined;
for (let index = 0; index < Deno.args.length; index++) {
  const argument = Deno.args[index];
  if (argument === "--dev") {
    development = true;
  } else if (argument === "--incremental") {
    incremental = true;
  } else if (argument === "--time-report") {
    timeReport = true;
  } else if (argument.startsWith("--fixtures=")) {
    fixtures ??= [];
    fixtures.push(
      ...parseCompilerFixtures(argument.slice("--fixtures=".length)),
    );
  } else if (argument === "--fixtures") {
    const value = Deno.args[++index];
    if (value === undefined) {
      throw new Error("--fixtures requires a comma-separated list");
    }
    fixtures ??= [];
    fixtures.push(...parseCompilerFixtures(value));
  } else if (argument.startsWith("--jobs=")) {
    jobs = Number(argument.slice("--jobs=".length));
    if (!Number.isInteger(jobs) || jobs < 1) {
      throw new Error("--jobs requires a positive integer");
    }
  } else throw new Error(`Unknown argument: ${argument}`);
}
if (incremental && !development) {
  throw new Error("--incremental requires --dev");
}
fixtures ??= [...compilerFixtures];
fixtures = [...new Set(fixtures)];
const version = await new Deno.Command("zig", {
  args: ["version"],
  stdout: "piped",
}).output();
const installed = new TextDecoder().decode(version.stdout).trim();
if (!version.success || !/^0\.17\.0(?:-|$)/.test(installed)) {
  throw new Error(`Blot requires Zig 0.17.0 (installed: ${installed})`);
}
console.log(`Building Blot with Zig ${installed}`);
const args = ["build", "install", "compiler-identity", ...fixtures];
if (development) {
  args.push(
    "-Doptimize=safe",
    "-Dllvm=false",
    "--prefix",
    "zig-out-dev",
  );
} else {
  args.push("-Doptimize=fast", "-Dllvm=true");
}
if (incremental) args.push("-fincremental");
// Zig deliberately forces a rebuild for this report; keep it opt-in.
if (timeReport) args.push("--time-report");
if (jobs !== undefined) args.push(`-j${jobs}`);
args.push("--summary", "all");
const result = await new Deno.Command("zig", {
  cwd: fileURLToPath(directory),
  args,
  stdout: "inherit",
  stderr: "inherit",
}).output();
if (!result.success) Deno.exit(result.code);
await Deno.mkdir(new URL("../build/", import.meta.url), { recursive: true });
let executable = new URL("zig-out/bin/blotc", directory);
if (development) executable = new URL("zig-out-dev/bin/blotc", directory);
console.log(`Compiler executable: ${fileURLToPath(executable)}`);
