import { deepStrictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";

type Node = { readonly $: string; readonly [key: string]: unknown };
type List<T> = { readonly $: "Nil" } | {
  readonly $: "Con";
  readonly head: T;
  readonly tail: List<T>;
};
type Result<T> = { readonly $: "Done"; readonly value: T } | {
  readonly $: "Fail";
  readonly error: { readonly code: string };
};
type Module = Node & {
  readonly constants: List<Node>;
  readonly functions: List<Node>;
  readonly data_types: List<Node>;
  readonly operations: List<Node>;
};

const families = compiled as unknown as {
  "effect_families.identity"(
    template: Node,
    arguments_: List<Node>,
  ): Result<Node>;
  "effect_families.prepare"(module: Module): Result<Module>;
  "effect_families.required"(module: Module): boolean;
};

function list<T>(values: readonly T[]): List<T> {
  let result: List<T> = { $: "Nil" };
  for (let index = values.length - 1; index >= 0; index--) {
    result = { $: "Con", head: values[index], tail: result };
  }
  return result;
}

function array<T>(values: List<T>): T[] {
  const result: T[] = [];
  for (let cursor = values; cursor.$ === "Con"; cursor = cursor.tail) {
    result.push(cursor.head);
  }
  return result;
}

const unit = { $: "model.UnitTy" };
const u32 = { $: "model.U32Ty" };
const f32 = { $: "model.F32Ty" };
const parameter = { $: "model.ParameterTy", index: 0n };
const name = (declaration: string, module_name = "main"): Node => ({
  $: "model.TypeId",
  module_name,
  declaration,
});
const template = (
  identity: Node,
  input: Node,
  output: Node,
  parameters = 1n,
): Node => ({
  $: "model.OperationTemplate",
  identity,
  parameters,
  parameter: input,
  result: output,
});
const request = (identity: Node, ty: Node): Node => ({
  $: "model.OperationInstance",
  template: identity,
  arguments: list([ty]),
});
const moduleWith = (
  operations: readonly Node[],
  constants: readonly Node[] = [],
): Module => ({
  $: "model.Module",
  constants: list(constants),
  functions: list([]),
  data_types: list([]),
  operations: list(operations),
});

Deno.test("effect family identities distinguish type arguments and module ownership", () => {
  const identity = families["effect_families.identity"];
  equal(identity(name("State.get"), list([u32])), {
    $: "Done",
    value: name("State.get<1:i>"),
  });
  equal(identity(name("State.get"), list([f32])), {
    $: "Done",
    value: name("State.get<1:f>"),
  });
  equal(identity(name("State.get", "other"), list([u32])), {
    $: "Done",
    value: name("State.get<1:i>", "other"),
  });
});

Deno.test("ordinary effect modules need no family rewrite", () => {
  const ordinary = moduleWith([{
    $: "model.Operation",
    identity: name("Reader.ask"),
    parameter: unit,
    result: u32,
  }]);
  equal(families["effect_families.required"](ordinary), false);
  equal(families["effect_families.prepare"](ordinary), {
    $: "Done",
    value: ordinary,
  });
});

Deno.test("effect family preparation registers annotation-only instances and erases expression markers", () => {
  const get = name("State.get");
  const set = name("State.set");
  const concreteGet = name("State.get<1:i>");
  const source = moduleWith([
    template(get, unit, parameter),
    template(set, parameter, unit),
    request(get, u32),
    request(get, u32),
    request(set, u32),
  ], [{
    $: "model.Constant",
    name: "operation",
    exported: false,
    annotation: { $: "None" },
    value: {
      $: "model.SpecializeOperationExpr",
      template: get,
      arguments: list([u32]),
      body: { $: "model.OperationExpr", identity: concreteGet },
    },
  }]);
  equal(families["effect_families.required"](source), true);
  const prepared = families["effect_families.prepare"](source);
  equal(prepared.$, "Done");
  if (prepared.$ !== "Done") return;
  equal(families["effect_families.required"](prepared.value), true);
  equal(families["effect_families.prepare"](prepared.value), prepared);
  equal(array(prepared.value.operations), [
    template(get, unit, parameter),
    template(set, parameter, unit),
    {
      $: "model.Operation",
      identity: concreteGet,
      parameter: unit,
      result: u32,
    },
    {
      $: "model.Operation",
      identity: name("State.set<1:i>"),
      parameter: u32,
      result: unit,
    },
  ]);
  equal(array(prepared.value.constants)[0].value, {
    $: "model.OperationExpr",
    identity: concreteGet,
  });
});

Deno.test("effect family preparation finds an instance inside an expression", () => {
  const get = name("State.get");
  const concreteGet = name("State.get<1:i>");
  const source = moduleWith([template(get, unit, parameter)], [{
    $: "model.Constant",
    name: "answer",
    exported: false,
    annotation: { $: "None" },
    value: {
      $: "model.ApplyExpr",
      callee: {
        $: "model.SpecializeOperationExpr",
        template: get,
        arguments: list([u32]),
        body: { $: "model.OperationExpr", identity: concreteGet },
      },
      argument: { $: "model.UnitExpr" },
    },
  }]);
  const prepared = families["effect_families.prepare"](source);
  equal(prepared.$, "Done");
  if (prepared.$ !== "Done") return;
  equal(array(prepared.value.operations), [template(get, unit, parameter), {
    $: "model.Operation",
    identity: concreteGet,
    parameter: unit,
    result: u32,
  }]);
  equal(array(prepared.value.constants)[0].value, {
    $: "model.ApplyExpr",
    callee: { $: "model.OperationExpr", identity: concreteGet },
    argument: { $: "model.UnitExpr" },
  });
});

Deno.test("effect family preparation handles wide sibling expressions", () => {
  const values = Array.from({ length: 8192 }, () => ({ $: "model.UnitExpr" }));
  const source = moduleWith(
    [template(name("Get"), unit, parameter)],
    [{
      $: "model.Constant",
      name: "wide",
      exported: false,
      annotation: { $: "None" },
      value: { $: "model.ArrayExpr", elements: list(values) },
    }],
  );
  const prepared = families["effect_families.prepare"](source);
  equal(prepared.$, "Done");
  if (prepared.$ !== "Done") return;
  const value = array(prepared.value.constants)[0].value as Node;
  equal(value.$, "model.ArrayExpr");
  equal(array(value.elements as List<Node>).length, values.length);
});

Deno.test("effect family preparation checks unused signatures and instance arity", () => {
  const get = name("State.get");
  equal(
    families["effect_families.prepare"](moduleWith([
      template(get, unit, { $: "model.ParameterTy", index: 1n }),
    ])).$,
    "Fail",
  );
  const duplicate = families["effect_families.prepare"](moduleWith([
    template(get, unit, parameter),
    template(get, u32, parameter),
  ]));
  equal(duplicate.$, "Fail");
  if (duplicate.$ === "Fail") equal(duplicate.error.code, "duplicate_type");
  const wrong = families["effect_families.prepare"](moduleWith([
    template(get, unit, parameter),
    { $: "model.OperationInstance", template: get, arguments: list([]) },
  ]));
  equal(wrong.$, "Fail");
  if (wrong.$ === "Fail") equal(wrong.error.code, "effect_instance");
  const unresolved = families["effect_families.identity"](
    get,
    list([{ $: "model.ParameterTy", index: 0n }]),
  );
  equal(unresolved.$, "Fail");
  if (unresolved.$ === "Fail") equal(unresolved.error.code, "effect_instance");
});
