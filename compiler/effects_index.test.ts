import { deepStrictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import type { Descriptor, Effect, SystemPlan, TypeId } from "./host.ts";

type List<A> = { readonly $: "Nil" } | {
  readonly $: "Con";
  readonly head: A;
  readonly tail: List<A>;
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

function call<A>(name: string, ...args: unknown[]): A {
  const exports = compiled as unknown as Record<
    string,
    (...args: unknown[]) => A
  >;
  return exports[name](...args);
}

const descriptor = (value: Descriptor) => ({
  ...value,
  storage: { $: `model.${value.storage.$}` },
});
const effect = (value: Effect) => ({
  ...value,
  access: { $: `model.${value.access.$}` },
  descriptor: descriptor(value.descriptor),
});
const row = (values: readonly Effect[]) => list(values.map(effect));
const system = (value: SystemPlan) => ({
  $: "SystemPlan",
  ...value,
  effects: row(value.effects),
  query: list(value.query.map(descriptor)),
});

const sameIdentity = (left: TypeId, right: TypeId) =>
  left.module_name === right.module_name &&
  left.declaration === right.declaration;
const sameEffect = (left: Effect, right: Effect) =>
  left.access.$ === right.access.$ &&
  sameIdentity(left.descriptor.identity, right.descriptor.identity);
const conflict = (left: Effect, right: Effect) =>
  sameIdentity(left.descriptor.identity, right.descriptor.identity) &&
  (left.access.$ !== "Read" || right.access.$ !== "Read");

function union(left: readonly Effect[], right: readonly Effect[]): Effect[] {
  const result = [...right];
  for (let index = left.length - 1; index >= 0; index--) {
    if (!result.some((found) => sameEffect(found, left[index]))) {
      result.unshift(left[index]);
    }
  }
  return result;
}

function registrations(effects: readonly Effect[]): Descriptor[] {
  const result: Descriptor[] = [];
  for (let index = effects.length - 1; index >= 0; index--) {
    const found = effects[index].descriptor;
    if (
      !result.some((previous) =>
        sameIdentity(previous.identity, found.identity)
      )
    ) {
      result.unshift(found);
    }
  }
  return result;
}

const requiresEntity = (value: Effect) =>
  value.access.$ !== "Insert" && value.descriptor.storage.$ === "Component";
const separates = (left: readonly Effect[], right: readonly Effect[]) =>
  [...left, ...right].some((value) => value.access.$ === "Insert") ||
  left.some((a) => right.some((b) => conflict(a, b)));

function batches(systems: readonly SystemPlan[]): string[][] {
  const completed: string[][] = [];
  let current: string[] = [];
  let effects: Effect[] = [];
  for (const system of systems) {
    if (separates(effects, system.effects)) {
      if (current.length) completed.push(current);
      current = [system.name];
      effects = [...system.effects];
    } else {
      current.push(system.name);
      effects = union(system.effects, effects);
    }
  }
  if (current.length) completed.push(current);
  return completed;
}

function random(seed: number) {
  let state = seed;
  return (limit: number): number => {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    return state % limit;
  };
}

const identities: readonly TypeId[] = [
  ["", ""],
  ["game/components", "Position"],
  ["game/resources", "Position"],
  ["a::b", "c"],
  ["a", "b::c"],
  ["a\0b", "c"],
  ["a", "b\0c"],
  ["λ", "位置"],
].map(([module_name, declaration]) => ({
  $: "TypeId",
  module_name,
  declaration,
}));

function fixture(
  identity: TypeId,
  access: Effect["access"]["$"],
  storage: Descriptor["storage"]["$"] = "Component",
): Effect {
  return {
    $: "Effect",
    access: { $: access },
    descriptor: { $: "Descriptor", identity, storage: { $: storage } },
  };
}

function randomRow(next: (limit: number) => number, limit: number): Effect[] {
  return Array.from({ length: next(limit + 1) }, () =>
    fixture(
      identities[next(identities.length)],
      (["Read", "Read", "Read", "Write", "Write", "Insert"] as const)[next(6)],
      next(2) ? "Component" : "Resource",
    ));
}

Deno.test("effect identity and conflict rules distinguish nominal names but deliberately ignore storage kind", () => {
  const effects = identities.flatMap((identity) =>
    (["Read", "Write", "Insert"] as const).flatMap((access) =>
      (["Component", "Resource"] as const).map((storage) =>
        fixture(identity, access, storage)
      )
    )
  );
  for (const left of effects) {
    for (const right of effects) {
      equal(
        call("effects.effect_equal", effect(left), effect(right)),
        sameEffect(left, right),
      );
      equal(
        call("effects.conflicts", effect(left), effect(right)),
        conflict(left, right),
      );
    }
  }
});

Deno.test("indexed effect union preserves left last occurrences and the exact duplicate-bearing right row", () => {
  const next = random(0x51075eed);
  for (let sample = 0; sample < 250; sample++) {
    const left = randomRow(next, 24);
    const right = randomRow(next, 24);
    equal(
      array(call<List<unknown>>("effects.union", row(left), row(right))),
      union(left, right).map(effect),
    );
    for (const candidate of left.slice(0, 3)) {
      const expected = right.some((found) => sameEffect(found, candidate));
      equal(call("effects.contains", row(right), effect(candidate)), expected);
      equal(
        array(
          call<List<unknown>>("effects.put", row(right), effect(candidate)),
        ),
        (expected ? right : [candidate, ...right]).map(effect),
      );
    }
  }
  const read = fixture(identities[1], "Read");
  const resourceRead = fixture(identities[1], "Read", "Resource");
  const write = fixture(identities[1], "Write");
  equal(
    array(
      call<List<unknown>>(
        "effects.union",
        row([read, write, resourceRead]),
        row([]),
      ),
    ),
    [write, resourceRead].map(effect),
  );
  equal(
    array(
      call<List<unknown>>(
        "effects.union",
        row([read]),
        row([resourceRead, read]),
      ),
    ),
    [resourceRead, read].map(effect),
  );
});

Deno.test("indexed registrations, query filtering and canonicalization match ordered reference rows", () => {
  const next = random(0x6e7c02f1);
  for (let sample = 0; sample < 160; sample++) {
    const effects = randomRow(next, 64);
    const descriptors = effects.map((value) => value.descriptor);
    equal(
      array(call<List<unknown>>("effects.registrations", row(effects))),
      registrations(effects).map(descriptor),
    );
    equal(
      array(call<List<unknown>>("effects.query", row(effects))),
      registrations(effects.filter(requiresEntity)).map(descriptor),
    );
    const ordered = descriptors.toSorted((a, b) => {
      for (const name of ["module_name", "declaration"] as const) {
        if (a.identity[name] !== b.identity[name]) {
          return a.identity[name] < b.identity[name] ? -1 : 1;
        }
      }
      return 0;
    });
    equal(
      array(
        call<List<unknown>>(
          "effects.canonical",
          list(descriptors.map(descriptor)),
        ),
      ),
      ordered.map(descriptor),
    );
  }
});

Deno.test("indexed batches and cross-system registrations match reference schedules including malformed duplicate descriptors", () => {
  const next = random(0x305babe);
  for (let sample = 0; sample < 150; sample++) {
    const systems = Array.from(
      { length: next(25) },
      (_, index): SystemPlan => ({
        name: `system_${index % 7}`,
        effects: randomRow(next, 8),
        query: [],
      }),
    );
    const left = randomRow(next, 12);
    const right = randomRow(next, 12);
    equal(
      call("schedule.row_conflicts", row(left), row(right)),
      left.some((a) => right.some((b) => conflict(a, b))),
    );
    equal(
      call("schedule.separates", row(left), row(right)),
      separates(left, right),
    );
    equal(
      array(
        call<List<List<string>>>("schedule.batches", list(systems.map(system))),
      ).map(array),
      batches(systems),
    );
    const combined = systems.reduceRight<Effect[]>(
      (tail, current) => union(current.effects, tail),
      [],
    );
    equal(
      array(
        call<List<unknown>>(
          "effects.system_registrations",
          list(systems.map(system)),
        ),
      ),
      registrations(combined).map(descriptor),
    );
  }
});

Deno.test("indexed scheduler keeps long disjoint batches, internal read-write rows and structural barriers exact", () => {
  const shared = fixture(
    { $: "TypeId", module_name: "game", declaration: "Clock" },
    "Read",
    "Resource",
  );
  const systems: SystemPlan[] = Array.from({ length: 64 }, (_, index) => {
    const identity: TypeId = {
      $: "TypeId",
      module_name: "game",
      declaration: `Position${index}`,
    };
    return {
      name: `move_${index}`,
      effects: [fixture(identity, "Read"), fixture(identity, "Write"), shared],
      query: [],
    };
  });
  const barrier: SystemPlan = {
    name: "insert",
    effects: [fixture(identities[1], "Insert", "Resource")],
    query: [],
  };
  const pure: SystemPlan = { name: "pure", effects: [], query: [] };
  for (
    const ordered of [systems, [barrier, pure, ...systems], [
      ...systems,
      barrier,
      pure,
      barrier,
      pure,
    ]]
  ) {
    equal(
      array(
        call<List<List<string>>>("schedule.batches", list(ordered.map(system))),
      ).map(array),
      batches(ordered),
    );
  }
  equal(
    array(
      call<List<List<string>>>("schedule.batches", list(systems.map(system))),
    ).map(array),
    [systems.map((entry) => entry.name)],
  );
});
