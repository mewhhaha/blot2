import { runCli } from "../compiler/cli.ts";

Deno.exit(
  await runCli(Deno.args, {
    executable: new URL("./zig-out/bin/blotc-zig", import.meta.url),
  }),
);
