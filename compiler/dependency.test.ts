import { deepStrictEqual as equal, ok } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";

type List<A> =
  | { readonly $: "Nil" }
  | { readonly $: "Con"; readonly head: A; readonly tail: List<A> };

interface Node {
  readonly $: "Node";
  readonly name: string;
  readonly references: List<string>;
  readonly lambdas: List<bigint>;
}

type ComponentsResult =
  | { readonly $: "Done"; readonly value: List<List<string>> }
  | {
    readonly $: "Fail";
    readonly error: {
      readonly code: string;
      readonly subject: string;
      readonly message: string;
    };
  };

const dependency = compiled as unknown as {
  "dependency.components"(nodes: List<Node>): ComponentsResult;
};

function list<A>(values: readonly A[]): List<A> {
  return values.reduceRight<List<A>>(
    (tail, head) => ({ $: "Con", head, tail }),
    { $: "Nil" },
  );
}

function array<A>(values: List<A>): A[] {
  const result: A[] = [];
  for (let cursor = values; cursor.$ === "Con"; cursor = cursor.tail) {
    result.push(cursor.head);
  }
  return result;
}

function components(edges: readonly (readonly number[])[], unknown: boolean) {
  const nodes: Node[] = edges.map((references, index) => ({
    $: "Node",
    name: `node_${index}`,
    references: list([
      ...references.map((target) => `node_${target}`),
      ...(references.length ? [`node_${references[0]}`] : []),
      ...(unknown ? ["unknown_definition"] : []),
    ]),
    lambdas: list([]),
  }));
  const result = dependency["dependency.components"](list(nodes));
  if (result.$ === "Fail") {
    throw new Error(`${result.error.code}: ${result.error.message}`);
  }
  return array(result.value).map(array);
}

Deno.test("empty dependency graph has no inference components", () => {
  equal(components([], false), []);
});

type ReferenceExpr =
  | { $: "FunctionExpr" | "ConstantExpr"; name: string }
  | { $: "ApplyExpr"; callee: ReferenceExpr; argument: ReferenceExpr }
  | {
    $: "IfExpr";
    condition: ReferenceExpr;
    consequent: ReferenceExpr;
    alternative: ReferenceExpr;
  }
  | { $: "ArrayExpr"; elements: List<ReferenceExpr> };
type ReferencesResult =
  | {
    $: "Done";
    value: { $: "References"; names: List<string>; lambdas: List<bigint> };
  }
  | Extract<ComponentsResult, { $: "Fail" }>;
const referenceCompiler = compiled as unknown as {
  "dependency.references"(
    fuel: bigint,
    work: { $: "Expression"; value: ReferenceExpr },
  ): ReferencesResult;
};

Deno.test("flat dependency traversal preserves branch order and structural fuel", () => {
  const fn = (name: string): ReferenceExpr => ({ $: "FunctionExpr", name });
  const apply: ReferenceExpr = {
    $: "ApplyExpr",
    callee: fn("left"),
    argument: fn("right"),
  };
  const call = (fuel: bigint, value: ReferenceExpr) =>
    referenceCompiler["dependency.references"](fuel, {
      $: "Expression",
      value,
    });
  for (const fuel of [0n, 1n]) {
    const failed = call(fuel, apply);
    ok(failed.$ === "Fail");
    equal(failed.error.code, "expression_complexity");
  }
  const shallow = call(2n, apply);
  ok(shallow.$ === "Done");
  equal(array(shallow.value.names), ["left", "right"]);
  const branches: ReferenceExpr = {
    $: "IfExpr",
    condition: apply,
    consequent: fn("then"),
    alternative: { $: "ArrayExpr", elements: list([fn("last"), fn("left")]) },
  };
  const result = call(5n, branches);
  ok(result.$ === "Done");
  equal(array(result.value.names), ["left", "right", "then", "last", "left"]);
  equal(array(result.value.lambdas), []);
  ok(call(4n, branches).$ === "Fail");
});

Deno.test("SCCs agree with transitive closure and order dependencies before users", () => {
  let seed = 197;
  const random = () => {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    return seed;
  };

  for (let trial = 0; trial < 256; trial++) {
    const count = 1 + random() % 9;
    const edges = Array.from(
      { length: count },
      () =>
        Array.from(
          { length: count },
          (_, target) => random() % 5 === 0 ? target : -1,
        ).filter((target) => target >= 0),
    );
    const groups = components(edges, trial % 7 === 0);
    const names = groups.flat();
    const label = `graph ${trial}: ${JSON.stringify(edges)}`;

    equal(names.length, count, `every declared node occurs: ${label}`);
    equal(new Set(names).size, count, `nodes are not duplicated: ${label}`);
    const groupOf = new Map(
      groups.flatMap((group, index) =>
        group.map((name) => [name, index] as const)
      ),
    );

    // An intentionally different algorithm is the oracle: Floyd–Warshall
    // computes reachability, and mutual reachability defines SCC equivalence.
    const reachable = edges.map((targets, index) =>
      Array.from(
        { length: count },
        (_, target) => target === index || targets.includes(target),
      )
    );
    for (let via = 0; via < count; via++) {
      for (let from = 0; from < count; from++) {
        for (let to = 0; to < count; to++) {
          reachable[from][to] ||= reachable[from][via] && reachable[via][to];
        }
      }
    }

    for (let from = 0; from < count; from++) {
      for (let to = 0; to < count; to++) {
        const source = groupOf.get(`node_${from}`);
        const target = groupOf.get(`node_${to}`);
        ok(source !== undefined && target !== undefined, label);
        equal(
          source === target,
          reachable[from][to] && reachable[to][from],
          `SCC equivalence for ${from}, ${to}: ${label}`,
        );
        if (edges[from].includes(to)) {
          ok(
            target <= source,
            `dependency-first order ${from} -> ${to}: ${label}`,
          );
        }
      }
    }
  }
});
