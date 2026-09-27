import { deepStrictEqual as equal, ok } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";

type List<T> = { readonly $: "Nil" } | {
  readonly $: "Con";
  readonly head: T;
  readonly tail: List<T>;
};
interface Identity {
  readonly $: "model.TypeId";
  readonly module_name: string;
  readonly declaration: string;
}
type Tail = { readonly $: "model.ClosedRow" } | {
  readonly $: "model.RowVariable" | "model.RowParameter";
  readonly index: bigint;
};
interface Row {
  readonly $: "model.EffectRow";
  readonly operations: List<Identity>;
  readonly tail: Tail;
}
interface Binding {
  readonly $: "effect_rows.Binding";
  readonly variable: bigint;
  readonly replacement: Row;
}
type Result<T> = { readonly $: "Done"; readonly value: T } | {
  readonly $: "Fail";
  readonly error: {
    readonly code: string;
    readonly subject: string;
    readonly message: string;
  };
};
const rows = compiled as unknown as {
  "effect_rows.unify"(
    left: Row,
    right: Row,
    bindings: List<Binding>,
    next: bigint,
    subject: string,
  ): Result<{ readonly bindings: List<Binding>; readonly next: bigint }>;
  "effect_rows.resolve"(bindings: List<Binding>, row: Row): Row;
  "effect_rows.canonical"(row: Row): Row;
  "effect_rows.operation_set"(row: Row): List<Identity>;
};

function list<T>(values: readonly T[]): List<T> {
  return values.reduceRight<List<T>>(
    (tail, head) => ({ $: "Con", head, tail }),
    { $: "Nil" },
  );
}
function array<T>(values: List<T>): T[] {
  const result: T[] = [];
  for (let cursor = values; cursor.$ === "Con"; cursor = cursor.tail) {
    result.push(cursor.head);
  }
  return result;
}
const identity = (declaration: string): Identity => ({
  $: "model.TypeId",
  module_name: "effects",
  declaration,
});
const closed: Tail = { $: "model.ClosedRow" };
const variable = (index: bigint): Tail => ({ $: "model.RowVariable", index });
const parameter = (index: bigint): Tail => ({ $: "model.RowParameter", index });
const row = (operations: readonly string[], tail: Tail = closed): Row => ({
  $: "model.EffectRow",
  operations: list(operations.map(identity)),
  tail,
});
const labelCounts = (value: Row) => {
  const counts = new Map<string, number>();
  for (const operation of array(value.operations)) {
    counts.set(
      operation.declaration,
      (counts.get(operation.declaration) ?? 0) + 1,
    );
  }
  return counts;
};

// A row is a multiset of fixed labels plus at most one unknown multiset. This
// independent arithmetic oracle distinguishes scoped duplicates from sets.
function solvable(left: Row, right: Row): boolean {
  const a = labelCounts(left);
  const b = labelCounts(right);
  const names = new Set([...a.keys(), ...b.keys()]);
  const sameTail = left.tail.$ === right.tail.$ &&
    (left.tail.$ === "model.ClosedRow" ||
      (right.tail.$ !== "model.ClosedRow" &&
        left.tail.index === right.tail.index));
  if (sameTail) {
    return [...names].every((name) =>
      (a.get(name) ?? 0) === (b.get(name) ?? 0)
    );
  }
  if (
    left.tail.$ === "model.RowVariable" && right.tail.$ === "model.RowVariable"
  ) {
    return true;
  }
  if (left.tail.$ === "model.RowVariable") {
    return [...names].every((name) => (a.get(name) ?? 0) <= (b.get(name) ?? 0));
  }
  if (right.tail.$ === "model.RowVariable") {
    return [...names].every((name) => (b.get(name) ?? 0) <= (a.get(name) ?? 0));
  }
  return false;
}

Deno.test("scoped effect rows agree with a multiset unification oracle", () => {
  const labels = [[], ["A"], ["B"], ["A", "B"], ["B", "A"], ["A", "A"]];
  const tails = [closed, variable(0n), variable(1n), parameter(2n)];
  const examples = labels.flatMap((labels) =>
    tails.map((tail) => row(labels, tail))
  );
  for (const left of examples) {
    for (const right of examples) {
      const result = rows["effect_rows.unify"](
        left,
        right,
        list([]),
        3n,
        "oracle",
      );
      const label = JSON.stringify(
        [left, right],
        (_, value) => typeof value === "bigint" ? value.toString() : value,
      );
      equal(result.$ === "Done", solvable(left, right), label);
      if (result.$ === "Done") {
        const resolve = (value: Row) =>
          rows["effect_rows.canonical"](
            rows["effect_rows.resolve"](result.value.bindings, value),
          );
        equal(resolve(left), resolve(right), label);
      } else {
        ok(
          ["infinite_effect", "effect_mismatch"].includes(result.error.code),
          label,
        );
        equal(result.error.subject, "oracle");
      }
    }
  }
});

Deno.test("row substitutions preserve chronological dependencies and scoped multiplicity", () => {
  const bindings: Binding[] = [{
    $: "effect_rows.Binding",
    variable: 0n,
    replacement: row(["A"], variable(1n)),
  }, {
    $: "effect_rows.Binding",
    variable: 1n,
    replacement: row(["A", "B"]),
  }];
  const resolved = rows["effect_rows.resolve"](
    list(bindings),
    row([], variable(0n)),
  );
  equal(resolved, row(["A", "A", "B"]));
  equal(array(rows["effect_rows.operation_set"](resolved)), [
    identity("A"),
    identity("B"),
  ]);
  equal(
    rows["effect_rows.resolve"](
      list([...bindings].reverse()),
      row([], variable(0n)),
    ),
    row(["A"], variable(1n)),
  );
});

Deno.test("row occurs checks reject introducing a label through the same tail", () => {
  const result = rows["effect_rows.unify"](
    row(["A"], variable(0n)),
    row(["B"], variable(0n)),
    list([]),
    1n,
    "recursive",
  );
  ok(result.$ === "Fail");
  equal(result.error, {
    $: "model.Diagnostic",
    code: "infinite_effect",
    subject: "recursive",
    message: "effect row occurs check failed",
  });
});
