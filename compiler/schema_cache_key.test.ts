import {
  deepStrictEqual as equal,
  notDeepStrictEqual as different,
  ok,
} from "node:assert/strict";

import compiledModule from "../generated/compiler/native_session.js";
const compiled = compiledModule as unknown as Record<
  string,
  (...args: unknown[]) => unknown
>;

type Cell<T> = { $: "Nil" } | { $: "Con"; head: T; tail: Cell<T> };
const nil: Cell<never> = { $: "Nil" };
const list = <T>(values: T[]): Cell<T> =>
  values.reduceRight<Cell<T>>((tail, head) => ({ $: "Con", head, tail }), nil);
const array = <T>(values: Cell<T>): T[] => {
  const out: T[] = [];
  for (let cell = values; cell.$ === "Con"; cell = cell.tail) {
    out.push(cell.head);
  }
  return out;
};
const identity = (name: string) => ({
  $: "model.TypeId",
  module_name: "cache-test",
  declaration: name,
});
const dataType = (name: string, extra = false) => ({
  $: "model.DataType",
  identity: identity(name),
  parameters: 0n,
  constructors: list([
    { $: "model.Constructor", name, payload: { $: "None" }, fields: nil },
    ...(extra
      ? [{
        $: "model.Constructor",
        name: `${name}Extra`,
        payload: { $: "None" },
        fields: nil,
      }]
      : []),
  ]),
});
const functionSource = (name: string, value: number) => ({
  $: "model.Function",
  name,
  exported: false,
  parameter: "argument",
  parameter_type: { $: "None" },
  result_type: { $: "None" },
  body: { $: "model.U32Expr", value },
});
const node = functionSource("Entry.contains", 1);
const terminal = functionSource("End.contains", 2);
const equality = functionSource("eq", 3);
const typeEquality = functionSource("Type.eq", 4);
const nodeType = dataType("Entry");
const terminalType = dataType("End");
const witnessType = dataType("Type");
const catalog = list([nodeType, terminalType, witnessType]);
const evidence = {
  $: "schema_stage.Evidence",
  node_method: node,
  terminal_method: terminal,
  equality,
  type_equality: typeEquality,
  node_type: nodeType,
  terminal_type: terminalType,
  witness_type: witnessType,
  node_constructor: "Entry",
  terminal_identity: terminalType.identity,
  node_identity: nodeType.identity,
  member: "contains",
};
const moduleFor = (proofs: Cell<typeof evidence>, types = catalog) =>
  compiled["monomorph.context_module"]({
    $: "monomorph.SpecializationContext",
    configuration: {
      $: "monomorph.Configuration",
      functions: nil,
      templates: list(["Entry.contains"]),
      entry: "main.blot",
      locals: nil,
      affected: nil,
      stride: 1024n,
      constants: nil,
      family_templates: nil,
      step: 1n,
      schema: proofs,
    },
    shapes: nil,
    types,
    operations: nil,
    schemes: nil,
    limit: { $: "Done", value: 0n },
  }, nil) as {
    $: "model.Module";
    functions: Cell<{ name: string; parameter: string }>;
  };
const key = (module: unknown) => {
  const result = compiled["native_cache_keys.module"](module) as {
    $: string;
    value?: unknown;
  };
  equal(result.$, "Done");
  return result.value;
};

Deno.test("schema context key frames proof presence, four source bodies, order, and catalog", () => {
  const empty = moduleFor(nil);
  const one = moduleFor(list([evidence]));
  const marker = (module: ReturnType<typeof moduleFor>) =>
    array(module.functions).find((fn) => fn.name === "@schema.evidence");
  equal(marker(empty)?.parameter, "0");
  equal(marker(one)?.parameter, "1");
  equal(array(one.functions).slice(-4).map((fn) => fn.name), [
    node.name,
    terminal.name,
    equality.name,
    typeEquality.name,
  ]);
  different(key(empty), key(one));

  for (
    const field of [
      "node_method",
      "terminal_method",
      "equality",
      "type_equality",
    ] as const
  ) {
    const changed = structuredClone(evidence);
    changed[field] = {
      ...changed[field],
      body: { $: "model.U32Expr", value: 99 },
    };
    different(
      key(one),
      key(moduleFor(list([changed]))),
      `${field} body did not invalidate context key`,
    );
  }
  const second = structuredClone(evidence);
  second.equality = {
    ...second.equality,
    body: { $: "model.U32Expr", value: 99 },
  };
  const two = moduleFor(list([evidence, second]));
  equal(marker(two)?.parameter, "2");
  different(key(one), key(two));
  different(key(two), key(moduleFor(list([second, evidence]))));
  different(
    key(one),
    key(
      moduleFor(
        list([evidence]),
        list([nodeType, dataType("End", true), witnessType]),
      ),
    ),
  );
  ok(array(one.functions).length > array(empty.functions).length);
});
