// Build the Blot compiler, which is written in Goose (compiler-goose/).
//   build_compiler.ts        the optimized compiler, about seven minutes
//   build_compiler.ts --dev  the debug compiler, about a minute and a half
// The first build also builds the patched Goose compiler it needs. Both need
// clang, cmake, ninja and Python 3.
import { fileURLToPath } from "node:url";

export const releaseCompiler = "compiler-goose/build/blotc-goose";
export const developmentCompiler = "compiler-goose/build/blotc-goose-dev";

/** The command that builds one of the two compilers, run from the repository root. */
export function buildCommand(development: boolean): string[] {
  const command = ["sh", "compiler-goose/build.sh"];
  if (development) command.push("--output", developmentCompiler);
  else command.push("--release");
  return command;
}

if (import.meta.main) {
  let development = false;
  for (const argument of Deno.args) {
    if (argument === "--dev") development = true;
    else throw new Error(`Unknown argument: ${argument}`);
  }
  const root = fileURLToPath(new URL("../", import.meta.url));
  const command = buildCommand(development);
  const result = await new Deno.Command(command[0], {
    cwd: root,
    args: command.slice(1),
    stdout: "inherit",
    stderr: "inherit",
  }).output();
  if (!result.success) Deno.exit(result.code);
  let executable = releaseCompiler;
  if (development) executable = developmentCompiler;
  console.log(`Compiler executable: ${root}${executable}`);
}
