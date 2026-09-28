// This suite must run BEFORE generating any JavaScript reference modules.
import { deepStrictEqual as equal, rejects } from "node:assert/strict";
import { createNativeCompiler } from "../compiler/native.ts";
import { createNativeIncrementalCompiler } from "../compiler/native_incremental.ts";
import { createNativeProjectCompiler } from "../compiler/native_project.ts";
import { runCli } from "../compiler/cli.ts";
import { includesAnalysis } from "../compiler/options.ts";

const options = {
  executable: new URL("./zig-out/bin/blotc-zig", import.meta.url),
  prelude: "none" as const,
  threads: 4,
};
async function answer(bytes: Uint8Array<ArrayBuffer>) {
  const { instance } = await WebAssembly.instantiate(bytes);
  return (instance.exports.answer as () => number)();
}

Deno.test("Zig stateless API runs with no generated JS reference", async () => {
  const compiler = await createNativeCompiler(options);
  try {
    equal(
      await answer(
        (await compiler.compile("entry const answer = fn () => 42")).bytes,
      ),
      42,
    );
    equal((await compiler.analyze("const n = 1")).constants.length, 0);
    await rejects(() =>
      compiler.compile("entry const answer = fn () => missing")
    );
    equal(
      await answer(
        (await compiler.compile("entry const answer = fn () => 7", {
          analysis: false,
        })).bytes,
      ),
      7,
    );
  } finally {
    await compiler.dispose();
  }
});

Deno.test("Zig retained API survives changed and failed revisions without JS", async () => {
  const compiler = await createNativeIncrementalCompiler(options);
  try {
    equal(
      await answer(
        (await compiler.compile("entry const answer = fn () => 42")).artifact
          .bytes,
      ),
      42,
    );
    await rejects(() =>
      compiler.compile("entry const answer = fn () => missing")
    );
    equal(
      await answer(
        (await compiler.compile("entry const answer = fn () => 43")).artifact
          .bytes,
      ),
      43,
    );
  } finally {
    await compiler.dispose();
  }
});

Deno.test("Zig project API imports and recycles sessions without JS", async () => {
  const entry = new URL("file:///virtual-zig/main.blot");
  const library = new URL("file:///virtual-zig/lib.blot");
  const files = new Map([
    [
      entry.href,
      'import * as lib from "./lib"\nentry const answer = fn () => lib.value ()',
    ],
    [library.href, "const value = fn () => 42"],
  ]);
  const compiler = await createNativeProjectCompiler({
    ...options,
    maxRevisions: 1,
    readSource: async (url: URL) => {
      const source = files.get(url.href);
      if (source === undefined) {
        throw new Error(`Missing virtual module ${url}`);
      }
      return source;
    },
  });
  try {
    equal(await answer((await compiler.compile(entry)).artifact.bytes), 42);
    files.set(library.href, "const value = fn () => 43");
    equal(await answer((await compiler.compile(entry)).artifact.bytes), 43);
  } finally {
    await compiler.dispose();
  }
  equal(typeof runCli, "function");
  equal(includesAnalysis({}), true);
  equal(includesAnalysis({ analysis: false }), false);
});
