import { equal, ok, rejects } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { toBendCst } from "./bend_abi.ts";
import { bendArray, type BendList } from "./bend_list.ts";
import { createNativeCompiler } from "./native.ts";
import { createSourceFrontend } from "./source_frontend.ts";
import { loadSourceProject } from "./source_project.ts";
import { SourceError } from "./syntax.ts";

type Node = { readonly $: string; readonly [field: string]: unknown };
type Result<T> = { readonly $: "Done"; readonly value: T } | {
  readonly $: "Fail";
  readonly error: Node;
};
const api = compiled as unknown as {
  "source_modules.source_module_core"(
    project: boolean,
    root: unknown,
    prelude: unknown,
    fuel: bigint,
  ): Result<Node>;
  "source_modules.sourced_prepared"(sourced: Node): Node;
  "checked_core.prepared_module"(prepared: Node): Node;
};

const executable = new URL("../generated/compiler/blotc", import.meta.url);
const entry = new URL("file:///virtual-schema-evaluation/main.blot");
const library = new URL("file:///virtual-schema-evaluation/schema.blot");

const schema = `type End is data = #End
type Entry { head, tail } is data = #Entry { head, tail }
const End.contains = fn (end: End) => fn witness => #False
const Entry.contains = fn entry => fn witness => do:
  let #Entry { head, tail } = entry
  if #Type head == #Type witness:
    return #True
  return tail.contains(witness)
const schema = #Entry { head: #True, tail: #Entry { head: 7, tail: #End } }
`;

const query = `import * as s from "./schema"
const answer = s.schema.contains(#True)
entry const read_answer = fn () => answer
`;

function project(main: string, imported = schema) {
  const files = new Map([[entry.href, main], [library.href, imported]]);
  return loadSourceProject(entry, {
    readSource: (url: URL) => {
      const source = files.get(url.href);
      if (source === undefined) {
        throw new Error(`missing fixture module ${url}`);
      }
      return Promise.resolve(source);
    },
  });
}

Deno.test("schema selection evaluates typed receiver and witness operands and checks unused source", async () => {
  const compiler = await createNativeCompiler({ executable, threads: 1 });
  const frontend = await createSourceFrontend();
  try {
    async function selectedHelperNames(main: string) {
      const prepared = frontend.prepare(await project(main));
      const lowered = api["source_modules.source_module_core"](
        true,
        toBendCst(prepared.root),
        toBendCst(prepared.prelude),
        prepared.nodeCount,
      );
      equal(lowered.$, "Done", Deno.inspect(lowered));
      if (lowered.$ !== "Done") return [];
      const module = api["checked_core.prepared_module"](
        api["source_modules.sourced_prepared"](lowered.value),
      );
      return bendArray(module.functions as BendList<Node>)
        .map((fn) => fn.name as string)
        .filter((name) => name.startsWith("$schema["));
    }

    ok((await selectedHelperNames(query)).length > 0);
    const ordinary = await compiler.analyze(await project(query));
    ok(
      ordinary.functions.some((fn) => fn.name.startsWith("$schema[")),
      "the companion two-module query must exercise schema selection",
    );

    for (
      const [source, message] of [
        [
          `import * as s from "./schema"
entry const answer = do:
  let witness = do:
    if #True:
      return @panic "witness operand reached"
    return #True
  return s.schema.contains(witness)
`,
          "witness operand reached",
        ],
        [
          `import * as s from "./schema"
entry const answer = do:
  let receiver = do:
    if #True:
      return @panic "receiver operand reached"
    return s.schema
  return receiver.contains(#True)
`,
          "receiver operand reached",
        ],
      ] as const
    ) {
      ok(
        (await selectedHelperNames(source)).length > 0,
        `${message}: schema selection did not reach the panic expression`,
      );
      await rejects(
        async () => compiler.analyze(await project(source)),
        (error) => {
          ok(error instanceof SourceError, String(error));
          equal(error.code, "const_panic");
          equal(error.message, message);
          return true;
        },
      );
    }

    const invalid = `${schema}const unused = fn () => missing_value\n`;
    await rejects(
      async () => compiler.analyze(await project(query, invalid)),
      (error) => {
        ok(error instanceof SourceError, String(error));
        equal(error.code, "unknown_value");
        equal(error.origin?.filename, library.pathname);
        equal(error.origin?.source, invalid);
        return true;
      },
    );
  } finally {
    frontend.dispose();
    await compiler.dispose();
  }
});
