import { deepStrictEqual as equal, ok } from "node:assert/strict";
import generated from "../generated/compiler/compiler.js";
import { bendArray, type BendList, bendList } from "./bend_list.ts";

type Term = { readonly $: string; readonly [field: string]: unknown };
type Identity = {
  readonly $: "model.TypeId";
  readonly module_name: string;
  readonly declaration: string;
};
type UsageResult =
  | {
    readonly $: "Done";
    readonly value: { readonly nominals: BendList<Identity> };
  }
  | { readonly $: "Fail"; readonly error: { readonly code: string } };
const backend = generated as unknown as {
  "groups.constructor_index"(types: BendList<Term>, index: Term): Term;
  "groups.usage"(fuel: bigint, work: Term, types: Term): UsageResult;
};
const identity = (declaration: string): Identity => ({
  $: "model.TypeId",
  module_name: "test",
  declaration,
});
const empty = { $: "MTip" };
const unit = { $: "model.UnitExpr" };
const wildcard = { $: "model.WildcardPattern" };

Deno.test("wide nominal dependency lists retain their exact sibling fuel boundary", () => {
  for (
    const [kind, element] of [
      ["groups.ExpressionsUsage", unit],
      ["groups.PatternsUsage", wildcard],
      ["groups.TypesUsage", { $: "model.U32Ty" }],
      ["groups.ArmsUsage", {
        $: "model.MatchArm",
        patterns: bendList([]),
        body: unit,
      }],
    ] as const
  ) {
    const count = 8192;
    const work = { $: kind, values: bendList(Array(count).fill(element)) };
    const result = backend["groups.usage"](BigInt(count + 1), work, empty);
    ok(result.$ === "Done", kind);
    equal(bendArray(result.value.nominals), []);
    const exhausted = backend["groups.usage"](BigInt(count), work, empty);
    ok(exhausted.$ === "Fail", kind);
    equal(exhausted.error.code, "expression_complexity");
  }
});

Deno.test("nominal collection preserves recursive merge order and duplicate elimination", () => {
  const catalog = backend["groups.constructor_index"](
    bendList(["A", "B", "C"].map((name) => ({
      $: "model.DataType",
      identity: identity(name),
      parameters: 0n,
      constructors: bendList([{
        $: "model.Constructor",
        fields: { $: "Nil" },
        name,
        payload: { $: "None" },
      }]),
    }))),
    empty,
  );
  const result = backend["groups.usage"](32n, {
    $: "groups.ArmsUsage",
    values: bendList([{
      $: "model.MatchArm",
      patterns: bendList([{
        $: "model.ConstructorPattern",
        constructor: "A",
        payload: { $: "None" },
      }]),
      body: {
        $: "model.ArrayExpr",
        elements: bendList(
          ["B", "A", "C"].map((constructor) => ({
            $: "model.ConstructorRefExpr",
            constructor,
          })),
        ),
      },
    }]),
  }, catalog);
  ok(result.$ === "Done");
  equal(bendArray(result.value.nominals), [
    identity("C"),
    identity("A"),
    identity("B"),
  ]);
});
