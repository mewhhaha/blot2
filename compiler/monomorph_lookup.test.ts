import { deepStrictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { type BendList, bendList } from "./bend_list.ts";

type Node = { readonly $: string; readonly [field: string]: unknown };
type Maybe<T> = { readonly $: "Some"; readonly value: T } | {
  readonly $: "None";
};
type Result<T> = { readonly $: "Done"; readonly value: T } | {
  readonly $: "Fail";
  readonly error: Node;
};

const mono = compiled as unknown as {
  "monomorph.renamed"(names: BendList<Node>, wanted: string): Maybe<string>;
  "monomorph.lookup"(
    functions: BendList<Node>,
    wanted: string,
  ): Result<Node>;
  "monomorph.lookup_constant"(
    constants: BendList<Node>,
    wanted: string,
  ): Maybe<Node>;
  "monomorph.local_template"(
    locals: BendList<Node>,
    wanted: string,
  ): Maybe<Node>;
  "monomorph.family_declaration"(
    declarations: BendList<Node>,
    wanted: Node,
  ): Result<Node>;
};

// A first match may inspect the next list node's shape while entering the
// recursive helper, but must not continue scanning the suffix.
function unreadTail<T>(): BendList<T> {
  return new Proxy({ $: "Nil" } as BendList<T>, {
    get() {
      throw new Error("lookup traversed past its first match");
    },
  });
}

function withUnreadTail<T>(head: T): BendList<T> {
  return {
    $: "Con",
    head,
    tail: { $: "Con", head, tail: unreadTail<T>() },
  };
}

const expression = (value: number): Node => ({ $: "U32Expr", value });
const constant = (name: string, value: number): Node => ({
  $: "Constant",
  name,
  exported: false,
  annotation: { $: "None" },
  value: expression(value),
});
const func = (name: string, value: number): Node => ({
  $: "Function",
  name,
  exported: false,
  parameter: "argument",
  parameter_type: { $: "None" },
  result_type: { $: "None" },
  body: expression(value),
});
const identity = (declaration: string): Node => ({
  $: "TypeId",
  module_name: "test",
  declaration,
});
const operation = (declaration: string, parameter: number): Node => ({
  $: "OperationTemplate",
  identity: identity(declaration),
  parameters: 1n,
  parameter: { $: "ParameterTy", index: BigInt(parameter) },
  result: { $: "UnitTy" },
});

Deno.test("specialization scope lookups stop at the first binding", () => {
  const rename = { $: "Rename", original: "target", specialized: "first" };
  const functionBinding = func("target", 1);
  const constantBinding = constant("target", 2);
  const local = { $: "LocalTemplate", name: "target", value: expression(3) };
  const effect = operation("target", 0);

  equal(mono["monomorph.renamed"](withUnreadTail(rename), "target"), {
    $: "Some",
    value: "first",
  });
  equal(mono["monomorph.lookup"](withUnreadTail(functionBinding), "target"), {
    $: "Done",
    value: functionBinding,
  });
  equal(
    mono["monomorph.lookup_constant"](
      withUnreadTail(constantBinding),
      "target",
    ),
    { $: "Some", value: constantBinding },
  );
  equal(mono["monomorph.local_template"](withUnreadTail(local), "target"), {
    $: "Some",
    value: local.value,
  });
  equal(
    mono["monomorph.family_declaration"](
      withUnreadTail(effect),
      identity("target"),
    ),
    { $: "Done", value: effect },
  );
});

Deno.test("specialization lookups retain first-binding priority and missing diagnostics", () => {
  equal(
    mono["monomorph.renamed"](
      bendList([
        { $: "Rename", original: "other", specialized: "skip" },
        { $: "Rename", original: "target", specialized: "first" },
        { $: "Rename", original: "target", specialized: "last" },
      ]),
      "target",
    ),
    { $: "Some", value: "first" },
  );

  const firstFunction = func("target", 1);
  equal(
    mono["monomorph.lookup"](
      bendList([
        func("other", 0),
        firstFunction,
        func("target", 2),
      ]),
      "target",
    ),
    { $: "Done", value: firstFunction },
  );
  equal(mono["monomorph.lookup"](bendList([func("other", 0)]), "target"), {
    $: "Fail",
    error: {
      $: "Diagnostic",
      code: "unknown_function",
      subject: "target",
      message: "missing function during specialization",
    },
  });

  const firstConstant = constant("target", 1);
  equal(
    mono["monomorph.lookup_constant"](
      bendList([
        constant("other", 0),
        firstConstant,
        constant("target", 2),
      ]),
      "target",
    ),
    { $: "Some", value: firstConstant },
  );
  equal(
    mono["monomorph.lookup_constant"](
      bendList([
        constant("other", 0),
      ]),
      "target",
    ),
    { $: "None" },
  );

  const firstLocal = expression(1);
  equal(
    mono["monomorph.local_template"](
      bendList([
        { $: "LocalTemplate", name: "other", value: expression(0) },
        { $: "LocalTemplate", name: "target", value: firstLocal },
        { $: "LocalTemplate", name: "target", value: expression(2) },
      ]),
      "target",
    ),
    { $: "Some", value: firstLocal },
  );
  equal(mono["monomorph.local_template"](bendList([]), "target"), {
    $: "None",
  });

  const firstOperation = operation("target", 1);
  equal(
    mono["monomorph.family_declaration"](
      bendList([
        {
          $: "Operation",
          identity: identity("target"),
          parameter: {
            $: "UnitTy",
          },
          result: { $: "UnitTy" },
        },
        operation("other", 0),
        firstOperation,
        operation("target", 2),
      ]),
      identity("target"),
    ),
    { $: "Done", value: firstOperation },
  );
  equal(
    mono["monomorph.family_declaration"](
      bendList([
        operation("other", 0),
      ]),
      identity("target"),
    ),
    {
      $: "Fail",
      error: {
        $: "Diagnostic",
        code: "unknown_effect",
        subject: "test::target",
        message: "no declared effect operation matches this family member",
      },
    },
  );
});
