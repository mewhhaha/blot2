import { deepStrictEqual as equal, ok } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import {
  analyze,
  CompilerError,
  type CoreModule,
  type DataType,
  type Descriptor,
  type Effect,
  type TypeId,
} from "./host.ts";
import { descriptor, fn, module, u32Type, unit } from "./fixtures.ts";

type List<A> = { readonly $: "Nil" } | {
  readonly $: "Con";
  readonly head: A;
  readonly tail: List<A>;
};

interface Diagnostic {
  readonly $: "Diagnostic";
  readonly code: string;
  readonly subject: string;
  readonly message: string;
}

type Result<A> = { readonly $: "Done"; readonly value: A } | {
  readonly $: "Fail";
  readonly error: Diagnostic;
};

function list<A>(values: readonly A[]): List<A> {
  return values.reduceRight<List<A>>(
    (tail, head) => ({ $: "Con", head, tail }),
    { $: "Nil" },
  );
}

function call<A>(name: string, ...args: unknown[]): A {
  const exports = compiled as unknown as Record<
    string,
    (...args: unknown[]) => A
  >;
  return exports[name](...args);
}

const done = <A>(value: A): Result<A> => ({ $: "Done", value });
const fail = (
  code: string,
  subject: string,
  message: string,
): Result<never> => ({
  $: "Fail",
  error: { $: "Diagnostic", code, subject, message },
});
const unitResult = done({ $: "Unit" });
const sameIdentity = (left: TypeId, right: TypeId) =>
  left.module_name === right.module_name &&
  left.declaration === right.declaration;
const showIdentity = ({ module_name, declaration }: TypeId) =>
  `${module_name}::${declaration}`;

const wireDescriptor = (value: Descriptor) => ({
  ...value,
  storage: { $: `model.${value.storage.$}` },
});
const wireEffect = (value: Effect) => ({
  ...value,
  access: { $: `model.${value.access.$}` },
  descriptor: wireDescriptor(value.descriptor),
});

function firstDuplicate<A>(
  values: readonly A[],
  same: (a: A, b: A) => boolean,
) {
  return values.find((value, index) =>
    values.slice(index + 1).some((other) => same(value, other))
  );
}

Deno.test("indexed name and lambda validation retain first-duplicate priority", () => {
  const alphabets = ["a", "b", "雪", "🙂", "__proto__", "constructor", ""];
  let seed = 1931;
  const random = () => {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    return seed >>> 8;
  };
  const examples = [[], ["a"], ["a", "b", "b", "a"]];
  for (let trial = 0; trial < 128; trial++) {
    examples.push(Array.from(
      { length: random() % 24 },
      () => alphabets[random() % alphabets.length],
    ));
  }
  for (const names of examples) {
    const duplicate = firstDuplicate(names, (a, b) => a === b);
    equal(
      call("check.unique_names", list(names)),
      duplicate === undefined
        ? unitResult
        : fail("duplicate_name", duplicate, "duplicate top-level definition"),
    );
    const identities = names.map((name) => BigInt(alphabets.indexOf(name)));
    const lambdaDuplicate = firstDuplicate(identities, (a, b) => a === b);
    equal(
      call("check.unique_lambdas", list(identities)),
      lambdaDuplicate === undefined ? unitResult : fail(
        "duplicate_lambda",
        String(lambdaDuplicate),
        "lambda identity must be unique within its module",
      ),
    );
  }
});

Deno.test("descriptor indexes preserve first matches and distinct nominal identities", () => {
  const identities: TypeId[] = [
    { $: "TypeId", module_name: "a::b", declaration: "c" },
    { $: "TypeId", module_name: "a", declaration: "b::c" },
    { $: "TypeId", module_name: "雪🙂", declaration: "Type" },
    { $: "TypeId", module_name: "雪", declaration: "🙂Type" },
    { $: "TypeId", module_name: "", declaration: "" },
  ];
  const descriptors: Descriptor[] = identities.map((identity) => ({
    $: "Descriptor",
    identity,
    storage: { $: "Component" },
  }));
  const reordered = [
    descriptors[0],
    descriptors[1],
    { ...descriptors[1], storage: { $: "Resource" as const } },
    { ...descriptors[0], storage: { $: "Resource" as const } },
  ];
  for (
    const registrations of [
      [],
      descriptors,
      reordered,
      [...descriptors].reverse(),
    ]
  ) {
    const duplicate = firstDuplicate(
      registrations,
      (a, b) => sameIdentity(a.identity, b.identity),
    );
    const raw = list(registrations.map(wireDescriptor));
    equal(
      call("check.valid_descriptors", raw),
      duplicate === undefined ? unitResult : fail(
        "duplicate_type",
        showIdentity(duplicate.identity),
        "duplicate nominal identity",
      ),
    );
    for (const identity of identities) {
      const found = registrations.find((entry) =>
        sameIdentity(entry.identity, identity)
      );
      equal(
        call("check.lookup_descriptor", raw, identity),
        found ? done(wireDescriptor(found)) : fail(
          "unknown_storage",
          showIdentity(identity),
          "no component or resource descriptor for this type",
        ),
      );
    }
  }
});

function diagnosis(source: CoreModule) {
  try {
    analyze(source);
    throw new Error("expected a compiler diagnostic");
  } catch (error) {
    ok(error instanceof CompilerError);
    return { code: error.code, subject: error.subject, detail: error.detail };
  }
}

Deno.test("indexed datatype validation preserves interleaved error ordering", () => {
  const a = descriptor("A");
  const b = descriptor("B");
  const type = (value: Descriptor): DataType => ({
    identity: value.identity,
    parameters: 0n,
    constructors: [{ name: value.identity.declaration, payload: u32Type }],
  });
  const empty: DataType = { ...type(a), constructors: [] };
  equal(diagnosis(module([], { data_types: [empty, type(b), type(b)] })), {
    code: "invalid_annotation",
    subject: showIdentity(a.identity),
    detail: "data declarations need at least one constructor",
  });
  equal(diagnosis(module([], { data_types: [empty, type(b), empty] })), {
    code: "duplicate_type",
    subject: showIdentity(a.identity),
    detail: "duplicate nominal identity",
  });
  equal(
    diagnosis(module([], {
      data_types: [type(a), { ...type(b), parameters: 1n }, type(a)],
      descriptors: [b],
    })),
    {
      code: "duplicate_type",
      subject: showIdentity(a.identity),
      detail: "duplicate nominal identity",
    },
  );
  equal(
    diagnosis(module([fn("duplicate", unit), fn("duplicate", unit)], {
      data_types: [type(a)],
      descriptors: [b, a, a, b],
    })),
    {
      code: "duplicate_type",
      subject: showIdentity(b.identity),
      detail: "duplicate nominal identity",
    },
  );
});

interface EffectNode {
  readonly name: string;
  readonly direct: readonly Effect[];
  readonly callees: readonly string[];
}

const wireNode = ({ name, direct, callees }: EffectNode) => ({
  $: "EffectNode",
  name,
  direct: list(direct.map(wireEffect)),
  callees: list(callees),
});
const sameEffect = (left: Effect, right: Effect) =>
  left.access.$ === right.access.$ &&
  sameIdentity(left.descriptor.identity, right.descriptor.identity);

function union(left: readonly Effect[], right: readonly Effect[]) {
  const result = [...right];
  for (let index = left.length - 1; index >= 0; index--) {
    if (!result.some((value) => sameEffect(value, left[index]))) {
      result.unshift(left[index]);
    }
  }
  return result;
}

function reachableOracle(
  fuel: number,
  initial: readonly string[],
  nodes: readonly EffectNode[],
  visited: readonly string[],
  effects: readonly Effect[],
): Result<List<ReturnType<typeof wireEffect>>> {
  const pending = [...initial];
  const seen = new Set(visited);
  let result = [...effects];
  while (pending.length) {
    const name = pending.shift()!;
    if (fuel-- === 0) {
      return fail(
        "internal_error",
        name,
        "effect worklist exceeded its graph bound",
      );
    }
    const node = nodes.find((node) => node.name === name);
    if (!node) return fail("internal_error", name, "missing effect-graph node");
    if (!seen.has(name)) pending.unshift(...node.callees);
    seen.add(name);
    result = union(node.direct, result);
  }
  return done(list(result.map(wireEffect)));
}

Deno.test("indexed effect reachability agrees on cycles, duplicate nodes, missing names and fuel", () => {
  const storages = [descriptor("A"), descriptor("B", "Resource")];
  const effects: Effect[] = storages.flatMap((storage) =>
    (["Read", "Write", "Insert"] as const).map((access) => ({
      $: "Effect" as const,
      access: { $: access },
      descriptor: storage,
    }))
  );
  let seed = 417;
  const random = () => {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    return seed >>> 8;
  };
  for (let trial = 0; trial < 128; trial++) {
    const names = Array.from(
      { length: 1 + random() % 7 },
      (_, i) => `node_${i}`,
    );
    const nodes: EffectNode[] = names.map((name) => ({
      name,
      direct: effects.filter(() => random() % 5 === 0),
      callees: [...names, "missing"].filter(() => random() % 6 === 0),
    }));
    if (trial % 4 === 0) {
      nodes.push({ name: names[0], direct: effects, callees: ["missing"] });
    }
    const pending = [...names, "missing"].filter(() => random() % 3 === 0);
    const visited = names.filter(() => random() % 5 === 0);
    const initial = effects.filter(() => random() % 4 === 0);
    const rawNodes = list(nodes.map(wireNode));
    for (const fuel of [0, 1, 64]) {
      const expected = reachableOracle(fuel, pending, nodes, visited, initial);
      const args = [
        BigInt(fuel),
        list(pending),
        rawNodes,
        list(visited),
        list(initial.map(wireEffect)),
      ];
      equal(call("check.reachable_work", ...args), expected);
      equal(
        call("check.reachable", ...args),
        nodes.some((node) => node.direct.length)
          ? expected
          : done(list(initial.map(wireEffect))),
      );
    }
    for (const name of [...names, "missing"]) {
      const found = nodes.find((node) => node.name === name);
      equal(
        call("check.lookup_effect_node", rawNodes, name),
        found
          ? done(wireNode(found))
          : fail("internal_error", name, "missing effect-graph node"),
      );
    }
  }
});
