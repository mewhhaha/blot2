import { deepStrictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";

const names = compiled as unknown as {
  "model.name_equal"(left: string, right: string): boolean;
  "infer.lookup_binding"(bindings: unknown, name: string): unknown;
  "type_data.lookup"(types: unknown, identity: unknown): unknown;
  "type_data.constructor"(types: unknown, name: string): unknown;
  "type_data.operation"(operations: unknown, identity: unknown): unknown;
};

function list(values: readonly unknown[]): unknown {
  return values.reduceRight((tail, head) => ({ $: "Con", head, tail }), {
    $: "Nil",
  });
}

Deno.test("compiler name equality agrees with exact Unicode equality", () => {
  const spellings = [
    "",
    "a",
    "ab",
    "ba",
    "position_1",
    "position_10",
    "position_100",
    "$prelude.Maybe.map",
    "$prelude.Maybe.bind",
    "std/prelude",
    "main",
    "é",
    "e\u0301",
    "λ",
    "𐐀",
    "𐐁",
    "𐐀name",
    "𐐀Name",
    "a\0b",
    "a\0c",
  ];
  for (const left of spellings) {
    for (const right of spellings) {
      equal(
        names["model.name_equal"](left, right),
        left === right,
        JSON.stringify([left, right]),
      );
    }
  }
});

Deno.test("long shared name prefixes use stack-safe equality", () => {
  const prefix = "namespace.".repeat(4096);
  equal(names["model.name_equal"](prefix, prefix), true);
  equal(names["model.name_equal"](`${prefix}left`, `${prefix}right`), false);
  equal(names["model.name_equal"](prefix, `${prefix}a`), false);
});

Deno.test("metadata scans preserve first-match binding and nominal identity semantics", () => {
  const identities = [
    { $: "model.TypeId", module_name: "a::b", declaration: "c" },
    { $: "model.TypeId", module_name: "a", declaration: "b::c" },
    { $: "model.TypeId", module_name: "🦆", declaration: "é" },
    { $: "model.TypeId", module_name: "🦆", declaration: "e\u0301" },
  ];
  const bindings = ["value", "other", "value"].map((name, index) => ({
    $: "infer.Binding",
    predicates: { $: "Nil" },

    name,
    inferred_type: { $: "model.VariableTy", index: BigInt(index) },
    variables: list([]),
  }));
  for (const name of ["value", "other", "missing"]) {
    const found = bindings.find((binding) => binding.name === name);
    equal(
      names["infer.lookup_binding"](list(bindings), name),
      found ? { $: "Some", value: found } : { $: "None" },
    );
  }
  const types = [...identities, identities[0]].map((identity, index) => ({
    $: "model.DataType",
    identity,
    parameters: BigInt(index),
    constructors: list([{
      $: "model.Constructor",
      fields: { $: "Nil" },
      name: `Variant${index % identities.length}`,
      payload: { $: "None" },
    }]),
  }));
  for (const [index, identity] of identities.entries()) {
    equal(names["type_data.lookup"](list(types), identity), {
      $: "Some",
      value: types[index],
    });
    equal(names["type_data.constructor"](list(types), `Variant${index}`), {
      $: "Some",
      value: {
        $: "type_data.ConstructorDefinition",
        identity,
        parameters: BigInt(index),
        payload: { $: "None" },
      },
    });
    const operation = {
      $: "model.Operation",
      identity,
      parameter: { $: "model.UnitTy" },
      result: { $: "model.U32Ty" },
    };
    for (const other of identities) {
      equal(
        names["type_data.operation"](list([operation]), other),
        identity === other ? { $: "Some", value: operation } : { $: "None" },
      );
    }
  }
  equal(names["type_data.lookup"](list([]), identities[0]), { $: "None" });
  equal(names["type_data.constructor"](list(types), "Missing"), { $: "None" });
  equal(names["type_data.operation"](list([]), identities[0]), { $: "None" });
});
