import { fileURLToPath } from "node:url";

const directory = new URL("../zig-native/", import.meta.url);
const version = await new Deno.Command("zig", {
  args: ["version"],
  stdout: "piped",
}).output();
const installed = new TextDecoder().decode(version.stdout).trim();
if (!version.success || !/^0\.17\.0(?:-|$)/.test(installed)) {
  throw new Error(`Blot requires Zig 0.17.0 (installed: ${installed})`);
}
console.log(`Building Blot with Zig ${installed}`);
const result = await new Deno.Command("zig", {
  cwd: fileURLToPath(directory),
  args: [
    "build",
    "install",
    "compiler-identity",
    "arena-fixture",
    "list-runtime-fixture",
    "-Doptimize=fast",
  ],
  stdout: "inherit",
  stderr: "inherit",
}).output();
if (!result.success) Deno.exit(result.code);
await Deno.mkdir(new URL("../build/", import.meta.url), { recursive: true });
