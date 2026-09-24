import { deepStrictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";

type List<T> = { $: "Nil" } | { $: "Con"; head: T; tail: List<T> };
type Binding = {
  $: "Binding";
  name: string;
  inferred_type: { $: "VariableTy"; index: bigint };
  variables: List<bigint>;
};
const api = compiled as unknown as {
  "global_bindings.build"(
    bindings: List<Binding>,
    position: bigint,
    index: unknown,
  ): unknown;
  "global_bindings.referenced"(
    index: unknown,
    names: List<string>,
  ): List<Binding>;
  "globals.referenced_bindings"(
    bindings: List<Binding>,
    names: List<string>,
  ): List<Binding>;
  "globals.lookup"(declarations: List<unknown>, name: string): unknown;
};
function list<T>(items: readonly T[]): List<T> {
  return items.reduceRight<List<T>>(
    (tail, head) => ({ $: "Con", head, tail }),
    { $: "Nil" },
  );
}
function binding(name: string, index: number): Binding {
  return {
    $: "Binding",
    name,
    inferred_type: { $: "VariableTy", index: BigInt(index) },
    variables: list([BigInt(index)]),
  };
}

Deno.test("global binding index preserves source order, duplicate bindings and shared snapshots", () => {
  const bindings = list(["z", "same", "unused", "same", "a"].map(binding));
  const index = api["global_bindings.build"](bindings, 0n, { $: "MTip" });
  const snapshot = structuredClone(index);
  for (
    const names of [["a", "same", "z", "same"], ["absent"], [], ["same"], [
      "z",
      "a",
    ]]
  ) {
    equal(
      api["global_bindings.referenced"](index, list(names)),
      api["globals.referenced_bindings"](bindings, list(names)),
    );
    equal(index, snapshot);
  }
});

Deno.test("global binding index matches ordered filtering for prefixes, Unicode and large sparse environments", () => {
  const names = [
    "",
    "a",
    "ab",
    "a\0",
    "🦆",
    "日本語",
    ...Array.from({ length: 700 }, (_, i) => `module/${i % 17}/symbol_${i}`),
  ];
  const source = [...names, ...names.slice(0, 20)].map(binding);
  const bindings = list(source);
  const index = api["global_bindings.build"](bindings, 0n, { $: "MTip" });
  for (let start = 0; start < names.length; start += 17) {
    const wanted = [
      names[start],
      names[(start * 11) % names.length],
      "missing",
      names[start],
    ];
    equal(
      api["global_bindings.referenced"](index, list(wanted)),
      list(source.filter((value) => wanted.includes(value.name))),
    );
  }
});

Deno.test("global declaration lookup retains its first match and missing-name diagnostic", () => {
  const declaration = (name: string, value: bigint) => ({
    $: "ConstantDeclaration",
    value: {
      $: "Constant",
      name,
      exported: false,
      annotation: { $: "None" },
      value: { $: "U32Expr", value },
    },
  });
  const first = declaration("same", 1n);
  const declarations = list([
    first,
    declaration("other", 2n),
    declaration("same", 3n),
  ]);
  equal(api["globals.lookup"](declarations, "same"), {
    $: "Done",
    value: first,
  });
  equal(api["globals.lookup"](declarations, "missing"), {
    $: "Fail",
    error: {
      $: "Diagnostic",
      code: "internal_error",
      subject: "missing",
      message: "missing top-level declaration",
    },
  });
});
