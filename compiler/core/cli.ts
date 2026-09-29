import { runCli } from "../cli.ts";

// Select the experimental native backend explicitly. Never install it over the
// default compiler or silently retry another backend when this one is missing.
if (import.meta.main) {
  Deno.exitCode = await runCli(new URL("./_build/blotc", import.meta.url));
}
