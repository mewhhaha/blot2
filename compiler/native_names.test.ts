import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { createNativeCompiler } from "./native.ts";
import { createSourceCompiler } from "./source.ts";
import { loadSourceProject } from "./source_project.ts";

for (const threads of [1, 4]) {
  Deno.test(`native ${threads}-thread names retain exact Unicode and shared-prefix identity`, async () => {
    const prefix = "shared_".repeat(32);
    const entry = new URL("file:///virtual-names/main.blot");
    const files = new Map([
      [
        entry.href,
        'import * as first from "./café"\nimport * as second from "./café"\nconst answer = fn () => @u32.add (first.value ()) (second.value ())\n',
      ],
      [new URL("./café.blot", entry).href, "const value = fn () => 17\n"],
      [new URL("./café.blot", entry).href, "const value = fn () => 25\n"],
    ]);
    const project = await loadSourceProject(entry, {
      readSource: (url) => {
        const source = files.get(url.href);
        if (source === undefined) {
          throw new Error(`Missing source: ${url.href}`);
        }
        return Promise.resolve(source);
      },
    });
    const sharedPrefixSource =
      `const ${prefix}x = fn () => 17\nconst ${prefix}y = fn () => 25\nconst answer = fn () => @u32.add (${prefix}x ()) (${prefix}y ())\n`;
    const sources = [
      sharedPrefixSource,
      "const identity = fn (x: U32) => x\nconst answer = fn () => identity (identity 42)\n",
      project,
    ];
    const native = await createNativeCompiler({ threads, prelude: "none" });
    const js = await createSourceCompiler({ prelude: "none" });
    try {
      for (const source of sources) {
        const artifact = await native.compile(source);
        equal(artifact.bytes, js.compile(source).bytes);
        const instance = new WebAssembly.Instance(
          new WebAssembly.Module(artifact.bytes),
        );
        const answer = instance.exports.answer;
        ok(typeof answer === "function");
        equal(answer(), 42);
      }
      // Base.String.cmp in the JS reference overflows at this length. Check
      // native ownership and stack safety directly using the guest result.
      const long = await native.compile(
        sharedPrefixSource.replaceAll(prefix, prefix.repeat(20)),
      );
      const instance = new WebAssembly.Instance(
        new WebAssembly.Module(long.bytes),
      );
      const answer = instance.exports.answer;
      ok(typeof answer === "function");
      equal(answer(), 42);
    } finally {
      js.dispose();
      await native.dispose();
    }
  });
}
