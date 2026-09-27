import { deepStrictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { bendArray, type BendList, bendList } from "./bend_list.ts";

type Node = { readonly $: string; readonly [field: string]: unknown };
const api = compiled as unknown as {
  "types.empty"(): Node;
  "monomorph.resolved_signature_rows"(
    types: BendList<Node>,
    substitutions: Node,
  ): { readonly $: "Done"; readonly value: BendList<bigint> } | {
    readonly $: "Fail";
    readonly error: Node;
  };
  "monomorph.signature_rows_work"(
    fuel: bigint,
    pending: BendList<Node>,
    found: BendList<bigint>,
  ): Node;
};
const nil = bendList<Node>([]);
const unit: Node = { $: "model.UnitTy" };
const withRow = (index: bigint): Node => ({
  $: "model.FunctionTy",
  parameter: unit,
  result: unit,
  effects: {
    $: "model.EffectRow",
    operations: nil,
    tail: { $: "model.RowVariable", index },
  },
});
const rows = (types: readonly Node[]): bigint[] => {
  const result = api["monomorph.resolved_signature_rows"](
    bendList(types),
    api["types.empty"](),
  );
  if (result.$ === "Fail") throw new Error(JSON.stringify(result.error));
  return bendArray(result.value);
};

Deno.test("selected signature rows retain right-fold order over wide inputs", () => {
  equal(rows([withRow(3n), withRow(1n), withRow(3n), withRow(2n)]), [
    1n,
    3n,
    2n,
  ]);
  const wide = Array.from(
    { length: 12_000 },
    (_, index) => withRow(BigInt(index % 3)),
  );
  equal(rows(wide), [0n, 1n, 2n]);
});

Deno.test("selected signature row traversal keeps its bounded diagnostic", () => {
  equal(
    api["monomorph.signature_rows_work"](
      0n,
      bendList([withRow(1n)]),
      bendList([]),
    ),
    {
      $: "Fail",
      error: {
        $: "model.Diagnostic",
        code: "type_complexity",
        subject: "effects",
        message: "selected signature is too complex",
      },
    },
  );
});
