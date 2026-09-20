import { basename, dirname } from "node:path";
import { createNativeCompiler } from "./native.ts";
import { formatDiagnostic } from "./source_frontend.ts";
import { SourceError } from "./syntax.ts";

const [command, filename, output, ...extra] = Deno.args;
if (
  (command !== "check" && command !== "build") || !filename || extra.length ||
  (command === "check" && output)
) {
  console.error(
    "Usage: deno task blot check <source.blot> | build <source.blot> [build/output.wasm]",
  );
  Deno.exit(2);
}

let source = "";
try {
  source = await Deno.readTextFile(filename);
  const compiler = await createNativeCompiler();
  try {
    if (command === "check") {
      const analysis = await compiler.analyze(source);
      console.log(
        `${filename}: checked ${analysis.functions.length} functions, ${analysis.constants.length} constants`,
      );
    } else {
      const artifact = await compiler.compile(source);
      const destination = output ?? `build/${basename(filename, ".blot")}.wasm`;
      await Deno.mkdir(dirname(destination), { recursive: true });
      await Deno.writeFile(destination, artifact.bytes);
      console.log(`${destination}: ${artifact.bytes.length} bytes`);
    }
  } finally {
    await compiler.dispose();
  }
} catch (error) {
  if (error instanceof SourceError) {
    console.error(formatDiagnostic(filename, source, error));
  } else if (
    error instanceof Deno.errors.NotFound ||
    error instanceof Deno.errors.PermissionDenied ||
    error instanceof Deno.errors.NotCapable
  ) {
    console.error(error.message);
  } else throw error;
  Deno.exit(1);
}
