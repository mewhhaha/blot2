import { fileURLToPath } from "node:url";

const directory = new URL("../zig-native/", import.meta.url);
const development = Deno.args.includes("--dev");
for (const argument of Deno.args) {
  if (argument !== "--dev") throw new Error(`Unknown argument: ${argument}`);
}
const version = await new Deno.Command("zig", {
  args: ["version"],
  stdout: "piped",
}).output();
const installed = new TextDecoder().decode(version.stdout).trim();
if (!version.success || !/^0\.17\.0(?:-|$)/.test(installed)) {
  throw new Error(`Blot requires Zig 0.17.0 (installed: ${installed})`);
}
console.log(`Building Blot with Zig ${installed}`);
const fixtures = ["arena-fixture", "shared-rc-fixture", "list-runtime-fixture"];
const commands = [];
if (development) {
  const options = ["-Doptimize=safe", "-Dllvm=false", "-fincremental"];
  commands.push([
    "build",
    "install",
    "compiler-identity",
    ...fixtures,
    ...options,
    "--prefix",
    "zig-out-dev",
    "--summary",
    "all",
  ]);
  // An unchanged budget fixture can use Zig's artifact cache. Forcing another
  // incremental compiler invocation adds several seconds to every quick check.
  commands.push([
    "build",
    "budget-fixture",
    "-Doptimize=safe",
    "-Dllvm=false",
    "--prefix",
    "zig-out-dev",
    "--summary",
    "all",
  ]);
} else {
  commands.push([
    "build",
    "install",
    "compiler-identity",
    ...fixtures,
    "budget-fixture",
    "-Doptimize=fast",
    "--summary",
    "all",
  ]);
}
for (const args of commands) {
  const result = await new Deno.Command("zig", {
    cwd: fileURLToPath(directory),
    args,
    stdout: "inherit",
    stderr: "inherit",
  }).output();
  if (!result.success) Deno.exit(result.code);
}
await Deno.mkdir(new URL("../build/", import.meta.url), { recursive: true });
