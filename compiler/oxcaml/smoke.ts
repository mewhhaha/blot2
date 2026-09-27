import { deepStrictEqual as equal, rejects } from "node:assert/strict";
import { createNativeCompiler } from "../native.ts";
import { createNativeIncrementalCompiler } from "../native_incremental.ts";

const executable = Deno.args[0] ?? new URL("./_build/blotc", import.meta.url);
let checks = 0;
for (const prelude of ["none", "default"] as const) {
  const compiler = await createNativeCompiler({ executable, prelude });
  const session = await createNativeIncrementalCompiler({ executable, prelude });
  try {
    for (const name of ["scalar", "generic_effects", ...(prelude === "default" ? ["prelude"] : [])]) {
      const source = await Deno.readTextFile(new URL(`../../examples/${name}.blot`, import.meta.url));
      const artifact = await compiler.compile(source);
      const cached = await session.compile(source);
      equal(cached.artifact.bytes, artifact.bytes); checks++;
      const warm = await session.compile(source);
      equal(warm.artifact, cached.artifact); checks++;
      const { instance } = await WebAssembly.instantiate(artifact.bytes);
      equal((instance.exports.answer as CallableFunction)(), 42); checks++;
      console.log(`${name}/${prelude}: answer=42, ${artifact.bytes.length} Wasm bytes`);
    }
    const source = "entry const answer = fn () => 42\n";
    const first = await session.compile(source);
    equal((await session.compile(source.replace("42", "43"))).artifact, await compiler.compile(source.replace("42", "43"))); checks++;
    await rejects(() => session.compile("entry const answer = fn () => missing\n")); checks++;
    equal((await session.compile(source)).artifact, first.artifact); checks++;
    const compact = await compiler.compile(source, { analysis: false });
    equal(compact.bytes, first.artifact.bytes); checks++;
    equal(Object.hasOwn(compact, "analysis"), false); checks++;
  } finally {
    await session.dispose();
    await compiler.dispose();
  }
}
console.log(`${checks} source, Wasm, and incremental smoke checks passed without a JavaScript compiler artifact`);
