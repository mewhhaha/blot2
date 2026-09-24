import {
  deepStrictEqual as equal,
  notDeepStrictEqual as notEqual,
} from "node:assert/strict";
import compiled from "../generated/compiler/native_session.js";

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

const backend = compiled as unknown as {
  "lower.add_global"(
    context: Node,
    source: string,
    core: string,
    kind: Node,
    node: Node,
  ): Result<Node>;
  "native_cache_keys.scope"(context: Node): Result<List<number>>;
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

function identity(declaration: string): Node {
  return { $: "TypeId", module_name: "main", declaration };
}

function scope(kind: Node): Node {
  const empty = {
    $: "Context",
    globals: { $: "MTip" },
    headers: { $: "MTip" },
    fixities: list([]),
    locals: list([]),
    return_label: { $: "None" },
    annotation_variables: list([]),
  };
  const added = backend["lower.add_global"](empty, "State", "State", kind, {
    $: "Cst",
    kind: "IDENT",
    field: "",
    text: "State",
    offset: 0n,
    children: list([]),
  });
  equal(added.$, "Done");
  if (added.$ !== "Done") throw new Error("could not build scope");
  return added.value;
}

function key(kind: Node): number[] {
  const encoded = backend["native_cache_keys.scope"](scope(kind));
  equal(encoded.$, "Done");
  if (encoded.$ !== "Done") throw new Error("could not encode scope");
  return array(encoded.value);
}

Deno.test("native scope keys distinguish effect templates, arity, and family members", () => {
  const get = identity("State.get");
  const set = identity("State.set");
  const ordinary = key({ $: "OperationName", identity: get });
  const template = key({
    $: "OperationTemplateName",
    identity: get,
    parameters: list([{ $: "Binding", source: "a" }]),
  });
  notEqual(template, ordinary);
  notEqual(
    template,
    key({
      $: "OperationTemplateName",
      identity: get,
      parameters: list([{
        $: "ArrayPattern",
        elements: list([{ $: "Binding", source: "a" }, {
          $: "Binding",
          source: "b",
        }]),
      }]),
    }),
  );
  const family = key({
    $: "EffectFamilyName",
    members: list([get, set]),
    parameters: list([{ $: "Binding", source: "a" }]),
  });
  notEqual(family, template);
  notEqual(
    family,
    key({
      $: "EffectFamilyName",
      members: list([set, get]),
      parameters: list([{ $: "Binding", source: "a" }]),
    }),
  );
});
