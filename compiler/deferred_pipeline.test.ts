import { deepStrictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { toBendCst } from "./bend_abi.ts";
import { createSourceFrontend } from "./source_frontend.ts";

type Node = { readonly $: string; readonly [field: string]: unknown };
type Result<T> = { readonly $: "Done"; readonly value: T } | {
  readonly $: "Fail";
  readonly error: Node;
};
const api = compiled as unknown as {
  "source_modules.source_module"(
    project: boolean,
    root: unknown,
    prelude: unknown,
    fuel: bigint,
  ): Result<Node>;
  compile(module: Node, steps: bigint): Result<Node>;
  compile_source(
    root: unknown,
    prelude: unknown,
    fuel: bigint,
    steps: bigint,
  ): Result<Node>;
};

// Runtime bytes are a deep linked list; flatten that list before the recursive
// assertion so adding runtime code does not exhaust JavaScript's call stack.
function comparable(result: Result<Node>): Result<Node> {
  if (result.$ === "Fail") return result;
  const bytes: unknown[] = [];
  let cursor = result.value.bytes as Node;
  for (; cursor.$ === "Con"; cursor = cursor.tail as Node) {
    bytes.push(cursor.head);
  }
  equal(cursor.$, "Nil");
  return { ...result, value: { ...result.value, bytes } };
}

Deno.test("deferred cold checking matches legacy specialization across effects and closures", async () => {
  const frontend = await createSourceFrontend({ prelude: "none" });
  const cases = [
    `const offset = 2
const make = fn value => fn extra => @u32.add value extra
const saved = make offset
entry const answer = fn () => saved 40
`,
    `effect Reader.ask: Unit -> U32
const ask = fn () => Reader.ask ()
const handler = fn () => 42
const reader = @effect.provider Reader.ask handler
entry const requirement_count = @effect.count (@effect.of ask)
entry const answer = fn () => do reader:
  return ask ()
`,
    `data Maybe a = Some a | Nothing
const identity = fn value => value
entry const answer = fn () => case identity (Some 42) of
  Some number => number
  Nothing => 0
`,
    `entry const answer = fn (flag: Bool) => case flag of
  True => 1
`,
    `const transform = fn value => @u32.add value 1
entry const metadata = fn () => @effect.count (@effect.of transform)
`,
  ];
  try {
    for (const source of cases) {
      const prepared = frontend.prepare(source);
      const root = toBendCst(prepared.root);
      const prelude = toBendCst(prepared.prelude);
      const module = api["source_modules.source_module"](
        false,
        root,
        prelude,
        prepared.nodeCount,
      );
      const legacy = module.$ === "Fail"
        ? module
        : api.compile(module.value, 100_000n);
      const deferred = api.compile_source(
        root,
        prelude,
        prepared.nodeCount,
        100_000n,
      );
      equal(comparable(deferred), comparable(legacy), source);
    }
  } finally {
    frontend.dispose();
  }
});
