import { strictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { type BendList, bendList } from "./bend_list.ts";

type Predicate = {
  readonly $: "model.TypeRepPredicate";
  readonly represented: {
    readonly $: "model.VariableTy";
    readonly index: bigint;
  };
};
const core = compiled as unknown as {
  "dispatch_resolution.same_predicates"(
    left: BendList<Predicate>,
    right: BendList<Predicate>,
  ): boolean;
};
function predicate(index: number): Predicate {
  return {
    $: "model.TypeRepPredicate",
    represented: { $: "model.VariableTy", index: BigInt(index) },
  };
}
const width = 12_000;
const values = Array.from({ length: width }, (_, index) => predicate(index));
function same(
  left: readonly Predicate[],
  right: readonly Predicate[],
): boolean {
  return core["dispatch_resolution.same_predicates"](
    bendList(left),
    bendList(right),
  );
}
Deno.test("dispatch compares wide ordered predicate lists without consuming the JS stack", () => {
  equal(same(values, values.map((_, index) => predicate(index))), true);
  equal(same([], []), true);
});
Deno.test("dispatch predicate comparison retains prefix, suffix, order and length mismatches", () => {
  equal(same(values, [predicate(width), ...values.slice(1)]), false);
  equal(same(values, [...values.slice(0, -1), predicate(width)]), false);
  equal(same(values, [values[1], values[0], ...values.slice(2)]), false);
  equal(same(values, values.slice(0, -1)), false);
  equal(same(values.slice(0, -1), values), false);
  equal(same([], [predicate(0)]), false);
  equal(same([predicate(0)], []), false);
});
