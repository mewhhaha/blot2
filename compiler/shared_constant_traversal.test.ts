import { deepStrictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";

type List<A> = { $: "Nil" } | { $: "Con"; head: A; tail: List<A> };
const nil = { $: "Nil" } as const;
const list = <A>(values: readonly A[]): List<A> =>
  values.reduceRight<List<A>>((tail, head) => ({ $: "Con", head, tail }), nil);
const array = <A>(values: List<A>): A[] => {
  const result: A[] = [];
  for (let p = values; p.$ === "Con"; p = p.tail) result.push(p.head);
  return result;
};
const bend = compiled as unknown as Record<
  string,
  (...args: unknown[]) => unknown
>;
const unit = { $: "model.UnitTy" };
const u32 = { $: "model.U32Ty" };
const predicate = { $: "model.TypeRepPredicate", represented: u32 };

Deno.test("dependency and predicate lookups preserve first-match precedence, including empty results", () => {
  const names = ["", "a::b", "雪🙂", "prefix", "prefix-long"];
  const nodes = names.map((name, i) => ({
    $: "dependency.Node",
    name,
    references: list(i % 2 ? [name, "unknown"] : []),
    lambdas: nil,
  }));
  const definitions = names.map((name, i) => ({
    $: "infer.Definition",
    name,
    inference: {
      $: "infer.Inference",
      inferred_type: unit,
      coverage: nil,
      exits: nil,
      reflections: nil,
      predicates: list(i % 2 ? [predicate] : []),
      uses: nil,
    },
  }));
  for (const query of [...names, "missing", "雪"]) {
    const allNodes = [
      ...nodes,
      ...nodes.map((node) => ({ ...node, references: list(["later"]) })),
    ];
    const allDefinitions = [
      ...definitions,
      ...definitions.map((definition) => ({
        ...definition,
        inference: { ...definition.inference, predicates: list([predicate]) },
      })),
    ];
    equal(
      bend["dependency.lookup"](list(allNodes), query),
      allNodes.find((n) => n.name === query)?.references ?? nil,
    );
    equal(
      bend["globals.definition_predicates"](list(allDefinitions), query),
      allDefinitions.find((d) => d.name === query)?.inference.predicates ?? nil,
    );
  }
});

type Identity = { $: "model.TypeId"; module_name: string; declaration: string };
type Operation = {
  $: "model.Operation" | "model.OperationTemplate";
  identity: Identity;
  parameter: typeof unit;
  result: typeof unit;
  parameters?: bigint;
} | {
  $: "model.OperationInstance";
  template: Identity;
  arguments: List<unknown>;
};
const identity = (n: number): Identity => ({
  $: "model.TypeId",
  module_name: ["a", "a::b", "", "雪🙂"][n % 4],
  declaration: `read::${n}`,
});
const operation = (n: number, kind = 0): Operation =>
  kind === 2
    ? {
      $: "model.OperationInstance",
      template: identity(n),
      arguments: list([unit]),
    }
    : {
      $: kind === 1 ? "model.OperationTemplate" : "model.Operation",
      identity: identity(n),
      parameter: unit,
      result: n % 2 ? unit : u32,
      ...(kind === 1 ? { parameters: 1n } : {}),
    };
const key = (id: Identity) => JSON.stringify([id.module_name, id.declaration]);
function oracle(incoming: Operation[], retained: Operation[]): Operation[] {
  const seen = new Set(
    retained.flatMap((op) =>
      op.$ === "model.Operation" ? [key(op.identity)] : []
    ),
  );
  const result = retained.slice();
  for (const op of incoming) {
    if (op.$ !== "model.Operation" || seen.has(key(op.identity))) continue;
    seen.add(key(op.identity));
    result.push(op);
  }
  return result;
}
function merged(incoming: Operation[], retained: Operation[]) {
  const before = structuredClone([incoming, retained]);
  const result = array(
    bend["state_specialize.merge"](list(incoming), list(retained)) as List<
      Operation
    >,
  );
  equal(result, oracle(incoming, retained));
  equal([incoming, retained], before);
}

Deno.test("operation merging preserves the existing catalog through shared prefixes and divergent suffixes", () => {
  const retained = Array.from(
    { length: 128 },
    (_, n) => operation(n, n % 5 === 0 ? 1 : 0),
  );
  merged([], retained);
  merged(retained, retained);
  merged([...retained, operation(999), operation(998)], retained);
  merged(
    [...retained.slice(0, 55), operation(999), ...retained.slice(30)],
    retained,
  );
  merged([...retained].reverse(), retained);
  merged(
    [operation(1), operation(1), operation(999), operation(999)],
    retained,
  );
  merged(retained, []);
  const old = operation(1);
  const changed = { ...old, parameter: u32, result: u32 } as Operation;
  merged([changed, operation(2)], [old]);
});

Deno.test("operation merging agrees with an identity-set oracle across mixed kinds, duplicates and order", () => {
  let seed = 71023;
  const random = () => (seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0);
  for (let trial = 0; trial < 160; trial++) {
    const retained = Array.from(
      { length: random() % 30 },
      () => operation(random() % 70, random() % 3),
    );
    const incoming = [
      ...retained.slice(0, random() % (retained.length + 1)),
      ...Array.from(
        { length: random() % 35 },
        () => operation(random() % 70, random() % 3),
      ),
    ];
    merged(incoming, retained);
  }
});
