import { runCli } from "../compiler/cli.ts";

Deno.exitCode = await runCli("zig/zig-out/bin/blotc-zig");
