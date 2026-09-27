import { deepStrictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { bendArray, type BendList, bendList } from "./bend_list.ts";

type Node = { readonly $: string; readonly [key: string]: unknown };
type Result<T> = { readonly $: "Done"; readonly value: T } | {
  readonly $: "Fail";
  readonly error: { readonly code: string };
};

const core = compiled as unknown as {
  "types.union"(
    left: BendList<bigint>,
    right: BendList<bigint>,
  ): BendList<bigint>;
  "types.difference"(
    variables: BendList<bigint>,
    excluded: BendList<bigint>,
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
  const result = [...right];
  for (const variable of left) {
    if (!result.includes(variable)) result.unshift(variable);
  }
  return result;
}

function originalDifference(
  variables: readonly bigint[],
  excluded: readonly bigint[],
): bigint[] {
  return variables.filter((variable) => !excluded.includes(variable));
}

function typeRep(index: bigint): Node {
  return {
    $: "model.TypeRepPredicate",
    represented: { $: "model.VariableTy", index },
  };
}

function effectRep(index: bigint): Node {
  return {
    $: "model.EffectRepPredicate",
    row: {
      $: "model.EffectRow",
      operations: bendList([]),
      tail: { $: "model.RowVariable", index },
    },
  };
}

Deno.test("indexed free-variable operations retain order and right-side duplicates", () => {
  const maximum = (1n << 48n) - 1n;
  const leftValues = [0n, 1n, 3n, maximum - 1n, maximum, 17n, 19n];
  const rightValues = [0n, 1n, maximum - 1n, 23n, 29n];
  const sizes = [0, 1, 4, 15, 16, 17, 32, 40];
  for (const leftSize of sizes) {
    for (const rightSize of sizes) {
      const left = Array.from(
        { length: leftSize },
        (_, index) => leftValues[(index * 5 + leftSize) % leftValues.length],
      );
      const right = Array.from(
        { length: rightSize },
        (_, index) => rightValues[(index * 3 + rightSize) % rightValues.length],
      );
      equal(
        bendArray(core["types.union"](bendList(left), bendList(right))),
        originalUnion(left, right),
      );
      equal(
        bendArray(core["types.difference"](bendList(left), bendList(right))),
        originalDifference(left, right),
      );
    }
  }
  equal(
    bendArray(core["types.union"](bendList([3n, 2n, 3n]), bendList([1n, 1n]))),
    [2n, 3n, 1n, 1n],
  );
});

Deno.test("wide free-variable lists agree with the original ordered operations", () => {
  const left = Array.from(
    { length: 4096 },
    (_, index) => BigInt((index * 19) % 2053),
  );
  const right = Array.from(
    { length: 1024 },
    (_, index) => BigInt((index * 7) % 1009),
  );
  equal(
    bendArray(core["types.union"](bendList(left), bendList(right))),
    originalUnion(left, right),
  );
  equal(
    bendArray(core["types.difference"](bendList(left), bendList(right))),
    originalDifference(left, right),
  );
});

Deno.test("free-list right fold retains its accumulated duplicates and group order", () => {
  const groups = Array.from({ length: 80 }, (_, index) => [
    BigInt(index % 17),
    BigInt((index + 1) % 17),
    BigInt(index % 17),
  ]);
  const accumulated = [5n, 5n, 19n];
  const expected = groups.reduce<bigint[]>(
    (right, left) => originalUnion(left, right),
    accumulated,
  );
  equal(
    bendArray(core["constraints.free_list_union"](
      bendList(groups.map((group) => bendList(group))),
      bendList(accumulated),
    )),
    expected,
  );
});

Deno.test("predicate free-list visits source head first and preserves its right fold", () => {
  const predicates = [typeRep(3n), effectRep(2n), typeRep(3n), typeRep(1n)];
  equal(
    core["constraints.free_list"](bendList(predicates)),
    { $: "Done", value: bendList([2n, 3n, 1n]) },
  );
  const invalid: Node = {
    $: "model.TypeRepPredicate",
    represented: { $: "model.FreeTy", scope: "test", name: "unresolved" },
  };
  const result = core["constraints.free_list"](bendList([
    invalid,
    typeRep(1n),
    invalid,
  ]));
  equal(result.$, "Fail");
  if (result.$ === "Fail") equal(result.error.code, "unresolved_annotation");
});
