import { runCli } from "./cli.ts";
import { extractNativeCompiler } from "./packaged_native.ts";

export async function runInstalledCli(
  args: string[] = Deno.args,
): Promise<number> {
  if (args.includes("--language=k1")) {
    console.error(
      "The installed CLI does not bundle the experimental K1 compiler",
    );
    return 1;
  }
  let native: Awaited<ReturnType<typeof extractNativeCompiler>> | undefined;
  try {
    // Reject unknown language selections before extracting the legacy compiler.
    if (
      !args.some((arg) => arg.startsWith("--language=")) &&
      ["check", "build", "dependencies"].includes(args[0])
    ) {
      native = await extractNativeCompiler();
    }
    return await runCli(native?.path, args);
  } finally {
    await native?.dispose();
  }
}

if (import.meta.main) Deno.exitCode = await runInstalledCli();
