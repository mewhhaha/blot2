import { runCli } from "./cli.ts";
import { extractNativeCompiler } from "./packaged_native.ts";

let native: Awaited<ReturnType<typeof extractNativeCompiler>> | undefined;
try {
  if (["check", "build", "dependencies"].includes(Deno.args[0])) {
    native = await extractNativeCompiler();
  }
  Deno.exitCode = await runCli(native?.path);
} finally {
  await native?.dispose();
}
