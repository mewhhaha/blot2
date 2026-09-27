import { toBendCst } from "./bend_abi.ts";
import { deepStrictEqual as equal, ok } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { bendArray, type BendList } from "./bend_list.ts";
import { createSourceFrontend } from "./source_frontend.ts";

type Node = { readonly $: string; readonly [field: string]: unknown };
type Result<T> = { readonly $: "Done"; readonly value: T } | {
  readonly $: "Fail";
  readonly error: Node;
};
const api = compiled as unknown as {
  "lower.source_module"(
    root: unknown,
    prelude: unknown,
    fuel: bigint,
  ): Result<Node>;
};

function descendants(root: unknown): Node[] {
  const found: Node[] = [];
  const visit = (value: unknown): void => {
    if (typeof value !== "object" || value === null) return;
    if (Array.isArray(value)) {
      for (const item of value) visit(item);
      return;
    }
    const node = value as Node;
    if (typeof node.$ === "string") found.push(node);
    for (const child of Object.values(node)) visit(child);
  };
  visit(root);
  return found;
}

Deno.test("local annotations reuse enclosing names and scope fresh names locally", async () => {
  const frontend = await createSourceFrontend({ prelude: "none" });
  try {
    const input = frontend.prepare(`
const check = fn (value: a) => do:
  let same: a = value
  let first: b = value
  let second: b = value
  return same
`);
    const lowered = api["lower.source_module"](
      toBendCst(input.root),
      toBendCst(input.prelude),
      input.nodeCount,
    );
    equal(lowered.$, "Done");
    if (lowered.$ !== "Done") throw new Error("source lowering failed");
    const check = bendArray(lowered.value.functions as BendList<Node>)
      .find((value) => value.name === "check");
    ok(check);
    const free = descendants(check).filter((value) =>
      value.$ === "model.FreeTy"
    );
    const outer = free.filter((value) => value.name === "a");
    ok(outer.length >= 2);
    equal(new Set(outer.map((value) => value.scope)).size, 1);
    equal(outer[0].scope, "check");
    const local = free.filter((value) => value.name === "b");
    equal(local.length, 2);
    equal(new Set(local.map((value) => value.scope)).size, 2);
    for (const variable of local) {
      ok(typeof variable.scope === "string");
      ok((variable.scope as string).startsWith("$let$"));
    }
  } finally {
    frontend.dispose();
  }
});
