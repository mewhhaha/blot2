import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { createNativeCompiler } from "./native.ts";
import { createNativeIncrementalCompiler } from "./native_incremental.ts";
import { createSourceCompiler } from "./source.ts";

function workload(edited: boolean, reversed: boolean): string {
  const names = Array.from({ length: 32 }, (_, index) => "helper_" + index);
  const declarations = names.map((name, index) => {
    const last = index + (edited && index % 2 === 0 ? 100 : 0);
    const width = index < 8 ? 1024 : 160;
    const fields = [...Array(width - 1).fill("0"), String(last)].join(", ");
    return `entry const ${name} = fn () => @array.get [${fields}] ${width - 1}`;
  });
  let answer = "0";
  for (const name of names) answer = `@u32.add (${name} ()) (${answer})`;
  return [
    ...(reversed ? declarations.toReversed() : declarations),
    `entry const answer = fn () => ${answer}`,
    "",
  ].join("\n");
}

for (const threads of [1, 2, 4, 8]) {
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
          [workload(false, false), 496, 33, 0],
          [workload(true, false), 2096, 16, 17],
          [workload(true, false), 2096, 0, 33],
          [workload(true, true), 2096, 0, 33],
        ] as const
      ) {
        const result = await session.compile(source);
        const reference = js.compile(source);
        equal(result.artifact, reference);
        equal(await clean.compile(source), reference);
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
