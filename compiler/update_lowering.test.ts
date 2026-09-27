import { toBendCst } from "./bend_abi.ts";
import { deepStrictEqual as equal, ok } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { bendArray, type BendList, bendList } from "./bend_list.ts";
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
  "groups.check_group"(module: Node, imports: BendList<Node>): Result<Node>;
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

async function lowered(source: string, name: string): Promise<{
  module: Node;
  body: Node;
}> {
  const frontend = await createSourceFrontend({ prelude: "none" });
  try {
    const input = frontend.prepare(source);
    const result = api["lower.source_module"](
      toBendCst(input.root),
      toBendCst(input.prelude),
      input.nodeCount,
    );
    equal(result.$, "Done", source);
    if (result.$ !== "Done") throw new Error("lowering failed");
    const functionValue = bendArray(result.value.functions as BendList<Node>)
      .find((item) => item.name === name);
    ok(functionValue, `missing lowered function ${name}`);
    return { module: result.value, body: functionValue.body as Node };
  } finally {
    frontend.dispose();
  }
}

function members(body: Node, dispatch: string): string[] {
  return descendants(body)
    .filter((node) =>
      node.$ === "model.AssociatedExpr" &&
      (node.dispatch as Node).$ === dispatch
    )
    .map((node) => node.member as string);
}

Deno.test("terminal field replacement needs only its explicit update predicate", async () => {
  const { module, body } = await lowered(
    `
type Box a is data = Box { value: a }
const replace: a -> b -> c where { update "value" a b c } = fn box => fn value => do:
  let current = box
  current.value := value
  return current
`,
    "replace",
  );
  equal(members(body, "model.FieldUpdateDispatch"), ["value"]);
  equal(members(body, "model.MemberDispatch"), []);
  const checked = api["groups.check_group"](module, bendList([]));
  equal(
    checked.$,
    "Done",
    checked.$ === "Fail" ? checked.error.code as string : undefined,
  );
});

Deno.test("terminal self use still reads the old field and requires its predicate", async () => {
  const source = (where: string) => `
const increment: a -> a where { ${where} } = fn box => do:
  let current = box
  current.value := @u32.add self 1
  return current
`;
  const absent = await lowered(source('update "value" a U32 a'), "increment");
  equal(members(absent.body, "model.MemberDispatch"), ["value"]);
  equal(members(absent.body, "model.FieldUpdateDispatch"), ["value"]);
  const missing = api["groups.check_group"](absent.module, bendList([]));
  equal(missing.$, "Fail");
  if (missing.$ === "Fail") equal(missing.error.code, "missing_predicate");

  const complete = await lowered(
    source('field "value" a U32, update "value" a U32 a'),
    "increment",
  );
  equal(api["groups.check_group"](complete.module, bendList([])).$, "Done");
});

Deno.test("nested field update reads its parent, but not an unused old leaf", async () => {
  const { body } = await lowered(
    `
type Inner is data = Inner { value: U32 }
type Outer is data = Outer { inner: Inner }
entry const run = fn () => do:
  let current = Outer { inner: Inner { value: 0 } }
  current.inner.value := 42
  return current.inner.value
`,
    "run",
  );
  const updates = members(body, "model.FieldUpdateDispatch");
  equal(updates, ["inner", "value"]);
  const outer = descendants(body).find((node) =>
    node.$ === "model.AssociatedExpr" &&
    (node.dispatch as Node).$ === "model.FieldUpdateDispatch" &&
    node.member === "inner"
  );
  ok(outer);
  equal(members(outer.right as Node, "model.MemberDispatch"), ["inner"]);
  const leaf = descendants(outer.right).find((node) =>
    node.$ === "model.AssociatedExpr" &&
    (node.dispatch as Node).$ === "model.FieldUpdateDispatch" &&
    node.member === "value"
  );
  ok(leaf);
  equal(members(leaf.right as Node, "model.MemberDispatch"), []);
});

Deno.test("array update still evaluates parent and index before replacement", async () => {
  const { body } = await lowered(
    `
entry const run = fn () => do:
  let values = [0]
  let index = fn () => 0
  let replacement = fn () => 42
  values[index ()] := replacement ()
  return values[0]
`,
    "run",
  );
  const nodes = descendants(body);
  const indexUse = nodes.find((node) =>
    node.$ === "model.UseExpr" &&
    typeof node.name === "string" && node.name.startsWith("$update$index$")
  );
  ok(indexUse);
  ok(descendants(indexUse.value).some((node) => node.$ === "model.ApplyExpr"));
  ok(
    descendants(indexUse.body).some((node) => node.$ === "model.ArraySetExpr"),
  );
  // Reading the old element preserves an out-of-bounds trap before the RHS.
  const priorRead = descendants(indexUse.body).find((node) =>
    node.$ === "model.UseExpr" &&
    (node.value as Node).$ === "model.ArrayGetExpr"
  );
  ok(priorRead);
  ok(descendants(priorRead.body).some((node) => node.$ === "model.ApplyExpr"));
  const parentUse = nodes.find((node) =>
    node.$ === "model.UseExpr" &&
    typeof node.name === "string" && node.name.startsWith("$update$parent$") &&
    descendants(node.body).includes(indexUse)
  );
  ok(parentUse);
});
