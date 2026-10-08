// Lint the native compiler with zig-analyzer. The executable comes from
// $ZIG_ANALYZER, else the sibling checkout's build. Any finding fails the run.
import { fileURLToPath } from "node:url";

const root = new URL("../", import.meta.url);
const analyzer = Deno.env.get("ZIG_ANALYZER") ??
  fileURLToPath(new URL("../zig-analyzer/zig-out/bin/zig-analyzer", root));
let result: Deno.CommandOutput;
try {
  result = await new Deno.Command(analyzer, {
    cwd: fileURLToPath(root),
    args: ["check", "zig-native/src"],
    stdout: "inherit",
    stderr: "inherit",
  }).output();
} catch (error) {
  if (!(error instanceof Deno.errors.NotFound)) throw error;
  throw new Error(
    `zig-analyzer not found at ${analyzer}; build it or set ZIG_ANALYZER`,
  );
}
if (!result.success) Deno.exit(result.code);
