import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { createSourceCompiler } from "./source.ts";

Deno.test("wide arrays compile with an unused effect family", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    const literals = Array.from({ length: 8192 }, (_, index) => index).join(
      ",",
    );
    const source = "type Get a is effect = Unit -> a\n" +
      "const values = fn () => [" + literals + "]\n" +
      "const answer = fn () => @array.get (values ()) 8191\n";
    const artifact = compiler.compile(source);
    ok(WebAssembly.validate(artifact.bytes));
    const answer = new WebAssembly.Instance(
      new WebAssembly.Module(artifact.bytes),
    ).exports.answer;
    ok(typeof answer === "function");
    equal(answer(0), 8191);
  } finally {
    compiler.dispose();
  }
});
