import { deepStrictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";

interface Identity {
  readonly $: "TypeId";
  readonly module_name: string;
  readonly declaration: string;
}
interface Effect {
  readonly $: "OperationEffect";
  readonly identity: Identity;
}
type List<T> = { readonly $: "Nil" } | {
  readonly $: "Con";
  readonly head: T;
  readonly tail: List<T>;
};
const effects = compiled as unknown as {
  "effects.effect_equal"(a: Effect, b: Effect): boolean;
  "effects.contains"(values: List<Effect>, value: Effect): boolean;
  "effects.put"(values: List<Effect>, value: Effect): List<Effect>;
  "effects.canonical"(values: List<Effect>): List<Effect>;
  "effects.union"(left: List<Effect>, right: List<Effect>): List<Effect>;
};
function list<T>(values: readonly T[]): List<T> {
  let result: List<T> = { $: "Nil" };
  for (let index = values.length - 1; index >= 0; index--) {
    result = { $: "Con", head: values[index], tail: result };
  }
  return result;
}
function array<T>(values: List<T>): T[] {
  const result: T[] = [];
  for (let cursor = values; cursor.$ === "Con"; cursor = cursor.tail) {
    result.push(cursor.head);
  }
  return result;
}
const effect = (module_name: string, declaration: string): Effect => ({
  $: "OperationEffect",
  identity: { $: "TypeId", module_name, declaration },
});

Deno.test("generic effect metadata compares exact nominal identities", () => {
  const values = [
    effect("a::b", "c"),
    effect("a", "b::c"),
    effect("𐐀", "é"),
    effect("𐐀", "e\u0301"),
    effect("", "a"),
    effect("a", ""),
  ];
  for (const [leftIndex, left] of values.entries()) {
    for (const [rightIndex, right] of values.entries()) {
      equal(
        effects["effects.effect_equal"](left, right),
        leftIndex === rightIndex,
      );
      equal(
        effects["effects.contains"](list([left]), right),
        leftIndex === rightIndex,
      );
    }
  }
});

Deno.test("generic metadata canonicalizes order, removes duplicates, and preserves set union", () => {
  const a = effect("a", "ask");
  const b = effect("a", "other");
  const c = effect("b", "ask");
  const d = effect("𐐀", "ask");
  const first = effects["effects.canonical"](list([d, b, c, a, d, a, b]));
  equal(array(first), [a, b, c, d]);
  equal(effects["effects.canonical"](first), first);
  equal(array(effects["effects.union"](list([d, b, b]), list([c, a, c]))), [
    a,
    b,
    c,
    d,
  ]);
  equal(array(effects["effects.put"](list([a, b]), a)), [a, b]);
  equal(array(effects["effects.put"](list([a, b]), c)), [c, a, b]);
});
