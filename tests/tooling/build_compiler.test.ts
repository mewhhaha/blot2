import { strict as assert } from "node:assert";
import {
  buildCommand,
  developmentCompiler,
  releaseCompiler,
} from "../../scripts/build_compiler.ts";

Deno.test("the two compilers are built by the one script into separate files", () => {
  assert.deepEqual(buildCommand(false), [
    "sh",
    "compiler-goose/build.sh",
    "--release",
  ]);
  assert.deepEqual(buildCommand(true), [
    "sh",
    "compiler-goose/build.sh",
    "--output",
    developmentCompiler,
  ]);
  assert.notEqual(developmentCompiler, releaseCompiler);
});

Deno.test("the build script rejects an argument it does not know", async () => {
  const result = await new Deno.Command(Deno.execPath(), {
    args: [
      "run",
      "--allow-read",
      new URL("../../scripts/build_compiler.ts", import.meta.url).pathname,
      "--incremental",
    ],
    stdout: "piped",
    stderr: "piped",
  }).output();
  assert.notEqual(result.code, 0);
  assert.match(new TextDecoder().decode(result.stderr), /Unknown argument/);
});
