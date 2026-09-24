import { deepStrictEqual as equal, ok } from "node:assert/strict";
import compiled from "../generated/compiler/native_session.js";
import { bendArray, type BendList, bendList } from "./bend_list.ts";

type Node = { readonly $: string; readonly [field: string]: unknown };
interface Job {
  readonly $: "CodegenJob";
  readonly key: string;
  readonly parameter: string;
  readonly body: Node;
  readonly captures: BendList<string>;
}
interface Diagnostic {
  readonly $: "Diagnostic";
  readonly code: string;
  readonly subject: string;
  readonly message: string;
}
type Result<T> = { readonly $: "Done"; readonly value: T } | {
  readonly $: "Fail";
  readonly error: Diagnostic;
};
interface KeyedEntry {
  readonly $: "KeyedEntry";
  readonly job: Job;
  readonly encoded: Result<BendList<number>>;
}
interface EntryPlan {
  readonly $: "EntryPlan";
  readonly selections: BendList<Node>;
  readonly missing: BendList<Job>;
  readonly failure: { readonly $: "None" } | {
    readonly $: "Some";
    readonly value: Diagnostic;
  };
}
interface Scheduled {
  readonly $: "Scheduled";
  readonly position: bigint;
  readonly level: bigint;
  readonly job: Node;
}
type PreparedGroup = Node & {
  readonly base_key: BendList<number>;
  readonly keys: BendList<BendList<number>>;
};
const backend = compiled as unknown as {
  "entry_key_tasks"(
    jobs: BendList<Job>,
    reversed: BendList<Node>,
  ): BendList<Node>;
  "compile_weighted_entries"(
    tasks: BendList<Node>,
    previous: Node,
    next: Node,
    reversed: BendList<Node>,
    counts: Node,
    staged: boolean,
  ): Result<Node>;
  "compile_keyed_entry"(entry: KeyedEntry, previous: Node): Result<Node>;
  "publish_compiled_entries"(
    entries: BendList<Result<Node>>,
    next: Node,
    reversed: BendList<Node>,
    counts: Node,
  ): Result<Node>;
  "keyed_entries"(jobs: BendList<Job>): BendList<KeyedEntry>;
  "native_cache_keys.entry"(job: Job): Result<BendList<number>>;
  "catalog_versions.prepare"(
    types: BendList<Node>,
    operations: BendList<Node>,
    previous: Node,
  ): Result<{ readonly revision: Node }>;
  "empty_checked"(): Node & { readonly groups: Node };
  "check_scheduler.catalog"(module: Node): Node;
  "prepare_group"(
    position: bigint,
    job: Node,
    known: Node,
    previous: Node,
    state: Node,
  ): Result<PreparedGroup>;
  "prepare_groups"(
    ready: BendList<Scheduled>,
    known: Node,
    previous: Node,
    state: Node,
    failure: Node,
  ): BendList<
    { readonly position: bigint; readonly result: Result<PreparedGroup> }
  >;
  "check_groups"(
    ready: BendList<Scheduled>,
    known: Node,
    previous: Node,
    state: Node,
    failure: Node,
  ): BendList<
    { readonly position: bigint; readonly result: Result<PreparedGroup> }
  >;
  "complete_preparation"(
    prepared: Result<PreparedGroup>,
  ): Result<PreparedGroup>;
  "check_frontier"(
    ready: BendList<Scheduled>,
    known: Node,
    previous: Node,
    progress: Node,
  ): Node;
  "check_frontier_sized"(
    ready: BendList<Scheduled>,
    known: Node,
    previous: Node,
    progress: Node,
    small: boolean,
  ): Node;
  "staged_frontier"(
    ready: BendList<Scheduled>,
    known: Node,
    small: boolean,
  ): boolean;
  "plan_entries"(
    entries: BendList<KeyedEntry>,
    previous: Node,
    plan: EntryPlan,
  ): EntryPlan;
  "compile_entry_plan"(
    plan: EntryPlan,
    next: Node,
    reversed: BendList<Node>,
    counts: Node,
  ): Result<Node>;
};
const job = (key: string, body: Node): Job => ({
  $: "CodegenJob",
  key,
  parameter: "value",
  body,
  captures: bendList([]),
});

function checkCatalog(module: Node): Node {
  const prepared = backend["catalog_versions.prepare"](
    module.data_types as BendList<Node>,
    module.operations as BendList<Node>,
    { $: "None" },
  );
  ok(prepared.$ === "Done");
  return {
    $: "CheckCatalog",
    catalog: backend["check_scheduler.catalog"](module),
    revision: prepared.value.revision,
  };
}

Deno.test("pipelined codegen preserves cold, mixed-hit, reordered and evicted caches", () => {
  const jobs = Array.from(
    { length: 16 },
    (_, index) =>
      job(`fn:pipeline_${index}`, {
        $: "ArrayExpr",
        elements: bendList(Array.from(
          { length: index < 4 ? 1024 : 3 },
          (_, value) => ({ $: "U32Expr", value: value + index }),
        )),
      }),
  );
  const empty = backend["empty_checked"]().groups;
  const counts = { $: "Counts", fresh: 0n, reused: 0n };
  let previous = empty;
  for (
    const input of [
      jobs,
      jobs,
      [
        job(jobs[0].key, { $: "U32Expr", value: 42 }),
        ...jobs.slice(1),
      ],
      jobs.toReversed(),
      jobs.slice(0, 3),
      [],
    ]
  ) {
    const tasks = backend["entry_key_tasks"](bendList(input), bendList([]));
    const pipelined = backend["compile_weighted_entries"](
      tasks,
      previous,
      empty,
      bendList([]),
      counts,
      false,
    );
    const staged = backend["compile_weighted_entries"](
      tasks,
      previous,
      empty,
      bendList([]),
      counts,
      true,
    );
    // Linked byte lists exceed the recursive assertion implementation's stack.
    const pending: [unknown, unknown][] = [[pipelined, staged]];
    for (let pair = pending.pop(); pair; pair = pending.pop()) {
      const [left, right] = pair;
      if (
        typeof left !== "object" || left === null ||
        typeof right !== "object" || right === null
      ) {
        equal(left, right);
      } else {
        equal(Object.keys(left), Object.keys(right));
        for (const [key, value] of Object.entries(left)) {
          pending.push([value, (right as Record<string, unknown>)[key]]);
        }
      }
    }
    ok(pipelined.$ === "Done");
    previous = pipelined.value.entries as Node;
  }
});

Deno.test("pipelined codegen retains source-order errors across keying and compilation", () => {
  const empty = backend["empty_checked"]().groups;
  const earlier = job("fn:earlier", { $: "LocalExpr", name: "missing" });
  const later = job("fn:later", { $: "U32Expr", value: 42 });
  const failure: Diagnostic = {
    $: "Diagnostic",
    code: "cache_key_complexity",
    subject: later.key,
    message: "synthetic key failure",
  };
  const first = backend["compile_keyed_entry"]({
    $: "KeyedEntry",
    job: earlier,
    encoded: backend["native_cache_keys.entry"](earlier),
  }, empty);
  const second = backend["compile_keyed_entry"]({
    $: "KeyedEntry",
    job: later,
    encoded: { $: "Fail", error: failure },
  }, empty);
  ok(first.$ === "Fail");
  equal(first.error.subject, "missing");
  for (const results of [[first, second], [second, first]]) {
    equal(
      backend["publish_compiled_entries"](
        bendList(results),
        empty,
        bendList([]),
        { $: "Counts", fresh: 0n, reused: 0n },
      ),
      results[0],
    );
  }
});

Deno.test("frontier routing keeps tiny jobs staged and pipelines substantial groups", () => {
  for (const heavy of [false, true]) {
    const functions = Array.from({ length: 8 }, (_, index) => ({
      $: "Function",
      name: `work_${index}`,
      exported: false,
      parameter: "value",
      parameter_type: { $: "None" },
      result_type: { $: "None" },
      body: heavy
        ? {
          $: "ArrayExpr",
          elements: bendList(
            Array.from(
              { length: 256 },
              (_, value) => ({ $: "U32Expr", value }),
            ),
          ),
        }
        : { $: "U32Expr", value: 1 },
    }));
    const known = checkCatalog({
      $: "Module",
      functions: bendList(functions),
      constants: bendList([]),
      data_types: bendList([]),
      operations: bendList([]),
    });
    const ready: Scheduled[] = functions.map((fn, index) => ({
      $: "Scheduled",
      position: BigInt(index),
      level: 0n,
      job: {
        $: "Job",
        members: bendList([fn.name]),
        dependencies: bendList([]),
        type_dependencies: bendList([]),
      },
    }));
    equal(backend["staged_frontier"](bendList(ready), known, false), !heavy);
    equal(
      backend["staged_frontier"](bendList(ready.slice(0, 4)), known, true),
      true,
    );
  }
});

Deno.test("pipelined frontiers and singleton fast paths equal ordered two-stage checking", () => {
  const names = Array.from({ length: 48 }, (_, index) => `work_${index}`);
  const catalog = checkCatalog({
    $: "Module",
    constants: bendList([]),
    data_types: bendList([]),
    operations: bendList([]),
    functions: bendList(names.map((name, index) => ({
      $: "Function",
      name,
      exported: false,
      parameter: "value",
      parameter_type: { $: "None" },
      result_type: { $: "None" },
      body: {
        $: "ArrayExpr",
        elements: bendList(Array.from(
          { length: index < 8 ? 256 : 8 },
          (_, value) => ({ $: "U32Expr", value }),
        )),
      },
    }))),
  });
  const ready: Scheduled[] = names.map((name, index) => ({
    $: "Scheduled",
    position: BigInt(index),
    level: 0n,
    job: {
      $: "Job",
      members: bendList([name]),
      dependencies: bendList(index === 2 ? ["missing_dependency"] : []),
      type_dependencies: bendList([]),
    },
  }));
  const state = backend["empty_checked"]();
  const normalize = (result: Result<PreparedGroup>) =>
    result.$ === "Fail" ? result : {
      ...result.value,
      base_key: bendArray(result.value.base_key),
      keys: bendArray(result.value.keys).map(bendArray),
    };
  for (const count of [0, 1, 4, 5, 48]) {
    for (const cutoff of [0, 1, 16, 48]) {
      const failure: Node = cutoff === 48 ? { $: "None" } : {
        $: "Some",
        value: {
          $: "Failure",
          position: BigInt(cutoff),
          diagnostic: {
            $: "Diagnostic",
            code: "earlier_failure",
            subject: "earlier",
            message: "prior frontier failed",
          },
        },
      };
      const actual = bendArray(backend["prepare_groups"](
        bendList(ready.slice(0, count)),
        catalog,
        state.groups,
        state,
        failure,
      ));
      const expected = ready.slice(0, Math.min(count, cutoff));
      equal(
        actual.map(({ position }) => position),
        expected.map(({ position }) => position),
      );
      actual.forEach(({ result }, index) => {
        equal(
          normalize(result),
          normalize(backend["prepare_group"](
            expected[index].position,
            expected[index].job,
            catalog,
            state.groups,
            state,
          )),
        );
      });
      const pipelined = bendArray(backend["check_groups"](
        bendList(ready.slice(0, count)),
        catalog,
        state.groups,
        state,
        failure,
      ));
      equal(
        pipelined.map(({ position }) => position),
        actual.map(({ position }) => position),
      );
      pipelined.forEach(({ result }, index) => {
        equal(
          normalize(result),
          normalize(backend["complete_preparation"](actual[index].result)),
        );
      });
      const progress = { $: "GroupProgress", checked: state, failure };
      equal(
        backend["check_frontier"](
          bendList(ready.slice(0, count)),
          catalog,
          state.groups,
          progress,
        ),
        backend["check_frontier_sized"](
          bendList(ready.slice(0, count)),
          catalog,
          state.groups,
          progress,
          true,
        ),
      );
    }
  }
});

Deno.test("parallel entry keys equal serial keys and preserve uneven source order", () => {
  const jobs = Array.from({ length: 48 }, (_, index) =>
    job(`fn:λ_${index}`, {
      $: "ArrayExpr",
      elements: bendList(Array.from(
        { length: index < 8 ? 1024 : 3 },
        (_, value) => ({ $: "U32Expr", value: value + index }),
      )),
    }));
  for (const input of [[], jobs.slice(0, 1), jobs, jobs.toReversed()]) {
    const actual = bendArray(
      backend["keyed_entries"](bendList(input)),
    );
    equal(actual.map(({ job }) => job.key), input.map(({ key }) => key));
    actual.forEach(({ job, encoded }) => {
      const expected = backend["native_cache_keys.entry"](job);
      ok(encoded.$ === "Done" && expected.$ === "Done");
      equal(bendArray(encoded.value), bendArray(expected.value));
    });
  }
});

Deno.test("parallel key failures preserve earlier compile errors and discard later results", () => {
  const earlier = job("fn:earlier", { $: "LocalExpr", name: "missing" });
  const failing = job("fn:key_failure", { $: "U32Expr", value: 1 });
  const later = job("fn:later", { $: "U32Expr", value: 2 });
  const failure: Diagnostic = {
    $: "Diagnostic",
    code: "cache_key_complexity",
    subject: failing.key,
    message: "synthetic key failure",
  };
  const encoded = bendArray(
    backend["keyed_entries"](
      bendList([earlier, failing, later]),
    ),
  );
  const empty = backend["empty_checked"]().groups;
  const initial: EntryPlan = {
    $: "EntryPlan",
    selections: bendList([]),
    missing: bendList([]),
    failure: { $: "None" },
  };
  const plan = backend["plan_entries"](
    bendList([
      encoded[0],
      { ...encoded[1], encoded: { $: "Fail", error: failure } },
      encoded[2],
    ]),
    empty,
    initial,
  );
  equal(bendArray(plan.missing), [earlier]);
  equal(bendArray(plan.selections).length, 1);
  equal(plan.failure, { $: "Some", value: failure });
  const result = backend["compile_entry_plan"](
    plan,
    empty,
    bendList([]),
    { $: "Counts", fresh: 0n, reused: 0n },
  );
  ok(result.$ === "Fail");
  ok(result.error.code !== failure.code);
  equal(result.error.subject, "missing");
  const noEarlierMiss = backend["plan_entries"](
    bendList([{ ...encoded[1], encoded: { $: "Fail", error: failure } }]),
    empty,
    initial,
  );
  equal(
    backend["compile_entry_plan"](
      noEarlierMiss,
      empty,
      bendList([]),
      { $: "Counts", fresh: 0n, reused: 0n },
    ),
    { $: "Fail", error: failure },
  );
});
