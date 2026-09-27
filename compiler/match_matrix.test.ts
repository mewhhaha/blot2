import { deepStrictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";

type List<A> = { readonly $: "Nil" } | {
  readonly $: "Con";
  readonly head: A;
  readonly tail: List<A>;
};
type BoolPattern =
  | { readonly $: "model.WildcardPattern" }
  | { readonly $: "model.BoolPattern"; readonly value: boolean };

function list<A>(values: readonly A[]): List<A> {
  return values.reduceRight<List<A>>(
    (tail, head) => ({ $: "Con", head, tail }),
    { $: "Nil" },
  );
}

const patterns = compiled as unknown as {
  "patterns.coverage"(
    fuel: bigint,
    work: {
      readonly $: "patterns.Cover";
      readonly inferred_types: List<{ readonly $: "model.BoolTy" }>;
      readonly rows: List<List<BoolPattern>>;
    },
    types: List<never>,
  ): unknown;
};

Deno.test("pattern matrix coverage agrees with complete finite row enumeration", () => {
  let seed = 8127;
  const random = (bound: number) => {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    return (seed >>> 8) % bound;
  };
  for (let trial = 0; trial < 256; trial++) {
    const columns = 1 + random(4);
    const rows = Array.from(
      { length: random(12) },
      () =>
        Array.from({ length: columns }, (): BoolPattern => {
          const value = random(3);
          return value === 2
            ? { $: "model.WildcardPattern" }
            : { $: "model.BoolPattern", value: value === 1 };
        }),
    );
    const combinations = Array.from(
      { length: 1 << columns },
      (_, mask) =>
        Array.from(
          { length: columns },
          (_, column) => (mask & (1 << column)) !== 0,
        ),
    );
    const complete = combinations.every((values) =>
      rows.some((row) =>
        row.every((pattern, column) =>
          pattern.$ === "model.WildcardPattern" ||
          pattern.value === values[column]
        )
      )
    );
    equal(
      patterns["patterns.coverage"](
        65536n,
        {
          $: "patterns.Cover",
          inferred_types: list(Array.from(
            { length: columns },
            () => ({ $: "model.BoolTy" as const }),
          )),
          rows: list(rows.map(list)),
        },
        list([]),
      ),
      { $: "Done", value: complete },
      `matrix ${trial}: ${JSON.stringify(rows)}`,
    );
  }
});
