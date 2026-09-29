import { deepStrictEqual as equal, ok, rejects } from "node:assert/strict";
import { createNativeCompiler } from "./native.ts";
import { createSourceCompiler } from "./source.ts";
import { loadSourceProject } from "./source_project.ts";
import { SourceError } from "./syntax.ts";

Deno.test("marked constructors preserve types, partial application and qualified patterns on both backends", async () => {
  const files: Record<string, string> = {
    "values.blot": `
type Maybe x is data = #Some x | #Nothing
type Point is data = #Point { x: U32 }
type Body is data = #Body { position: Point }
const body = #Body { position: #Point { x: 42 } }
`,
    "main.blot": `
import * as values from "./values"
const wrap = #values.Some
const inspect = fn (value: values.Maybe U32) => case value of
  #values.Some value if value > 0 => value
  #values.Some _ | #values.Nothing => 0
entry const answer = fn value => inspect (wrap value)
entry const selector = fn () => .position.x values.body
entry const truth = fn value => case value of
  #True => #False
  #False => #True
`,
  };
  const project = await loadSourceProject(
    new URL("file:///constructors/main.blot"),
    {
      readSource: (url) =>
        Promise.resolve(files[url.pathname.split("/").at(-1)!]),
    },
  );
  const reference = await createSourceCompiler();
  const native = await createNativeCompiler();
  try {
    const expected = reference.compile(project);
    equal(await native.compile(project), expected);
    const { exports } = new WebAssembly.Instance(
      new WebAssembly.Module(expected.bytes),
    );
    equal((exports.answer as CallableFunction)(42), 42);
    equal((exports.selector as CallableFunction)(), 42);
    equal((exports.truth as CallableFunction)(0), 1);
    for (const compiler of [reference, native]) {
      for (
        const source of [
          "type Choice is data = Choice\n",
          "type Choice is data = #Choice\nentry const value = Choice\n",
          "type Choice is data = #Choice U32\nentry const value = Choice 1\n",
          "type Point is data = #Point { x: U32 }\nentry const value = Point { x: 1 }\n",
          "type Choice is data = #Choice\nconst inspect = fn value => case value of\n  Choice => 1\n",
          "entry const value = True\n",
          "const number = 1\nentry const invalid = #number\n",
        ]
      ) {
        await rejects(async () => await compiler.compile(source), (error) => {
          ok(error instanceof SourceError, String(error));
          return true;
        });
      }
      for (
        const value of [
          "values.Some 42",
          "values.Some",
          "values.Point { x: 42 }",
        ]
      ) {
        const unmarked = await loadSourceProject(
          new URL("file:///constructors/main.blot"),
          {
            readSource: (url) =>
              Promise.resolve(
                url.pathname.endsWith("/main.blot")
                  ? `import * as values from "./values"\nentry const value = ${value}\n`
                  : files["values.blot"],
              ),
          },
        );
        await rejects(async () => await compiler.compile(unmarked), (error) => {
          ok(error instanceof SourceError);
          equal(error.code, "constructor_marker");
          return true;
        });
      }
    }
  } finally {
    reference.dispose();
    await native.dispose();
  }
});
