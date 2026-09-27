import { deepStrictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { bendArray, type BendList, bendList } from "./bend_list.ts";

type Node = { readonly $: string; readonly [key: string]: unknown };
type Result<T> = { readonly $: "Done"; readonly value: T } | {
  readonly $: "Fail";
  readonly error: { readonly code: string };
};
type Union = Node;

const core = compiled as unknown as {
  "types.union_seed"(values: BendList<bigint>): Union;
  "types.union_into"(left: BendList<bigint>, state: Union): Union;
  "types.union_values"(state: Union): BendList<bigint>;
  "types.union"(
    left: BendList<bigint>,
    right: BendList<bigint>,
  ): BendList<bigint>;
  "constraints.free_list_union"(
    reversed: BendList<BendList<bigint>>,
    accumulated: BendList<bigint>,
  ): BendList<bigint>;
  "constraints.free_list"(predicates: BendList<Node>): Result<BendList<bigint>>;
};

function originalUnion(
  left: readonly bigint[],
  right: readonly bigint[],
): bigint[] {
  const values = [...right];
  for (const variable of left) {
    if (!values.includes(variable)) values.unshift(variable);
  }
  return values;
}

function typeRep(index: bigint): Node {
  return {
    $: "model.TypeRepPredicate",
    represented: { $: "model.VariableTy", index },
  };
}

Deno.test("union retains order and duplicate right cells across promotion", () => {
  const maximum = (1n << 48n) - 1n;
  const left = [251n, 999n, 251n, 1000n, maximum, 0n, 999n];
  for (const size of [0, 1, 254, 255, 256, 257, 512]) {
    // At size 255 the right list already contains duplicates, so the next
    // new left ID promotes by cell count without collapsing those duplicates.
    const right = Array.from(
      { length: size },
      (_, index) => BigInt(index % 251),
    );
    const expected = originalUnion(left, right);
    const state = core["types.union_into"](
      bendList(left),
      core["types.union_seed"](bendList(right)),
    );
    equal(bendArray(core["types.union_values"](state)), expected);
    equal(
      bendArray(core["types.union"](bendList(left), bendList(right))),
      expected,
    );
    equal(
      bendArray(core["types.union_values"](
        core["types.union_into"](
          bendList([]),
          core["types.union_seed"](bendList(right)),
        ),
      )),
      right,
    );
  }
});

Deno.test("predicate right fold crosses promotion once without changing duplicates", () => {
  const groups = Array.from({ length: 300 }, (_, index) => [
    BigInt(index),
    BigInt(index),
  ]);
  const initial = [0n, 0n, 300n];
  const expected = groups.reduce<bigint[]>(
    (right, left) => originalUnion(left, right),
    initial,
  );
  equal(
    bendArray(core["constraints.free_list_union"](
      bendList(groups.map((group) => bendList(group))),
      bendList(initial),
    )),
    expected,
  );
  const predicates = Array.from(
    { length: 260 },
    (_, index) => typeRep(BigInt(index % 257)),
  );
  const result = core["constraints.free_list"](bendList(predicates));
  equal(result.$, "Done");
  if (result.$ === "Done") {
    const expectedPredicates = predicates.reduceRight<bigint[]>(
      (right, predicate) =>
        originalUnion(
          [(predicate.represented as { index: bigint }).index],
          right,
        ),
      [],
    );
    equal(bendArray(result.value), expectedPredicates);
  }
});
