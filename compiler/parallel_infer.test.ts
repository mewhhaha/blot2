import { deepStrictEqual as equal, ok } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";

type List<T> = { $: "Nil" } | { $: "Con"; head: T; tail: List<T> };
const nil = { $: "Nil" } as const;
const none = { $: "None" } as const;
function list<T>(items: readonly T[]): List<T> {
  return items.reduceRight<List<T>>(
    (tail, head) => ({ $: "Con", head, tail }),
    nil,
  );
}
function constant(name: string, value: unknown, annotation: unknown = none) {
  return {
    $: "ConstantDeclaration",
    value: { $: "Constant", name, exported: false, annotation, value },
  };
}
const u32 = { $: "U32Ty" };
const bool = { $: "BoolTy" };
const unit = { $: "UnitTy" };
const u32Expr = (value: number) => ({ $: "U32Expr", value });
const boolExpr = (value: boolean) => ({ $: "BoolExpr", value });
const ref = (name: string) => ({ $: "ConstantExpr", name });
const some = (value: unknown) => ({ $: "Some", value });
const id = (name: string) => ({
  $: "TypeId",
  module_name: "ops",
  declaration: name,
});
const row = (labels: unknown[], tail: unknown = { $: "ClosedRow" }) => ({
  $: "EffectRow",
  operations: list(labels),
  tail,
});

type Api = {
  serial: (...args: unknown[]) => unknown;
  parallel: (...args: unknown[]) => unknown;
  segment: (...args: unknown[]) => unknown;
  initialBindings: (declarations: unknown, next: bigint) => List<unknown>;
  initialNext: (declarations: unknown, next: bigint) => bigint;
  empty: () => unknown;
  appendSubstitution: (
    substitutions: unknown,
    substitution: unknown,
  ) => unknown;
  newIndex: () => unknown;
  indexGet: (...args: unknown[]) => unknown;
  adjacency: (...args: unknown[]) => unknown;
  indexedNeighbors: (...args: unknown[]) => unknown;
  readClosure: (...args: unknown[]) => unknown;
  prepareJobs: (...args: unknown[]) => unknown;
  runJob: (...args: unknown[]) => unknown;
  commit: (...args: unknown[]) => unknown;
  conflictsAbsent: (...args: unknown[]) => boolean;
  commitIfCompatible: (...args: unknown[]) => unknown;
};

const exports = compiled as Record<string, (...args: unknown[]) => unknown>;
const api: Api = {
  serial: exports["globals.infer_component"],
  parallel: exports["parallel_infer.infer_component"],
  segment: exports["parallel_infer.infer_segment"],
  initialBindings:
    exports["globals.initial_bindings"] as Api["initialBindings"],
  initialNext: exports["globals.initial_next"] as Api["initialNext"],
  empty: exports["types.empty"] as Api["empty"],
  appendSubstitution:
    exports["types.append_substitution"] as Api["appendSubstitution"],
  newIndex: exports["nat_index.new"] as Api["newIndex"],
  indexGet: exports["nat_index.get"],
  adjacency: exports["parallel_infer.adjacency"],
  indexedNeighbors: exports["parallel_infer.indexed_neighbors"],
  readClosure: exports["parallel_infer.read_closure"],
  prepareJobs: exports["parallel_infer.prepare_jobs"],
  runJob: exports["parallel_infer.run_job"],
  commit: exports["parallel_infer.commit"],
  conflictsAbsent:
    exports["parallel_infer.conflicts_absent"] as Api["conflictsAbsent"],
  commitIfCompatible: exports["parallel_infer.commit_if_compatible"],
};
ok(api.parallel, "generated compiler must export parallel inference");

function environment(
  declarations: List<unknown>,
  imports: unknown[] = [],
  start = 0n,
  substitutions = api.empty(),
) {
  const created = api.initialBindings(declarations, start);
  const bindings: unknown[] = [];
  for (let cursor = created; cursor.$ === "Con"; cursor = cursor.tail) {
    bindings.push(cursor.head);
  }
  return {
    $: "Environment",
    bindings: list([...bindings, ...imports]),
    definitions: nil,
    state: {
      $: "State",
      substitutions,
      next: api.initialNext(declarations, start),
      annotations: { $: "MTip" },
    },
  };
}

function compare(
  declarations: unknown[],
  imports: unknown[] = [],
  operations: unknown[] = [],
  start = 0n,
  substitutions = api.empty(),
) {
  const source = list(declarations);
  const env = environment(source, imports, start, substitutions);
  const args = [source, env, list(operations), nil, nil];
  const serial = api.serial(
    list(
      declarations.map((value) =>
        (value as { value: { name: string } }).value.name
      ),
    ),
    ...args,
  );
  const parallel = api.parallel(...args);
  equal(parallel, serial);
  return parallel as { $: string; error?: unknown };
}

Deno.test("parallel inference preserves independent and interleaved declaration state", () => {
  compare([]);
  compare([constant("only", u32Expr(1))]);
  compare([
    constant("a", u32Expr(1)),
    constant("b", boolExpr(true)),
    constant("depends", ref("a")),
    constant("d", u32Expr(2)),
    constant("e", boolExpr(false)),
  ]);
});

Deno.test("independent jobs pass guard and commit exact serial state", () => {
  const declarations = list([
    constant("a", u32Expr(1)),
    constant("b", boolExpr(true)),
  ]);
  const env = environment(declarations);
  const prepared = api.prepareJobs(
    declarations,
    env,
    none,
    0n,
  ) as {
    $: string;
    value: List<unknown>;
  };
  equal(prepared.$, "Done");
  const jobs: unknown[] = [];
  for (let cursor = prepared.value; cursor.$ === "Con"; cursor = cursor.tail) {
    jobs.push(cursor.head);
  }
  equal(jobs.length, 2);
  const context = {
    $: "Context",
    environment: env,
    operations: nil,
    types: nil,
    functions: nil,
    catalog: none,
  };
  const outcomes = list(jobs.map((job) => api.runJob(job, context)));
  const committed = api.commit(
    outcomes,
    some(env),
    env.state.next,
    (env.state.substitutions as { count: bigint }).count,
  ) as {
    $: string;
    value: unknown;
  };
  equal(committed.$, "Some");
  const serial = api.serial(
    list(["a", "b"]),
    declarations,
    env,
    nil,
    nil,
    nil,
  ) as { $: string; value: unknown };
  equal(serial.$, "Done");
  equal(committed.value, serial.value);
});

function speculativeOutcomes(
  declarations: unknown[],
  imports: unknown[],
  start: bigint,
  operations: unknown[] = [],
) {
  const source = list(declarations);
  const env = environment(source, imports, start);
  const prepared = api.prepareJobs(source, env, none, 0n) as {
    $: string;
    value: List<unknown>;
  };
  equal(prepared.$, "Done");
  const context = {
    $: "Context",
    environment: env,
    operations: list(operations),
    types: nil,
    functions: nil,
    catalog: none,
  };
  const outcomes: unknown[] = [];
  for (let cursor = prepared.value; cursor.$ === "Con"; cursor = cursor.tail) {
    outcomes.push(api.runJob(cursor.head, context));
  }
  return { env, outcomes: list(outcomes) };
}

function assertSpeculativeSuccess(outcomes: List<unknown>) {
  for (let cursor = outcomes; cursor.$ === "Con"; cursor = cursor.tail) {
    equal((cursor.head as { result: { $: string } }).result.$, "Done");
  }
}

Deno.test("shared read-only inference aliases can commit", () => {
  const shared = {
    $: "Binding",
    name: "shared",
    inferred_type: {
      $: "ProductTy",
      elements: list([{ $: "VariableTy", index: 100n }]),
    },
    variables: nil,
  };
  const declarations = [
    constant("first", ref("shared")),
    constant("second", ref("shared")),
  ];
  const { env, outcomes } = speculativeOutcomes(declarations, [shared], 101n);
  assertSpeculativeSuccess(outcomes);
  const baseCount = (env.state.substitutions as { count: bigint }).count;
  equal(api.conflictsAbsent(outcomes, baseCount), true);
  const committed = api.commitIfCompatible(
    outcomes,
    env,
    env.state.next,
    baseCount,
  ) as { $: string };
  equal(committed.$, "Some");
  compare(declarations, [shared], [], 101n);
});

Deno.test("actual writes to shared monomorphic type and row variables force replay", () => {
  const tyShared = {
    $: "Binding",
    name: "shared",
    inferred_type: { $: "VariableTy", index: 100n },
    variables: nil,
  };
  const typeDeclarations = [
    constant("first", ref("shared"), some(u32)),
    constant("second", ref("shared"), some(bool)),
  ];
  const typeJobs = speculativeOutcomes(typeDeclarations, [tyShared], 101n);
  assertSpeculativeSuccess(typeJobs.outcomes);
  const typeCount =
    (typeJobs.env.state.substitutions as { count: bigint }).count;
  equal(api.conflictsAbsent(typeJobs.outcomes, typeCount), false);
  equal(
    (api.commitIfCompatible(
      typeJobs.outcomes,
      typeJobs.env,
      typeJobs.env.state.next,
      typeCount,
    ) as { $: string }).$,
    "None",
  );
  equal(compare(typeDeclarations, [tyShared], [], 101n).$, "Fail");

  const rowShared = {
    $: "Binding",
    name: "shared",
    inferred_type: {
      $: "ProviderTy",
      identity: id("read"),
      effects: row([], { $: "RowVariable", index: 100n }),
    },
    variables: nil,
  };
  const rowDeclarations = [
    constant(
      "first",
      ref("shared"),
      some({ $: "ProviderTy", identity: id("read"), effects: row([]) }),
    ),
    constant(
      "second",
      ref("shared"),
      some({
        $: "ProviderTy",
        identity: id("read"),
        effects: row([id("write")]),
      }),
    ),
  ];
  const rowOps = ["read", "write"].map((name) => ({
    $: "Operation",
    identity: id(name),
    parameter: unit,
    result: unit,
  }));
  const rowJobs = speculativeOutcomes(
    rowDeclarations,
    [rowShared],
    101n,
    rowOps,
  );
  assertSpeculativeSuccess(rowJobs.outcomes);
  const rowCount = (rowJobs.env.state.substitutions as { count: bigint }).count;
  equal(api.conflictsAbsent(rowJobs.outcomes, rowCount), false);
  equal(
    (api.commitIfCompatible(
      rowJobs.outcomes,
      rowJobs.env,
      rowJobs.env.state.next,
      rowCount,
    ) as { $: string }).$,
    "None",
  );
});

function appendAll(entries: unknown[]) {
  return entries.reduce(
    (subs, entry) => api.appendSubstitution(subs, entry),
    api.empty(),
  );
}

function ids(values: List<bigint>): bigint[] {
  const found: bigint[] = [];
  for (let cursor = values; cursor.$ === "Con"; cursor = cursor.tail) {
    found.push(cursor.head);
  }
  return found;
}

Deno.test("indexed neighbors include every historical type and row version in order", () => {
  const variable = (index: bigint) => ({ $: "VariableTy", index });
  const substitutions = appendAll([
    { $: "Substitution", variable: 0n, replacement: variable(1n) },
    {
      $: "RowSubstitution",
      variable: 0n,
      replacement: row([], { $: "RowVariable", index: 2n }),
    },
    { $: "Substitution", variable: 0n, replacement: variable(3n) },
    {
      $: "RowSubstitution",
      variable: 0n,
      replacement: row([], { $: "RowVariable", index: 4n }),
    },
  ]);
  const current = api.indexedNeighbors(substitutions, 0n) as {
    $: string;
    value: List<bigint>;
  };
  equal(current.$, "Done");
  equal(ids(current.value), [1n, 2n, 3n, 4n]);
  const graph = api.adjacency(
    (substitutions as { history: List<unknown> }).history,
    api.newIndex(),
  ) as { $: string; value: unknown };
  equal(graph.$, "Done");
  equal(current.value, api.indexGet(graph.value, 0n, nil));
});

Deno.test("indexed read closure visits diamond and cyclic aliases once", () => {
  const variable = (index: bigint) => ({ $: "VariableTy", index });
  const substitutions = appendAll([
    {
      $: "Substitution",
      variable: 0n,
      replacement: {
        $: "ProductTy",
        elements: list([variable(1n), variable(2n)]),
      },
    },
    { $: "Substitution", variable: 1n, replacement: variable(3n) },
    { $: "Substitution", variable: 2n, replacement: variable(3n) },
    { $: "Substitution", variable: 3n, replacement: variable(0n) },
  ]);
  const work = { $: "ClosureStep", queue: list([0n]), seen: nil };
  const closure = api.readClosure(12n, work, substitutions) as {
    $: string;
    value: List<bigint>;
  };
  equal(closure.$, "Done");
  const visited = ids(closure.value);
  equal(visited.length, 4);
  equal(new Set(visited), new Set([0n, 1n, 2n, 3n]));
  equal((api.readClosure(1n, work, substitutions) as { $: string }).$, "Fail");
});

Deno.test("parallel inference replays first diagnostic in source order", () => {
  const declarations = [
    constant("first", u32Expr(1), some(bool)),
    constant("second", boolExpr(true), some(u32)),
  ];
  const speculative = speculativeOutcomes(declarations, [], 0n);
  const baseCount =
    (speculative.env.state.substitutions as { count: bigint }).count;
  equal(api.conflictsAbsent(speculative.outcomes, baseCount), false);
  equal(
    (api.commitIfCompatible(
      speculative.outcomes,
      speculative.env,
      speculative.env.state.next,
      baseCount,
    ) as { $: string }).$,
    "None",
  );
  const outcome = compare(declarations);
  equal(outcome.$, "Fail");
});

Deno.test("shared monomorphic State provider variables remain serial", () => {
  const shared = {
    $: "Binding",
    name: "shared",
    inferred_type: {
      $: "StateProviderTy",
      read: id("read"),
      write: id("write"),
      state: { $: "VariableTy", index: 100n },
    },
    variables: nil,
  };
  const op = (name: string) => ({
    $: "Operation",
    identity: id(name),
    parameter: unit,
    result: unit,
  });
  const provider = (state: unknown) => ({
    $: "StateProviderTy",
    read: id("read"),
    write: id("write"),
    state,
  });
  const outcome = compare(
    [
      constant("first", ref("shared"), some(provider(u32))),
      constant("second", ref("shared"), some(provider(bool))),
    ],
    [shared],
    [op("read"), op("write")],
    101n,
  );
  equal(outcome.$, "Fail");
});

Deno.test("shared monomorphic effect row constraints preserve serial state", () => {
  const shared = {
    $: "Binding",
    name: "shared",
    inferred_type: {
      $: "ProviderTy",
      identity: id("read"),
      effects: row([], { $: "RowVariable", index: 100n }),
    },
    variables: nil,
  };
  const op = (name: string) => ({
    $: "Operation",
    identity: id(name),
    parameter: unit,
    result: unit,
  });
  const provider = (labels: unknown[]) => ({
    $: "ProviderTy",
    identity: id("read"),
    effects: row(labels),
  });
  compare(
    [
      constant("first", ref("shared"), some(provider([]))),
      constant("second", ref("shared"), some(provider([id("write")]))),
    ],
    [shared],
    [op("read"), op("write")],
    101n,
  );
});

Deno.test("seeded aliases and bound imported quantifiers preserve serial state", () => {
  const alias = api.appendSubstitution(api.empty(), {
    $: "Substitution",
    variable: 100n,
    replacement: { $: "VariableTy", index: 101n },
  });
  const shared = (variables: bigint[]) => ({
    $: "Binding",
    name: "shared",
    inferred_type: { $: "VariableTy", index: 100n },
    variables: list(variables),
  });
  const declarations = [
    constant("first", ref("shared"), some(u32)),
    constant("second", ref("shared"), some(bool)),
  ];
  compare(declarations, [shared([])], [], 102n, alias);
  compare(declarations, [shared([100n])], [], 102n, alias);
});

Deno.test("duplicate pending names keep Globals first-match lookup", () => {
  compare([
    constant("same", u32Expr(1)),
    constant("same", boolExpr(true)),
  ]);
});

Deno.test("staged segment uses full pending names across barriers", () => {
  const declarations = [
    constant("uses_later", ref("later")),
    constant("independent", u32Expr(1)),
  ];
  const source = list(declarations);
  const imported = {
    $: "Binding",
    name: "later",
    inferred_type: { $: "VariableTy", index: 100n },
    variables: nil,
  };
  const env = environment(source, [imported], 101n);
  const original = api.serial(
    list(["uses_later", "independent"]),
    source,
    env,
    nil,
    nil,
    nil,
  );
  const segmented = api.segment(
    source,
    list(["uses_later", "independent", "later"]),
    env,
    nil,
    nil,
    nil,
    none,
  );
  equal(segmented, original);
});
