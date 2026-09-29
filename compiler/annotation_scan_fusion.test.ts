import { deepStrictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { type BendList, bendList } from "./bend_list.ts";
import { toBendCst } from "./bend_abi.ts";
import { createSourceFrontend } from "./source_frontend.ts";

type Node = { readonly $: string; readonly [field: string]: unknown };
type Result<T> = { readonly $: "Done"; readonly value: T } | {
  readonly $: "Fail";
  readonly error: Node;
};
const api = compiled as unknown as {
  "lower.annotation_scan_work"(
    fuel: bigint,
    work: Node,
  ): Result<BendList<Node>>;
  "source_types.free_variables"(node: unknown, scope: string): Result<unknown>;
  "source_types.scoped_free_variables"(
    node: unknown,
    scope: string,
  ): Result<unknown>;
};
function compare(node: unknown): void {
  const pruned = api["lower.annotation_scan_work"](1048576n, {
    $: "lower.ScanNode",
    node,
    root: true,
  });
  const previous = pruned.$ === "Fail"
    ? pruned
    : api["source_types.free_variables"](
      (pruned.value as { head: Node }).head,
      "scope",
    );
  equal(api["source_types.scoped_free_variables"](node, "scope"), previous);
}
const node = (
  kind: string,
  children: readonly Node[] = [],
  field = "",
  text = "",
  offset = 0n,
): Node => ({
  $: "cst.Cst",
  kind,
  children: bendList(children),
  field,
  text,
  offset,
});
const annotation = (name: string) =>
  node("type_expression", [node("IDENT", [], "", name)]);

Deno.test("annotation scan fusion preserves root, nested binding, row, and diagnostic boundaries", () => {
  const row = node("effect_row", [node("IDENT", [], "tail", "r", 42n)]);
  const malformedRow = node("effect_row", [
    node("IDENT", [], "tail", "r"),
    node("IDENT", [], "tail", "s"),
  ]);
  const cases = [
    node("binding", [annotation("a"), node("binding", [annotation("b")])]),
    node("declaration", [
      annotation("a"),
      node("binding", [annotation("b"), row]),
    ]),
    node("declaration", [annotation("a"), row, annotation("r")]),
    node("declaration", [malformedRow]),
    node("declaration", [node("binding", [malformedRow]), annotation("a")]),
    node("constraint_predicate", [
      node("IDENT", [], "kind", "operation"),
      node("IDENT", [], "arguments", "op"),
      annotation("a"),
    ]),
    node(
      "group",
      Array.from(
        { length: 4096 },
        (_, i) =>
          i % 2 ? annotation("a") : node("binding", [annotation(`t${i}`)]),
      ),
    ),
  ];
  let deep = annotation("a");
  for (let i = 0; i < 512; i++) deep = node("expression", [deep]);
  for (const input of [...cases, deep]) compare(input);
});

Deno.test("annotation scan fusion matches pruning on real parsed declarations", async () => {
  const frontend = await createSourceFrontend({ prelude: "none" });
  try {
    for (
      const source of [
        "const identity = fn (value: a) => value",
        "const check = fn (value: a) => do:\n  let same: a = value\n  let first: b = value\n  let second: b = value\n  return same",
        "entry const result = fn value => do:\n  let local = fn (item: a) => item\n  return local value",
      ]
    ) {
      const prepared = frontend.prepare(source);
      compare(toBendCst(prepared.root));
      const pending = [toBendCst(prepared.root) as unknown as Node];
      while (pending.length) {
        const current = pending.pop()!;
        if (current.kind === "binding" || current.kind === "lambda") {
          compare(current);
        }
        for (
          let children = current.children as BendList<Node>;
          children.$ === "Con";
          children = children.tail
        ) pending.push(children.head);
      }
    }
  } finally {
    frontend.dispose();
  }
});
