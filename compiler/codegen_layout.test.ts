import { deepStrictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { type BendList, bendList } from "./bend_list.ts";

type Node = { readonly $: string; readonly [name: string]: unknown };
const n = ($: string, fields: Record<string, unknown> = {}): Node => ({
  $,
  ...fields,
});
const scalar = n("codegen_layout.Scalar");
const unknown = n("codegen_layout.Unknown");
const array = n("codegen_layout.ScalarArray");
const product = (fields: Node[]) =>
  n("codegen_layout.Product", { fields: bendList(fields) });
const expr = (name: string, fields: Record<string, unknown> = {}) =>
  n(`codegen_ir.${name}Expr`, fields);
const local = (name: string) => expr("Local", { name });
const integer = (value: number) => expr("U32", { value });
const letIn = (name: string, value: Node, body: Node) =>
  expr("Let", { name, value, body });
const choose = (consequent: Node, alternative: Node) =>
  expr("If", { condition: local("condition"), consequent, alternative });
const tuple = (elements: Node[]) =>
  expr("Product", { elements: bendList(elements) });
const fill = (value: Node) => expr("ArrayFill", { count: integer(64), value });
const get = (array: Node) => expr("ArrayGet", { array, index: integer(0) });
const binding = (name: string) => n("model.BindingPattern", { name });
const patterns = (elements: Node[]) =>
  n("model.ProductPattern", { elements: bendList(elements) });

const backend = compiled as unknown as {
  "codegen_layout.empty"(): Node;
  "codegen_layout.expression"(fuel: bigint, expr: Node, locals: Node): Node;
  "codegen_layout.infer"(fuel: bigint, work: Node, locals: Node): Node;
  "codegen_layout.scalar_fields"(shape: Node): boolean;
  "codegen_layout.bind"(locals: Node, name: string, shape: Node): Node;
  "codegen_layout.find"(locals: Node, name: string): Node;
  "codegen_layout.pattern"(
    fuel: bigint,
    pattern: Node,
    shape: Node,
    locals: Node,
  ): Node;
  "codegen_layout.patterns"(
    fuel: bigint,
    patterns: BendList<Node>,
    shapes: BendList<Node>,
    locals: Node,
  ): Node;
  "codegen_layout.meet"(fuel: bigint, left: Node, right: Node): Node;
};
const empty = () => backend["codegen_layout.empty"]();
const infer = (expr: Node, locals = empty(), fuel = 32n) =>
  backend["codegen_layout.expression"](fuel, expr, locals);

Deno.test("codegen layout propagates lexical scalar, product and array provenance", () => {
  equal(infer(letIn("x", integer(65552), local("x"))), scalar);
  equal(infer(choose(integer(1), integer(2))), scalar);
  equal(infer(tuple([integer(1), fill(integer(7))])), product([scalar, array]));
  equal(
    infer(
      letIn(
        "p",
        tuple([integer(1), fill(integer(7))]),
        expr("Project", { value: local("p"), index: 0n }),
      ),
    ),
    scalar,
  );
  equal(infer(letIn("a", fill(integer(7)), get(local("a")))), scalar);
  equal(
    infer(
      choose(tuple([integer(1), local("x")]), tuple([integer(2), integer(3)])),
    ),
    product([scalar, unknown]),
  );
  equal(
    infer(expr("Sequence", { first: fill(integer(9)), next: integer(2) })),
    scalar,
  );
});

Deno.test("codegen layout never guesses unknown words, calls, captures or control-flow results", () => {
  for (
    const value of [
      local("x"),
      expr("Constant", { name: "x" }),
      expr("Closure", { key: "lambda:0", captures: bendList(["x"]) }),
      expr("Call", { key: "fn:f", argument: integer(1) }),
      expr("Apply", { callee: local("f"), argument: integer(1) }),
      get(local("a")),
      expr("Project", { value: local("p"), index: 0n }),
      expr("Block", {
        label: 1n,
        body: expr("Sequence", {
          first: expr("Return", { label: 1n, value: fill(integer(1)) }),
          next: integer(0),
        }),
      }),
      expr("For", {
        index: "i",
        start: integer(0),
        end: integer(3),
        state: "s",
        initial: integer(0),
        body: local("s"),
      }),
      expr("Forever", {
        state: "s",
        initial: integer(0),
        body: local("s"),
        compact: true,
      }),
    ]
  ) {
    equal(infer(value), unknown, value.$);
  }
  equal(infer(choose(integer(1), local("x"))), unknown);
  equal(infer(choose(local("x"), integer(1))), unknown);
  equal(
    infer(letIn("x", integer(7), letIn("x", local("y"), local("x")))),
    unknown,
  );
  equal(
    infer(letIn("x", integer(7), letIn("x", fill(integer(7)), local("x")))),
    array,
  );
  equal(infer(fill(fill(integer(7)))), unknown);
  equal(
    infer(
      expr("Array", { elements: bendList([integer(7), fill(integer(7))]) }),
    ),
    unknown,
  );
});

Deno.test("codegen layout patterns shadow outer facts including unknown and constructor payloads", () => {
  const outer = backend["codegen_layout.bind"](empty(), "x", scalar);
  const inner = backend["codegen_layout.pattern"](
    32n,
    binding("x"),
    unknown,
    outer,
  );
  equal(backend["codegen_layout.find"](inner, "x"), unknown);
  equal(backend["codegen_layout.find"](outer, "x"), scalar);
  const bound = backend["codegen_layout.pattern"](
    32n,
    patterns([binding("x"), patterns([binding("y"), binding("z")])]),
    product([array, product([scalar, unknown])]),
    outer,
  );
  equal(backend["codegen_layout.find"](bound, "x"), array);
  equal(backend["codegen_layout.find"](bound, "y"), scalar);
  equal(backend["codegen_layout.find"](bound, "z"), unknown);
  const payload = backend["codegen_layout.pattern"](
    32n,
    n("model.ConstructorPattern", {
      constructor: "Box",
      payload: n("Some", { value: binding("x") }),
    }),
    unknown,
    outer,
  );
  equal(backend["codegen_layout.find"](payload, "x"), unknown);
  const missing = backend["codegen_layout.patterns"](
    32n,
    bendList([binding("x")]),
    bendList([]),
    outer,
  );
  equal(backend["codegen_layout.find"](missing, "x"), unknown);
});

Deno.test("codegen layout budget exhaustion and differing arities lose facts", () => {
  equal(infer(integer(1), empty(), 0n), unknown);
  const outer = backend["codegen_layout.bind"](empty(), "x", scalar);
  const exhausted = backend["codegen_layout.pattern"](
    0n,
    binding("x"),
    unknown,
    outer,
  );
  equal(backend["codegen_layout.find"](exhausted, "x"), unknown);
  equal(
    backend["codegen_layout.meet"](
      32n,
      product([scalar]),
      product([scalar, scalar]),
    ),
    unknown,
  );
  equal(backend["codegen_layout.meet"](0n, scalar, scalar), unknown);
  const large = backend["codegen_layout.infer"](
    4n,
    n("codegen_layout.Expressions", {
      expressions: bendList(Array.from({ length: 64 }, () => integer(7))),
    }),
    empty(),
  );
  equal(large, unknown);
  equal(backend["codegen_layout.scalar_fields"](large), false);
});
