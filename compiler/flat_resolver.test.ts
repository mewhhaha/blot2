import { deepStrictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";

type List<A> = { $: "Nil" } | { $: "Con"; head: A; tail: List<A> };
type Node = { $: string; [key: string]: unknown };
const api = compiled as unknown as Record<
  string,
  (...args: unknown[]) => unknown
>;
const nil = { $: "Nil" } as const;
const list = <A>(values: readonly A[]): List<A> =>
  values.reduceRight<List<A>>((tail, head) => ({ $: "Con", head, tail }), nil);
const variable = (index: number): Node => ({
  $: "model.VariableTy",
  index: BigInt(index),
});
const typeId = (name: string): Node => ({
  $: "model.TypeId",
  module_name: "regression",
  declaration: name,
});
const row = (names: readonly string[], tail: number | null = null): Node => ({
  $: "model.EffectRow",
  operations: list(names.map(typeId)),
  tail: tail === null
    ? { $: "model.ClosedRow" }
    : { $: "model.RowVariable", index: BigInt(tail) },
});
const value = (index: number, replacement: Node): Node => ({
  $: "types.Substitution",
  variable: BigInt(index),
  replacement,
});
const effect = (index: number, replacement: Node): Node => ({
  $: "types.RowSubstitution",
  variable: BigInt(index),
  replacement,
});
const one = (ty: Node): Node => ({ $: "types.OneType", value: ty });
const many = (values: readonly Node[]): Node => ({
  $: "types.ManyTypes",
  values: list(values),
});
const u32 = { $: "model.U32Ty" };
const bool = { $: "model.BoolTy" };

function compare(entries: readonly Node[], fuel: bigint, work: Node) {
  const substitutions = api["types.from_list"](list(entries));
  const args = [substitutions, fuel, work];
  equal(
    api["types.resolve_work"](...args),
    api["types.resolve_work_reference"](...args),
  );
}

Deno.test("flat resolver preserves every type constructor and ordered effect rows", () => {
  const constructors: Node[] = [
    { $: "model.UnitTy" },
    u32,
    { $: "model.F32Ty" },
    bool,
    { $: "model.NeverTy" },
    { $: "model.EffectDescriptorTy" },
    { $: "model.EffectSetTy" },
    { $: "model.FreeTy", scope: "regression", name: "a" },
    { $: "model.ParameterTy", index: 0n },
    variable(0),
    { $: "model.ArrayTy", element: variable(0) },
    { $: "model.ProductTy", elements: list([variable(0), variable(1)]) },
    {
      $: "model.AppliedTy",
      identity: typeId("Box"),
      arguments: list([variable(0)]),
    },
    {
      $: "model.ProviderTy",
      identity: typeId("Store"),
      effects: row(["get", "get"], 20),
    },
    {
      $: "model.ProviderTy",
      identity: typeId("Store"),
      effects: {
        $: "model.EffectRow",
        operations: list([typeId("get")]),
        tail: { $: "model.RowParameter", index: 3n },
      },
    },
    {
      $: "model.StateProviderTy",
      read: typeId("get"),
      write: typeId("put"),
      state: variable(1),
    },
    {
      $: "model.FunctionTy",
      parameter: variable(0),
      result: variable(1),
      effects: row(["get", "get"], 20),
    },
  ];
  const entries = [
    value(0, u32),
    value(1, bool),
    effect(20, row(["put"], 21)),
    effect(21, row(["get"])),
  ];
  for (const ty of constructors) {
    for (const fuel of [0n, 1n, 2n, 3n, 8n, 64n]) {
      compare(entries, fuel, one(ty));
    }
  }
  compare(entries, 64n, many(constructors));
});

Deno.test("flat resolver preserves chronological suffixes and insertion boundaries", () => {
  const histories: Node[][] = [
    [value(0, variable(0))],
    [value(0, variable(1)), value(1, variable(0))],
    [value(1, u32), value(0, variable(1))],
    [value(0, variable(1)), value(0, bool), value(1, u32)],
    [effect(20, row(["get"], 20))],
    [effect(20, row(["get"], 21)), effect(21, row(["get"]))],
  ];
  const work = many([variable(0), variable(1), {
    $: "model.FunctionTy",
    parameter: variable(0),
    result: variable(1),
    effects: row(["get"], 20),
  }]);
  for (const entries of histories) {
    for (const fuel of [0n, 1n, 2n, 8n, 64n]) compare(entries, fuel, work);
  }
  const self = api["types.from_list"](list([value(0, variable(0))]));
  equal(api["types.resolve_work"](self, 1n, one(variable(0))), {
    $: "Done",
    value: list([variable(0)]),
  });
});

Deno.test("flat resolver preserves exhausted, malformed and fallback branches", () => {
  compare([], 0n, one({ $: "model.ArrayTy", element: variable(0) }));
  compare(
    [value(0, { $: "model.ArrayTy", element: variable(1) })],
    1n,
    one(variable(0)),
  );
  compare([value(0, u32)], 0n, one(bool));
  const substitutions = api["types.from_list"](list([value(0, bool)]));
  const work = one(variable(0));
  const control = {
    $: "types.FlatVisit",
    fuel: 1n,
    links: 0n,
    exhausted: false,
    cursor: 0n,
    work,
    reversed: nil,
    frames: nil,
  };
  equal(
    api["types.flat_result"](
      api["types.flat_step"](0n, substitutions, control),
      substitutions,
      3n,
      work,
    ),
    api["types.resolve_work_reference"](substitutions, 3n, work),
  );
  equal(api["types.flat_step"](8n, substitutions, control), {
    $: "Some",
    value: api["types.resolve_accumulated"](
      1n,
      0n,
      false,
      substitutions,
      0n,
      work,
      nil,
    ),
  });
});
