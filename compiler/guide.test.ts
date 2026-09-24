import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { createSourceCompiler } from "./source.ts";
import { createNativeCompiler } from "./native.ts";
import { loadSourceProject } from "./source_project.ts";

Deno.test("CLI guide examples compile with native and JavaScript parity", async () => {
  const guide = await Deno.readTextFile(new URL("./guide.md", import.meta.url));
  const examples = [...guide.matchAll(/```blot\n([\s\S]*?)\n```/g)];
  ok(examples.length > 0);
  const reference = await createSourceCompiler();
  const native = await createNativeCompiler();
  try {
    for (const [index, [, source]] of examples.entries()) {
      const entry = new URL(`./guide_example_${index}.blot`, import.meta.url);
      const project = await loadSourceProject(entry, {
        imports: { "std/": new URL("../std/", import.meta.url) },
        readSource: (url) =>
          url.href === entry.href
            ? Promise.resolve(source)
            : Deno.readTextFile(url),
      });
      const artifact = reference.compile(project);
      equal(await native.compile(project), artifact, `guide example ${index}`);
      ok(WebAssembly.validate(artifact.bytes), `guide example ${index}`);
    }
  } finally {
    reference.dispose();
    await native.dispose();
  }
});
