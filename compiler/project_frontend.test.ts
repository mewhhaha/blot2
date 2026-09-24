import { deepStrictEqual as equal, ok, rejects } from "node:assert/strict";
import { CompilerError } from "./diagnostics.ts";
import { createProjectFrontend } from "./project_frontend.ts";
import { createSourceProjectLoader } from "./source_project.ts";
import { SourceError } from "./syntax.ts";

const entry = new URL("file:///virtual-project/main.blot");
const library = new URL("file:///virtual-project/lib.blot");

Deno.test("project frontend retains declaration identities and remaps imported diagnostics after edits", async () => {
  const files = new Map([
    [
      entry.href,
      'import * as lib from "./lib"\nconst answer = fn () => lib.value ()\n',
    ],
    [library.href, "const value = fn () => 42\n"],
  ]);
  const loader = await createSourceProjectLoader({
    readSource(url) {
      const source = files.get(url.href);
      if (source === undefined) throw new Error(`Missing ${url}`);
      return Promise.resolve(source);
    },
  });
  const frontend = await createProjectFrontend({ prelude: "none" });
  try {
    const first = frontend.prepare(await loader.load(entry));
    const shifted = "// changed physical offsets\n" + files.get(library.href)!;
    files.set(library.href, shifted);
    const second = frontend.prepare(await loader.load(entry));
    equal(
      second.declarations.map((node) => node.offset),
      first.declarations.map((node) => node.offset),
    );
    equal(second.root, first.root);
    try {
      second.translate(
        new CompilerError({
          code: "test_diagnostic",
          subject: "$module[lib.blot].value",
          message: "test",
        }),
      );
      throw new Error("Expected translated diagnostic");
    } catch (error) {
      ok(error instanceof SourceError, String(error));
      equal(error.code, "test_diagnostic");
      equal(error.origin?.filename, "/virtual-project/lib.blot");
      equal(error.origin?.source, shifted);
      equal(error.start, shifted.indexOf("value"));
    }

    files.set(library.href, "const =\n");
    await rejects(() => loader.load(entry), (error) => {
      ok(error instanceof SourceError, String(error));
      equal(error.origin?.filename, "/virtual-project/lib.blot");
      return true;
    });
    files.set(library.href, shifted);
    const recovered = frontend.prepare(await loader.load(entry));
    equal(recovered.root, second.root);
  } finally {
    frontend.dispose();
    loader.dispose();
  }
});
