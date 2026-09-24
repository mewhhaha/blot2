import { deepStrictEqual as equal, ok, rejects } from "node:assert/strict";
import { createNativeIncrementalCompiler } from "./native_incremental.ts";
import { createSourceCompiler } from "./source.ts";
import { SourceError } from "./syntax.ts";

function declarations(changed: ReadonlySet<number>) {
  return Array.from({ length: 64 }, (_, index) =>
    [
      `const entry_${index} = fn value => do:`,
      ...Array.from({ length: 8 }, (_, step) =>
        `  let value_${step} = @u32.add ${
          step === 0 ? "value" : `value_${step - 1}`
        } ${changed.has(index) && step === 0 ? 2 : 1}`),
      "  return value_7",
    ].join("\n"));
}

for (const threads of [1, 2, 4, 8]) {
  Deno.test(`native ${threads}-thread lowering batches preserve cache hits, error order and rollback`, async () => {
    const session = await createNativeIncrementalCompiler({
      prelude: "none",
      threads,
    });
    const js = await createSourceCompiler({ prelude: "none" });
    const even = new Set(Array.from({ length: 32 }, (_, index) => index * 2));
    const all = new Set(Array.from({ length: 64 }, (_, index) => index));
    try {
      for (
        const [changed, fresh] of [[new Set<number>(), 64], [even, 32], [
          all,
          32,
        ]] as const
      ) {
        const source = declarations(changed).join("\n");
        const result = await session.compile(source);
        equal(result.artifact, js.compile(source));
        equal(result.stats.declarations_lowered, fresh);
        equal(result.stats.declarations_reused, 64 - fresh);
        const { instance } = await WebAssembly.instantiate(
          result.artifact.bytes,
        );
        for (let index = 0; index < 64; index++) {
          const entry = instance.exports[`entry_${index}`];
          ok(typeof entry === "function");
          equal(entry(10), changed.has(index) ? 19 : 18);
        }
      }
      const good = declarations(all);
      const broken = good.map((source, index) =>
        even.has(index)
          ? source.replaceAll("@u32.add", "@missing.operation")
          : source
      ).join("\n");
      await rejects(() => session.compile(broken), (error) => {
        ok(error instanceof SourceError);
        equal(error.code, "unknown_intrinsic");
        equal(error.start, broken.indexOf("@missing.operation"));
        return true;
      });
      const restored = await session.compile(good.join("\n"));
      equal(restored.artifact, js.compile(good.join("\n")));
      equal(restored.stats.declarations_lowered, 0);
      equal(restored.stats.declarations_reused, 64);
      const revision = declarations(even).join("\n");
      const recovered = await session.compile(revision);
      equal(recovered.artifact, js.compile(revision));
      equal(recovered.stats.declarations_lowered, 32);
      equal(recovered.stats.declarations_reused, 32);
    } finally {
      js.dispose();
      await session.dispose();
    }
  });
}
