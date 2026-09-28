import { deepStrictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { bendArray, bendList } from "./bend_list.ts";

type Node = { $: string; [field: string]: unknown };
const api = compiled as unknown as Record<string, (...args: unknown[]) => Node>;
const nil = bendList<Node>([]);
const empty = { $: "MTip" };
const unit = { $: "model.UnitTy" };
const pure = {
  $: "model.EffectRow",
  operations: nil,
  tail: { $: "model.ClosedRow" },
};
const typeId = {
  $: "model.TypeId",
  module_name: "pending",
  declaration: "read",
};
const represented = (n: number): Node => ({
  $: "model.TypeRepPredicate",
  represented: { $: "model.VariableTy", index: BigInt(n) },
});
const ordinary = (site: bigint): Node => ({
  $: "monomorph.OrdinaryChoiceChanged",
  site,
});
const qualified = (site: bigint, predicate: Node): Node => ({
  $: "monomorph.QualifiedChoiceChanged",
  site,
  predicate,
});
function need(site: bigint, kind: number, predicate = represented(0)): Node {
  if (kind === 2) {
    return { $: "infer.QualifiedNeed", site, predicate, subject: "qualified" };
  }
  if (kind === 1) {
    return {
      $: "infer.AssociatedNeed",
      identity: site,
      dispatch: { $: "model.BinaryDispatch" },
      member: "add",
      templates: nil,
      left: unit,
      right: unit,
      result: unit,
      invocation: { $: "None" },
      ambient: pure,
      subject: "associated",
    };
  }
  return {
    $: "infer.OperationNeed",
    identity: site,
    template: typeId,
    arguments: nil,
    function_type: unit,
    subject: "operation",
  };
}
const store = (map: Node, key: string, value: Node): Node =>
  api["monomorph.store_type_eq_choice"]({ $: "Some", value }, key, map);
function record(map: Node, change: Node): Node {
  if (change.$ === "monomorph.OrdinaryChoiceChanged") {
    return store(map, String(change.site), {
      $: "monomorph.OperationChoice",
      identity: typeId,
      signature: unit,
    });
  }
  const found = api["monomorph.qualified_choice"](map, change.site);
  const previous = found.$ === "Some" ? found.value as Node : undefined;
  const solved = previous ? bendArray(previous.solved as typeof nil) : [];
  return store(map, `q${change.site}`, {
    $: "monomorph.QualifiedChoice",
    solved: bendList([change.predicate as Node, ...solved]),
    answers: nil,
  });
}
const definition = (
  name: string,
  coverage: Node[],
  uses: Node[] = [],
): Node => ({
  $: "infer.Definition",
  name,
  inference: {
    $: "infer.Inference",
    inferred_type: unit,
    coverage: bendList(coverage),
    exits: nil,
    reflections: nil,
    predicates: nil,
    uses: bendList(uses),
  },
});
function specialization(definitions: Node[], choices: Node): Node {
  return {
    $: "monomorph.Specialization",
    module: {
      $: "model.Module",
      constants: nil,
      functions: nil,
      data_types: nil,
      operations: nil,
    },
    environment: {
      $: "globals.Environment",
      bindings: nil,
      definitions: bendList(definitions),
      state: {
        $: "infer.State",
        substitutions: api["types.empty"](),
        next: 100n,
        annotations: empty,
      },
    },
    choices,
    next: 0n,
    certificates: nil,
  };
}
function compare(
  oldDefinitions: Node[],
  fresh: Node[],
  choices: Node,
  change: Node,
) {
  const initial = specialization(oldDefinitions, choices);
  const cache = {
    $: "monomorph.PendingCache",
    definition_count: BigInt(oldDefinitions.length),
    needs: api["monomorph.specialization_pending"](initial),
  };
  const selected = specialization(
    [...fresh, ...oldDefinitions],
    record(choices, change),
  );
  const before = structuredClone([selected, cache, change]);
  const result = api["monomorph.refresh_after_change"](selected, cache, change);
  equal(result, api["monomorph.refresh_pending"](selected, cache));
  equal([selected, cache, change], before);
  return bendArray(result.needs as typeof nil);
}

Deno.test("pending choice changes preserve namespaces, duplicate removal, fresh-definition order and execution needs", () => {
  const site = (1n << 48n) - 1n;
  const first = represented(1);
  const second = represented(2);
  const old = definition("old", [
    need(site, 0),
    need(site, 1),
    need(site, 2, first),
    need(site, 2, first),
    need(site, 2, second),
    need(site - 1n, 2, first),
    need(7n, 0),
  ]);
  const fresh = definition("fresh", [need(site, 0), need(8n, 0)], [{
    $: "constraints.UsePlan",
    site,
    subject: "fresh use",
    instantiated_type: unit,
    predicates: bendList([first, second]),
  }]);
  const changed = compare([old], [fresh], empty, ordinary(site));
  equal(changed[0], need(8n, 0));
  equal(changed.filter((n) => n.$ !== "infer.QualifiedNeed"), [
    need(8n, 0),
    need(7n, 0),
  ]);
  const prior = record(empty, ordinary(site));
  const next = compare([old], [fresh], prior, qualified(site, first));
  equal(
    next.filter((n) => n.site === site && n.$ === "infer.QualifiedNeed").map(
      (n) => n.predicate,
    ),
    [second, second],
  );
  equal(next.filter((n) => n.site === site - 1n), [need(site - 1n, 2, first)]);
});

Deno.test("pending choice changes agree with full refresh across mixed prior choices and newly inferred definitions", () => {
  let seed = 719;
  const random = () => (seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0);
  for (let trial = 0; trial < 200; trial++) {
    let choices: Node = empty;
    for (let i = 0; i < 6; i++) {
      choices = record(
        choices,
        random() % 2
          ? ordinary(BigInt(random() % 12))
          : qualified(BigInt(random() % 12), represented(random() % 4)),
      );
    }
    const coverage = () =>
      Array.from(
        { length: 1 + random() % 45 },
        () =>
          need(BigInt(random() % 14), random() % 3, represented(random() % 4)),
      );
    const old = [definition("a", coverage()), definition("b", coverage())];
    const fresh = Array.from(
      { length: random() % 4 },
      (_, i) => definition(`new ${i}`, coverage()),
    );
    const change = trial % 2
      ? ordinary(BigInt(random() % 14))
      : qualified(BigInt(random() % 14), represented(random() % 4));
    compare(old, fresh, choices, change);
  }
});

Deno.test("pending change refresh keeps full-scan fallbacks for unknown changes and shrinking definition counts", () => {
  const choice = ordinary(1n);
  const selected = specialization([
    definition("remaining", [need(1n, 0), need(2n, 0)]),
  ], record(empty, choice));
  const cache = {
    $: "monomorph.PendingCache",
    definition_count: 9n,
    needs: bendList([need(99n, 0)]),
  };
  equal(
    api["monomorph.refresh_after_change"](selected, cache, choice),
    api["monomorph.refresh_pending"](selected, cache),
  );
  const unknown = { $: "monomorph.UnknownChoiceChange" };
  equal(
    api["monomorph.refresh_after_change"](selected, cache, unknown),
    api["monomorph.refresh_pending"](selected, cache),
  );
});
