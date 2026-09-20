import { deepStrictEqual as equal, ok, rejects } from "node:assert/strict";
import generated from "../generated/compiler/compiler.js";
import { createSourceFrontend } from "./source_frontend.ts";
import { createNativeCompiler } from "./native.ts";
import { createSourceCompiler } from "./source.ts";
import { SourceError } from "./syntax.ts";
import type { Cst } from "./syntax.ts";
import { bendArray, type BendList, bendList } from "./bend_list.ts";

type Result<T> = { readonly $: "Done"; readonly value: T } | {
  readonly $: "Fail";
  readonly error: unknown;
};
type LowerDeclarations = (
  nodes: BendList<Cst>,
  prefix: string,
  module: string,
  exported: boolean,
  fuel: bigint,
  scope: unknown,
) => Result<unknown>;
const lower = generated as unknown as {
  "lower.prepare_prelude"(root: Cst, fuel: bigint): Result<unknown>;
  "lower.prepare_source"(root: Cst, prelude: unknown): Result<{
    readonly declarations: BendList<Cst>;
    readonly scope: unknown;
  }>;
  "lower.lower_declarations": LowerDeclarations;
  "lower.lower_declarations_sequential": LowerDeclarations;
};

Deno.test("parallel lowering agrees with serial lowering across batch boundaries", async () => {
  const frontend = await createSourceFrontend({ prelude: "none" });
  try {
    for (const count of [0, 1, 4, 5, 17, 64]) {
      const source = Array.from(
        { length: count },
        (_, index) =>
          `export fn entry_${index} value => @u32.add value ${index}`,
      ).join("\n");
      for (const invalid of [false, true]) {
        const prepared = frontend.prepare(
          invalid
            ? source.replaceAll("@u32.add", "@missing.operation")
            : source,
        );
        const prelude = lower["lower.prepare_prelude"](
          prepared.prelude,
          prepared.nodeCount,
        );
        ok(prelude.$ === "Done");
        const plan = lower["lower.prepare_source"](
          prepared.root,
          prelude.value,
        );
        ok(plan.$ === "Done");
        const args = [
          plan.value.declarations,
          "",
          "main",
          true,
          prepared.nodeCount,
          plan.value.scope,
        ] as const;
        equal(
          lower["lower.lower_declarations"](...args),
          lower["lower.lower_declarations_sequential"](...args),
        );
        const declarations = bendArray(plan.value.declarations);
        for (const position of [0, declarations.length - 1]) {
          if (declarations.length === 0) continue;
          const malformed = declarations.map((node, index) =>
            index === position ? { ...node, children: bendList<Cst>([]) } : node
          );
          const malformedArgs = [
            bendList(malformed),
            ...args.slice(1),
          ] as Parameters<LowerDeclarations>;
          equal(
            lower["lower.lower_declarations"](...malformedArgs),
            lower["lower.lower_declarations_sequential"](...malformedArgs),
          );
        }
      }
    }
  } finally {
    frontend.dispose();
  }
});

Deno.test("native lowering preserves ordered artifacts and diagnostics at 1/2/4/8 threads", async () => {
  const source = Array.from(
    { length: 33 },
    (_, index) => `export fn entry_${index} value => @u32.add value ${index}`,
  ).join("\n");
  const invalid = source.replaceAll("@u32.add", "@missing.operation");
  const js = await createSourceCompiler({ prelude: "none" });
  try {
    const expected = js.compile(source);
    let diagnostic: SourceError | undefined;
    try {
      js.compile(invalid);
    } catch (error) {
      ok(error instanceof SourceError);
      diagnostic = error;
    }
    ok(diagnostic);
    for (const threads of [1, 2, 4, 8]) {
      const native = await createNativeCompiler({ prelude: "none", threads });
      try {
        const artifact = await native.compile(source);
        equal(artifact, expected);
        const { instance } = await WebAssembly.instantiate(artifact.bytes);
        for (let index = 0; index < 33; index++) {
          const fn = instance.exports[`entry_${index}`];
          ok(typeof fn === "function");
          equal(fn(10), index + 10);
        }
        await rejects(() => native.compile(invalid), (error) => {
          ok(error instanceof SourceError);
          equal([error.code, error.start, error.message], [
            diagnostic.code,
            diagnostic.start,
            diagnostic.message,
          ]);
          return true;
        });
        equal(await native.compile(source), expected);
      } finally {
        await native.dispose();
      }
    }
  } finally {
    js.dispose();
  }
});
