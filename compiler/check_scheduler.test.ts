import { deepStrictEqual as equal, ok } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { bendArray, type BendList, bendList } from "./bend_list.ts";

interface Diagnostic {
  readonly $: "model.Diagnostic";
  readonly code: string;
  readonly subject: string;
  readonly message: string;
}
type Result<T> = { readonly $: "Done"; readonly value: T } | {
  readonly $: "Fail";
  readonly error: Diagnostic;
};
type InitialAttempt = {
  readonly $: "check_scheduler.CheckedInitial";
  readonly initial: {
    readonly certificates: BendList<Record<string, unknown>>;
    readonly needs: BendList<Record<string, unknown>>;
    readonly checked: unknown;
  };
  readonly inferred: bigint;
  readonly retained: bigint;
} | {
  readonly $: "check_scheduler.FailedInitial";
  readonly diagnostic: Diagnostic;
  readonly certificates: BendList<unknown>;
  readonly inferred: bigint;
  readonly retained: bigint;
};
interface Job {
  readonly $: "groups.Job";
  readonly members: BendList<string>;
  readonly dependencies: BendList<string>;
  readonly type_dependencies: BendList<never>;
}
interface Scheduled {
  readonly $: "check_scheduler.Scheduled";
  readonly position: bigint;
  readonly level: bigint;
  readonly job: Job;
}
interface Chain {
  readonly $: "check_chain_plan.Chain";
  readonly position: bigint;
  readonly level: bigint;
  readonly jobs: BendList<
    {
      readonly $: "check_chain_plan.Job";
      readonly position: bigint;
      readonly job: Job;
    }
  >;
}
interface Task {
  readonly $: "check_scheduler.Task";
  readonly position: bigint;
  readonly module: unknown;
  readonly dependencies: BendList<unknown>;
  readonly cost: bigint;
}
interface Outcome {
  readonly $: "check_scheduler.Outcome";
  readonly position: bigint;
  readonly checked: Result<unknown>;
}
type Batch = {
  readonly $: "inference_batch.Sequential";
  readonly tasks: BendList<
    {
      readonly $: "inference_batch.Weighted";
      readonly value: Task;
      readonly cost: bigint;
    }
  >;
} | {
  readonly $: "inference_batch.Parallel";
  readonly left: Batch;
  readonly right: Batch;
};

const scheduler = compiled as unknown as {
  "check_regions.rooted_plan"(chains: BendList<Chain>): Result<{
    readonly prefix: BendList<Chain>;
    readonly regions: BendList<{ readonly chains: BendList<Chain> }>;
  }>;
  "check_regions.partition"(chains: BendList<Chain>): Result<
    BendList<{
      readonly $: "check_regions.Region";
      readonly chains: BendList<Chain>;
    }>
  >;
  "check_chain_plan.plan"(jobs: BendList<Job>): Result<BendList<Chain>>;
  "check_chain_plan.next_frontier"(chains: BendList<Chain>): {
    readonly ready: BendList<Chain>;
    readonly pending: BendList<Chain>;
  };
  "check_scheduler.check_jobs"(
    jobs: BendList<Job>,
    catalog: unknown,
    completed: unknown,
    dependent: boolean,
  ): Result<unknown>;
  "check_scheduler.schedule"(jobs: BendList<Job>): Result<BendList<Scheduled>>;
  "check_scheduler.check_batch_with_grain"(
    tasks: BendList<Task>,
    grain: bigint,
  ): BendList<Outcome>;
  "check_scheduler.task_batch"(
    tasks: BendList<Task>,
    grain: bigint,
  ): Batch;
  "check_scheduler.catalog"(module: unknown): unknown;
  "check_scheduler.next_frontier"(jobs: BendList<Scheduled>): unknown;
  "check_scheduler.check_frontiers"(
    fuel: bigint,
    frontier: unknown,
    catalog: unknown,
    completed: unknown,
  ): Result<unknown>;
  "check_scheduler.assembled"(
    module: unknown,
    completed: unknown,
  ): Result<unknown>;
  "check_scheduler.empty_completed"(): unknown;
  "check_scheduler.with_core"(
    catalog: unknown,
    module: unknown,
    certificates: BendList<unknown>,
  ): unknown;
  "check_scheduler.has_dependencies"(jobs: BendList<Job>): boolean;
  "groups.plan"(module: unknown): Result<BendList<Job>>;
  "groups.check_group"(
    module: unknown,
    dependencies: BendList<unknown>,
  ): Result<
    { readonly checked: unknown; readonly interfaces: BendList<unknown> }
  >;
  "check_scheduler.check_module"(module: unknown): Result<unknown>;
  "check_scheduler.check_module_resolving_probe"(
    module: unknown,
    certificates: BendList<unknown>,
  ): InitialAttempt;
  "check_scheduler.check_module_resolving_reusing"(
    module: unknown,
    certificates: BendList<unknown>,
    previous: unknown,
  ): InitialAttempt;
  "resolving_core.pair"(
    certificate: unknown,
    needs: BendList<unknown>,
  ): { readonly $: "Some"; readonly value: unknown } | { readonly $: "None" };
  "resolving_core.matches"(
    witness: unknown,
    subset: unknown,
    imports: unknown,
  ): { readonly $: "Some"; readonly value: unknown } | { readonly $: "None" };
};

function unwrap<T>(result: Result<T>): T {
  if (result.$ === "Fail") throw result.error;
  return result.value;
}

function checkedWithInterfaces(module: unknown): {
  checked: Result<unknown>;
  interfaces: BendList<unknown>;
} {
  const jobs = unwrap(scheduler["groups.plan"](module));
  const completed = unwrap(scheduler["check_scheduler.check_jobs"](
    jobs,
    scheduler["check_scheduler.with_core"](
      scheduler["check_scheduler.catalog"](module),
      module,
      bendList([]),
    ),
    scheduler["check_scheduler.empty_completed"](),
    scheduler["check_scheduler.has_dependencies"](jobs),
  ));
  return {
    checked: scheduler["check_scheduler.assembled"](module, completed),
    interfaces: (completed as { readonly published: BendList<unknown> })
      .published,
  };
}

function byName(interfaces: BendList<unknown>): unknown[] {
  return bendArray(interfaces).sort((left, right) =>
    String((left as { name: string }).name).localeCompare(
      String((right as { name: string }).name),
    )
  );
}

function job(members: string[], dependencies: string[] = []): Job {
  return {
    $: "groups.Job",
    members: bendList(members),
    dependencies: bendList(dependencies),
    type_dependencies: bendList([]),
  };
}

const unit = { $: "model.UnitExpr" };
const integer = (value: number) => ({ $: "model.U32Expr", value });
const call = (callee: string) => ({
  $: "model.CallExpr",
  callee,
  argument: unit,
});
const add = (left: unknown, right: unknown) => ({
  $: "model.ScalarExpr",
  operator: { $: "model.Add" },
  left,
  right,
});

Deno.test("completed shared roots release independent branches but preserve unfinished joins", () => {
  const jobs = [
    job(["root", "root_alias"]),
    job(["left_a"], ["root"]),
    job(["left_b"], ["root_alias"]),
    job(["left_join"], ["left_a", "left_b"]),
    job(["right_a"], ["root"]),
    job(["right_b"], ["root"]),
    job(["right_join"], ["right_a", "right_b"]),
  ];
  const regions = (input: Job[]) => {
    const planned = unwrap(scheduler["check_regions.rooted_plan"](
      unwrap(scheduler["check_chain_plan.plan"](bendList(input))),
    ));
    equal(
      bendArray(planned.prefix).flatMap((chain) =>
        bendArray(chain.jobs).map(({ position }) => Number(position))
      ),
      [0],
    );
    return bendArray(planned.regions).map((region) =>
      bendArray(region.chains).flatMap((chain) =>
        bendArray(chain.jobs).map(({ position }) => Number(position))
      ).sort((a, b) => a - b)
    ).sort((a, b) => a[0] - b[0]);
  };
  equal(regions(jobs), [[1, 2, 3], [4, 5, 6]]);
  equal(regions([...jobs, job(["final"], ["left_join", "right_join"])]), [
    [1, 2, 3, 4, 5, 6, 7],
  ]);
  const invalid: Chain = {
    $: "check_chain_plan.Chain",
    position: 1n,
    level: 1n,
    jobs: bendList([{
      $: "check_chain_plan.Job",
      position: 1n,
      job: job(["bad"], ["unknown"]),
    }]),
  };
  const root = bendArray(unwrap(
    scheduler["check_chain_plan.plan"](bendList([jobs[0]])),
  ))[0];
  const rejected = scheduler["check_regions.rooted_plan"](
    bendList([root, invalid]),
  );
  ok(rejected.$ === "Fail");
  equal(rejected.error.subject, "unknown");
});

Deno.test("shared multi-root frontiers release branches without synchronizing independent regions", () => {
  const plan = (jobs: Job[]) =>
    unwrap(scheduler["check_regions.rooted_plan"](
      unwrap(scheduler["check_chain_plan.plan"](bendList(jobs))),
    ));
  const jobs = [
    job(["root_a", "alias"]),
    job(["root_b"]),
    job(["left_a"], ["root_a", "root_b"]),
    job(["left_b"], ["alias", "root_b"]),
    job(["left_join"], ["left_a", "left_b"]),
    job(["right_a"], ["root_a", "root_b"]),
    job(["right_b"], ["root_a", "root_b"]),
    job(["right_join"], ["right_a", "right_b"]),
  ];
  const released = plan(jobs);
  equal(bendArray(released.prefix).map((chain) => chain.position), [0n, 1n]);
  equal(bendArray(released.regions).length, 2);
  equal(
    bendArray(
      plan([...jobs, job(["final"], ["left_join", "right_join"])]).regions,
    ).length,
    1,
  );
  const independent = plan([
    job(["left"]),
    job(["left_1"], ["left"]),
    job(["left_2"], ["left"]),
    job(["right"]),
    job(["right_1"], ["right"]),
    job(["right_2"], ["right"]),
  ]);
  equal(bendArray(independent.prefix), []);
  equal(bendArray(independent.regions).length, 2);
  const finalBatch = plan([
    job(["root_a"]),
    job(["root_b"]),
    ...Array.from(
      { length: 8 },
      (_, index) => job([`leaf_${index}`], ["root_a", "root_b"]),
    ),
  ]);
  equal(bendArray(finalBatch.prefix), []);
  equal(bendArray(finalBatch.regions).length, 1);
});

Deno.test("dependency chains contract only single-consumer edges and preserve SCCs, joins and aliases", () => {
  const verify = (jobs: Job[]) => {
    const owners = new Map<string, number>();
    const dependencies: Set<number>[] = [];
    const consumers = jobs.map(() => new Set<number>());
    jobs.forEach((job, position) => {
      dependencies.push(
        new Set(
          bendArray(job.dependencies).map((name) => {
            const owner = owners.get(name);
            ok(owner !== undefined);
            consumers[owner].add(position);
            return owner;
          }),
        ),
      );
      bendArray(job.members).forEach((name) => owners.set(name, position));
    });
    const heads: number[] = [];
    const expected = new Map<number, { level: number; jobs: number[] }>();
    jobs.forEach((_, position) => {
      const parents = [...dependencies[position]];
      const parent = parents[0];
      if (parents.length === 1 && consumers[parent].size === 1) {
        heads.push(heads[parent]);
        expected.get(heads[parent])!.jobs.push(position);
      } else {
        heads.push(position);
        expected.set(position, {
          level: parents.length
            ? Math.max(
              ...parents.map((parent) => expected.get(heads[parent])!.level),
            ) + 1
            : 0,
          jobs: [position],
        });
      }
    });
    const planned = unwrap(scheduler["check_chain_plan.plan"](bendList(jobs)));
    const regions = bendArray(unwrap(
      scheduler["check_regions.partition"](planned),
    ));
    const regionOf = new Map<number, number>();
    regions.forEach((region, regionIndex) => {
      const chains = bendArray(region.chains);
      equal(
        chains,
        chains.toSorted((a, b) =>
          Number(a.level - b.level || a.position - b.position)
        ),
      );
      for (const chain of chains) {
        for (const assigned of bendArray(chain.jobs)) {
          const position = Number(assigned.position);
          ok(!regionOf.has(position));
          equal(assigned.job, jobs[position]);
          regionOf.set(position, regionIndex);
        }
      }
    });
    equal(regionOf.size, jobs.length);
    const connected = jobs.map((_, position) => new Set([position]));
    dependencies.forEach((parents, position) => {
      for (const parent of parents) {
        equal(regionOf.get(parent), regionOf.get(position));
        const combined = new Set([
          ...connected[parent],
          ...connected[position],
        ]);
        for (const member of combined) connected[member] = combined;
      }
    });
    equal(regions.length, new Set(connected).size);
    equal(
      bendArray(planned).map((chain) => ({
        position: Number(chain.position),
        level: Number(chain.level),
        jobs: bendArray(chain.jobs).map(({ position, job }) => {
          equal(job, jobs[Number(position)]);
          return Number(position);
        }),
      })),
      [...expected].map(([position, chain]) => ({ position, ...chain }))
        .sort((a, b) => a.level - b.level || a.position - b.position),
    );
    let pending = planned;
    let count = 0;
    while (pending.$ === "Con") {
      const frontier = scheduler["check_chain_plan.next_frontier"](pending);
      const ready = bendArray(frontier.ready);
      ok(ready.length > 0);
      ok(ready.every((chain) => chain.level === ready[0].level));
      if (frontier.pending.$ === "Con") {
        ok(frontier.pending.head.level > ready[0].level);
      }
      count += ready.length;
      pending = frontier.pending;
    }
    equal(count, expected.size);
  };
  verify([]);
  verify([
    job(["seed", "alias"]),
    job(["middle"], ["seed", "alias"]),
    job(["left"], ["middle"]),
    job(["right"], ["middle"]),
    job(["join"], ["left", "right"]),
    job(["answer"], ["join"]),
    job(["independent"]),
  ]);
  let seed = 813;
  const random = () => seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
  for (let trial = 0; trial < 256; trial++) {
    verify(Array.from({ length: 1 + random() % 24 }, (_, position) =>
      job(
        [`node_${position}`, `alias_${position}`],
        Array.from({ length: position }, (_, parent) => parent)
          .filter(() => random() % 5 === 0)
          .flatMap((parent) =>
            random() % 2
              ? [`node_${parent}`, `alias_${parent}`]
              : [`alias_${parent}`]
          ),
      )));
  }
  equal(
    scheduler["check_chain_plan.plan"](bendList([job(["a"], ["missing"])])),
    scheduler["check_scheduler.schedule"](bendList([job(["a"], ["missing"])])),
  );
});

function fn(name: string, body: unknown, parameter = "value") {
  return {
    $: "model.Function",
    name,
    exported: false,
    parameter,
    parameter_type: { $: "Some", value: { $: "model.UnitTy" } },
    result_type: { $: "Some", value: { $: "model.U32Ty" } },
    body,
  };
}

function module(functions: unknown[]) {
  return {
    $: "model.Module",
    constants: bendList([]),
    functions: bendList(functions),
    data_types: bendList([]),
    operations: bendList([]),
  };
}

Deno.test("failed source checks retain exact completed groups and preserve checker diagnostic order", () => {
  const immediate = module([fn("only", unit)]);
  const immediateAttempt = scheduler
    ["check_scheduler.check_module_resolving_probe"](
      immediate,
      bendList([]),
    );
  ok(immediateAttempt.$ === "check_scheduler.FailedInitial");
  const immediateBaseline = scheduler["check_scheduler.check_module"](
    immediate,
  );
  ok(immediateBaseline.$ === "Fail");
  equal(immediateAttempt.diagnostic, immediateBaseline.error);
  equal(bendArray(immediateAttempt.certificates), []);

  const healthy = module([
    fn("good", integer(7)),
    fn("early", integer(1)),
    fn("late", integer(2)),
  ]);
  const healthyAttempt = scheduler
    ["check_scheduler.check_module_resolving_probe"](
      healthy,
      bendList([]),
    );
  ok(healthyAttempt.$ === "check_scheduler.CheckedInitial");

  const catalogEdit = scheduler["check_scheduler.check_module_resolving_probe"](
    {
      ...healthy,
      operations: bendList([{
        $: "model.Operation",
        identity: {
          $: "model.TypeId",
          module_name: "main",
          declaration: "Unused",
        },
        parameter: { $: "model.UnitTy" },
        result: { $: "model.U32Ty" },
      }]),
    },
    healthyAttempt.initial.certificates,
  );
  ok(catalogEdit.$ === "check_scheduler.CheckedInitial");
  // A new unused operation does not change a ready certificate's dependencies.
  equal(catalogEdit.retained, healthyAttempt.inferred);
  const changedCatalog = scheduler
    ["check_scheduler.check_module_resolving_probe"](
      {
        ...healthy,
        operations: bendList([{
          $: "model.Operation",
          identity: {
            $: "model.TypeId",
            module_name: "main",
            declaration: "Unused",
          },
          parameter: { $: "model.UnitTy" },
          result: { $: "model.BoolTy" },
        }]),
      },
      catalogEdit.initial.certificates,
    );
  ok(changedCatalog.$ === "check_scheduler.CheckedInitial");
  equal(changedCatalog.retained, 0n);
  equal(changedCatalog.inferred, healthyAttempt.inferred);

  const source = module([
    fn("good", integer(7)),
    fn("early", unit),
    fn("late", unit),
  ]);
  const first = scheduler["check_scheduler.check_module_resolving_probe"](
    source,
    bendList([]),
  );
  ok(first.$ === "check_scheduler.FailedInitial");
  const baseline = scheduler["check_scheduler.check_module"](source);
  ok(baseline.$ === "Fail");
  equal(first.diagnostic, baseline.error);
  // Independent checking owns the diagnostic order, including its SCC order.
  ok(bendArray(first.certificates).length > 0);
  ok(first.inferred > 0n);
  equal(first.retained, 0n);

  const warmEdit = scheduler["check_scheduler.check_module_resolving_probe"](
    source,
    healthyAttempt.initial.certificates,
  );
  ok(warmEdit.$ === "check_scheduler.FailedInitial");
  equal(warmEdit.diagnostic, first.diagnostic);
  ok(
    warmEdit.retained > 0n,
    "a failed edit reuses unchanged successful groups",
  );

  const dispatchEdit = module([
    fn("good", integer(7)),
    fn("early", integer(1)),
    fn("late", {
      $: "model.AssociatedExpr",
      identity: 123n,
      dispatch: { $: "model.BinaryDispatch" },
      member: "missing",
      templates: bendList([]),
      left: integer(1),
      right: integer(2),
    }),
  ]);
  const introduced = scheduler["check_scheduler.check_module_resolving_probe"](
    dispatchEdit,
    healthyAttempt.initial.certificates,
  );
  ok(
    introduced.retained > 0n,
    "a newly introduced dispatch retains unchanged no-dispatch groups",
  );

  const warm = scheduler["check_scheduler.check_module_resolving_probe"](
    source,
    first.certificates,
  );
  ok(warm.$ === "check_scheduler.FailedInitial");
  equal(warm.diagnostic, first.diagnostic);
  ok(warm.retained > 0n, "the warm failed check must actually retain a group");
  equal(warm.inferred, 0n);

  const changed = module([
    fn("good", integer(8)),
    fn("early", unit),
    fn("late", unit),
  ]);
  const edited = scheduler["check_scheduler.check_module_resolving_probe"](
    changed,
    first.certificates,
  );
  ok(edited.$ === "check_scheduler.FailedInitial");
  equal(edited.diagnostic, first.diagnostic);
  equal(
    edited.retained,
    0n,
    "an edited source group cannot use stale evidence",
  );
  ok(edited.inferred > 0n);
});

Deno.test("ready inference frontiers preserve SCC members and dependency levels", () => {
  equal(
    unwrap(scheduler["check_scheduler.schedule"](bendList([]))),
    bendList([]),
  );
  const jobs = [job(["a", "a_alias"]), job(["b"], ["a_alias"]), job(["c"])];
  equal(
    bendArray(unwrap(scheduler["check_scheduler.schedule"](bendList(jobs))))
      .map(({ position, level }) => [position, level]),
    [[0n, 0n], [2n, 0n], [1n, 1n]],
  );
  equal(
    scheduler["check_scheduler.schedule"](bendList([job(["a"], ["missing"])])),
    {
      $: "Fail",
      error: {
        $: "model.Diagnostic",
        code: "internal_error",
        subject: "missing",
        message: "incremental plan omitted a required checked dependency",
      },
    },
  );

  let seed = 331;
  const random = () => seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
  for (let trial = 0; trial < 256; trial++) {
    const count = 1 + random() % 16;
    const levels: number[] = [];
    const jobs = Array.from({ length: count }, (_, index) => {
      const earlier = Array.from({ length: index }, (_, target) => target)
        .filter(() => random() % 4 === 0);
      levels.push(
        earlier.length ? 1 + Math.max(...earlier.map((i) => levels[i])) : 0,
      );
      return job(
        [`node_${index}`, `alias_${index}`],
        earlier.map((target) => `${random() % 2 ? "node" : "alias"}_${target}`),
      );
    });
    const actual = bendArray(
      unwrap(scheduler["check_scheduler.schedule"](bendList(jobs))),
    );
    const expected = jobs.map((job, position) => ({
      $: "check_scheduler.Scheduled",
      position: BigInt(position),
      level: BigInt(levels[position]),
      job,
    })).sort((a, b) => Number(a.level - b.level || a.position - b.position));
    equal(actual, expected, `DAG ${trial}`);
  }
});

Deno.test("inference grain preserves ordered results and keeps small or indivisible leaves sequential", () => {
  const tasks: Task[] = Array.from({ length: 16 }, (_, position) => ({
    $: "check_scheduler.Task",
    position: BigInt(position),
    module: module([
      fn(`value_${position}`, position === 5 ? unit : integer(position)),
    ]),
    dependencies: bendList([]),
    cost: position % 4 === 0 ? 1024n : 128n,
  }));
  const expected = scheduler["check_scheduler.check_batch_with_grain"](
    bendList(tasks),
    1_000_000n,
  );
  for (const grain of [0n, 1n, 256n, 1024n]) {
    equal(
      scheduler["check_scheduler.check_batch_with_grain"](
        bendList(tasks),
        grain,
      ),
      expected,
    );
  }
  equal(
    bendArray(expected).map(({ position }) => position),
    tasks.map(({ position }) => position),
  );
  const failure = bendArray(expected)[5].checked;
  ok(failure.$ === "Fail");
  equal(failure.error.code, "type_mismatch");

  const tree = (tasks: Task[], grain: bigint) => {
    return scheduler["check_scheduler.task_batch"](bendList(tasks), grain);
  };
  equal(tree(tasks.slice(1, 3), 1024n).$, "inference_batch.Sequential");
  equal(
    tree([{ ...tasks[0], cost: 1_000_000n }], 0n).$,
    "inference_batch.Sequential",
  );
  equal(tree(tasks, 256n).$, "inference_batch.Parallel");
  const uneven = tree([
    { ...tasks[0], cost: 600n },
    { ...tasks[1], cost: 600n },
    { ...tasks[2], cost: 1500n },
  ], 1024n);
  ok(uneven.$ === "inference_batch.Parallel");
  ok(
    uneven.left.$ === "inference_batch.Sequential" &&
      uneven.right.$ === "inference_batch.Sequential",
  );
  equal(bendArray(uneven.left.tasks).map(({ value }) => value.position), [
    0n,
    1n,
  ]);
  equal(bendArray(uneven.right.tasks).map(({ value }) => value.position), [2n]);
});

Deno.test("a later ready inference error cannot hide an earlier blocked group error", () => {
  const source = module([
    fn("seed", integer(1)),
    fn("earlier", add(call("seed"), unit)),
    fn("later", { $: "model.LocalExpr", name: "missing" }),
  ]);
  const plan = unwrap(scheduler["check_scheduler.schedule"](bendList([
    job(["seed"]),
    job(["earlier"], ["seed"]),
    job(["later"]),
  ])));
  const completed = unwrap(scheduler["check_scheduler.check_frontiers"](
    3n,
    scheduler["check_scheduler.next_frontier"](plan),
    scheduler["check_scheduler.catalog"](source),
    {
      $: "check_scheduler.Completed",
      interfaces: { $: "MTip" },
      functions: { $: "MTip" },
      constants: { $: "MTip" },
      published: bendList([]),
      failure: { $: "None" },
      certificates: bendList([]),
      needs: bendList([]),
    },
  ));
  const actual = scheduler["check_scheduler.assembled"](source, completed);
  ok(actual.$ === "Fail");
  equal(actual.error.code, "type_mismatch");
  equal(actual.error.subject, "earlier");
  const chained = unwrap(scheduler["check_scheduler.check_jobs"](
    bendList([job(["seed"]), job(["earlier"], ["seed"]), job(["later"])]),
    scheduler["check_scheduler.catalog"](source),
    {
      $: "check_scheduler.Completed",
      interfaces: { $: "MTip" },
      functions: { $: "MTip" },
      constants: { $: "MTip" },
      published: bendList([]),
      failure: { $: "None" },
      certificates: bendList([]),
      needs: bendList([]),
    },
    true,
  ));
  equal(scheduler["check_scheduler.assembled"](source, chained), actual);
});

Deno.test("ready grouped checking agrees with serial inference interfaces on a diamond and recursive SCC", () => {
  const source = module([
    fn("answer", add(call("left"), call("right"))),
    fn("left", call("seed")),
    fn("right", call("seed")),
    fn("recursive_a", call("recursive_b")),
    fn("recursive_b", call("recursive_a")),
    fn("seed", integer(21)),
  ]);
  const ready = unwrap(scheduler["check_scheduler.check_module"](source));
  const readyWithInterfaces = checkedWithInterfaces(source);
  const serialGroup = unwrap(scheduler["groups.check_group"](
    source,
    bendList([]),
  ));
  equal(readyWithInterfaces.checked, { $: "Done", value: ready });
  equal(byName(readyWithInterfaces.interfaces), byName(serialGroup.interfaces));
});

Deno.test("resolving reuse retains complete deferred requirements across unrelated edits", () => {
  const deferred = fn("deferred", {
    $: "model.AssociatedExpr",
    identity: 17n,
    dispatch: { $: "model.BinaryDispatch" },
    member: "add",
    templates: bendList([]),
    left: { $: "model.U32Expr", value: 1 },
    right: { $: "model.U32Expr", value: 2 },
  });
  const original = module([
    deferred,
    fn("other", { $: "model.U32Expr", value: 3 }),
  ]);
  const first = scheduler["check_scheduler.check_module_resolving_probe"](
    original,
    bendList([]),
  );
  ok(first.$ === "check_scheduler.CheckedInitial");
  ok(
    bendArray(first.initial.needs).length > 0,
    "fixture must carry deferred evidence",
  );
  const edited = module([
    deferred,
    fn("other", { $: "model.U32Expr", value: 4 }),
  ]);
  const fresh = scheduler["check_scheduler.check_module_resolving_probe"](
    edited,
    bendList([]),
  );
  const reused = scheduler["check_scheduler.check_module_resolving_reusing"](
    edited,
    first.initial.certificates,
    first.initial,
  );
  ok(fresh.$ === "check_scheduler.CheckedInitial");
  ok(reused.$ === "check_scheduler.CheckedInitial");
  equal(reused.initial, fresh.initial);

  const certificates = bendArray(first.initial.certificates);
  const witnesses = certificates.map((certificate) => ({
    certificate,
    pair: scheduler["resolving_core.pair"](certificate, first.initial.needs),
  }));
  for (const { certificate, pair } of witnesses) {
    ok(pair.$ === "Some");
    ok(
      scheduler["resolving_core.matches"](
        pair.value,
        certificate.module,
        certificate.imports,
      ).$ === "Some",
    );
  }
});

Deno.test("resolving witness rejects malformed, duplicated and changed evidence", () => {
  const original = module([fn("deferred", {
    $: "model.AssociatedExpr",
    identity: 17n,
    dispatch: { $: "model.BinaryDispatch" },
    member: "add",
    templates: bendList([]),
    left: { $: "model.U32Expr", value: 1 },
    right: { $: "model.U32Expr", value: 2 },
  })]);
  const first = scheduler["check_scheduler.check_module_resolving_probe"](
    original,
    bendList([]),
  );
  ok(first.$ === "check_scheduler.CheckedInitial");
  const [certificate] = bendArray(first.initial.certificates);
  const [need] = bendArray(first.initial.needs);
  ok(certificate && need);
  equal(scheduler["resolving_core.pair"](certificate, bendList([need, need])), {
    $: "None",
  });
  equal(
    scheduler["resolving_core.pair"](
      certificate,
      bendList([{ ...need, members: bendList([]) }]),
    ),
    { $: "None" },
  );
  const pair = scheduler["resolving_core.pair"](
    certificate,
    first.initial.needs,
  );
  ok(pair.$ === "Some");
  const changed = {
    ...original,
    operations: bendList([{
      $: "model.OperationTemplate",
      identity: {
        $: "model.TypeId",
        module_name: "effects",
        declaration: "Read",
      },
      parameters: 1n,
      parameter: { $: "model.UnitTy" },
      result: { $: "model.ParameterTy", index: 0n },
    }]),
  };
  equal(
    scheduler["resolving_core.matches"](
      pair.value,
      changed,
      certificate.imports,
    ),
    { $: "None" },
  );
  equal(
    scheduler["resolving_core.matches"](
      pair.value,
      module([fn("deferred", { $: "model.U32Expr", value: 3 })]),
      certificate.imports,
    ),
    { $: "None" },
  );
  const imported = bendList([{
    $: "groups.Interface",
    name: "newDependency",
    predicates: bendList([]),
    kind: { $: "groups.ConstantInterface" },
    template: { $: "model.U32Ty" },

    parameters: 0n,
    effects: bendList([]),
  }]);
  equal(scheduler["resolving_core.matches"](pair.value, original, imported), {
    $: "None",
  });
});
