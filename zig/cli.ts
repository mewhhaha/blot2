import { runCli } from "../compiler/cli.ts";

Deno.exitCode = await runCli(
  new URL("./zig-out/bin/blotc-zig", import.meta.url),
);
