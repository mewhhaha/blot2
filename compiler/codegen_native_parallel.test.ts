import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { createNativeCompiler } from "./native.ts";
import { createNativeIncrementalCompiler } from "./native_incremental.ts";
import { createSourceCompiler } from "./source.ts";

function workload(edited: boolean, reversed: boolean): string {
  const names = Array.from({ length: 12 }, (_, index) => "helper_" + index);
  const declarations = names.map((name, index) => {
    const last = index + (edited && index % 2 === 0 ? 100 : 0);
    const fields = [...Array(159).fill("0"), String(last)].join(", ");
    return `fn ${name} () => @array.get [${fields}] 159`;
  });
  let answer = "0";
  for (const name of names) answer = `@u32.add (${name} ()) (${answer})`;
  return [
    ...(reversed ? declarations.toReversed() : declarations),
    `export fn answer () => ${answer}`,
    "",
  ].join("\n");
}

for (const threads of [1, 4]) {
  Deno.test(`native ${threads}-thread codegen compiles only independent cache misses`, async () => {
    const clean = await createNativeCompiler({ prelude: "none", threads });
    const session = await createNativeIncrementalCompiler({
      prelude: "none",
      threads,
    });
    const js = await createSourceCompiler({ prelude: "none" });
    try {
      for (
        const [source, expected, fresh, reused] of [
          [workload(false, false), 66, 13, 0],
          [workload(true, false), 666, 6, 7],
          [workload(true, false), 666, 0, 13],
          [workload(true, true), 666, 0, 13],
        ] as const
      ) {
        const result = await session.compile(source);
        const reference = js.compile(source);
        equal(result.artifact.bytes, reference.bytes);
        equal((await clean.compile(source)).bytes, reference.bytes);
        equal(result.stats.entries_compiled, fresh);
        equal(result.stats.entries_reused, reused);
        const { instance } = await WebAssembly.instantiate(
          result.artifact.bytes,
        );
        const answer = instance.exports.answer;
        ok(typeof answer === "function");
        equal(answer(), expected);
      }
    } finally {
      js.dispose();
      await session.dispose();
      await clean.dispose();
    }
  });
}
