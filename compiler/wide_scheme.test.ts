import { deepStrictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { bendArray, type BendList, bendList } from "./bend_list.ts";

type Node = { readonly $: string; readonly [key: string]: unknown };
type Result<T> = { readonly $: "Done"; readonly value: T } | {
  readonly $: "Fail";
  readonly error: { readonly code: string };
};
const core = compiled as unknown as {
  "groups.indices"(count: bigint, start: bigint): BendList<bigint>;
  "groups.predicate_shapes"(predicates: BendList<Node>): BendList<Node>;
  "groups.scheme_kinds"(fuel: bigint, types: BendList<Node>): Result<Node>;
  "groups.validate_scheme_kinds"(
    template: Node,
    predicates: BendList<Node>,
    subject: string,
  ): Result<Node>;
  "types.parameter_kinds"(fuel: bigint, work: Node): Result<Node>;
  "types.disjoint"(
    variables: BendList<bigint>,
    excluded: BendList<bigint>,
  ): boolean;
};

Deno.test("wide-scheme helpers retain order and collision results", () => {
  equal(bendArray(core["groups.indices"](4n, 7n)), [7n, 8n, 9n, 10n]);
  equal(core["types.disjoint"](bendList([1n, 1n, 3n]), bendList([2n])), true);
  equal(core["types.disjoint"](bendList([1n, 1n, 3n]), bendList([3n])), false);

  const first = {
    $: "model.TypeRepPredicate",
    represented: { $: "model.ParameterTy", index: 4n },
  };
  const second = {
    $: "model.EffectRepPredicate",
    row: {
      $: "model.EffectRow",
      operations: bendList([]),
      tail: { $: "model.RowParameter", index: 4n },
    },
  };
  const shapes = bendArray(
    core["groups.predicate_shapes"](bendList([first, second])),
  );
  equal(shapes[0], first.represented);
  equal(shapes[1].$, "model.FunctionTy");
  equal(
    core["groups.validate_scheme_kinds"](
      { $: "model.ParameterTy", index: 4n },
      bendList([second]),
      "scheme",
    ).$,
    "Fail",
  );
});

Deno.test("wide-scheme kind gather matches original per-branch fuel and merge order", () => {
  const closed = {
    $: "model.EffectRow",
    operations: bendList([]),
    tail: { $: "model.ClosedRow" },
  };
  const types = bendList<Node>([
    { $: "model.ParameterTy", index: 3n },
    {
      $: "model.FunctionTy",
      parameter: { $: "model.ParameterTy", index: 1n },
      result: { $: "model.ParameterTy", index: 3n },
      effects: closed,
    },
    { $: "model.ParameterTy", index: 2n },
  ]);
  for (const fuel of [0n, 1n, 2n, 3n, 4n, 8n, 16n]) {
    equal(
      core["groups.scheme_kinds"](fuel, types),
      core["types.parameter_kinds"](fuel, {
        $: "types.ManyTypes",
        values: types,
      }),
      `fuel ${fuel}`,
    );
  }
});
