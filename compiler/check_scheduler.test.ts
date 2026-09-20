import { deepStrictEqual as equal, ok } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { bendArray, type BendList, bendList } from "./bend_list.ts";

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
interface Job {
  readonly $: "Job";
  readonly members: BendList<string>;
  readonly dependencies: BendList<string>;
  readonly type_dependencies: BendList<never>;
}
interface Scheduled {
  readonly $: "Scheduled";
  readonly position: bigint;
  readonly level: bigint;
  readonly job: Job;
}
interface Task {
  readonly $: "Task";
  readonly position: bigint;
  readonly module: unknown;
  readonly dependencies: BendList<unknown>;
  readonly cost: bigint;
}
interface Outcome {
  readonly $: "Outcome";
  readonly position: bigint;
  readonly checked: Result<unknown>;
}
type Batch = {
  readonly $: "Sequential";
  readonly tasks: BendList<Task>;
} | { readonly $: "Parallel"; readonly left: Batch; readonly right: Batch };

const scheduler = compiled as unknown as {
  "check_scheduler.schedule"(jobs: BendList<Job>): Result<BendList<Scheduled>>;
  "check_scheduler.check_batch_with_grain"(
    tasks: BendList<Task>,
    grain: bigint,
  ): BendList<Outcome>;
  "check_scheduler.partition"(
    tasks: BendList<Task>,
    reversed: BendList<Task>,
    left: bigint,
    total: bigint,
    target: bigint,
    reached: boolean,
  ): unknown;
  "check_scheduler.forkable"(parts: unknown, grain: bigint): unknown;
  "check_scheduler.batches"(
    fuel: bigint,
    parts: unknown,
    grain: bigint,
    parallel: unknown,
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
  "check_scheduler.check_module"(module: unknown): Result<unknown>;
  "check.check_module"(module: unknown): Result<unknown>;
  "groups.checked_group"(module: unknown): Result<unknown>;
};

function unwrap<T>(result: Result<T>): T {
  if (result.$ === "Fail") throw result.error;
  return result.value;
}

function job(members: string[], dependencies: string[] = []): Job {
  return {
    $: "Job",
    members: bendList(members),
    dependencies: bendList(dependencies),
    type_dependencies: bendList([]),
  };
}

const unit = { $: "UnitExpr" };
const integer = (value: number) => ({ $: "U32Expr", value });
const call = (callee: string) => ({ $: "CallExpr", callee, argument: unit });
const add = (left: unknown, right: unknown) => ({
  $: "ScalarExpr",
  operator: { $: "Add" },
  left,
  right,
});

function fn(name: string, body: unknown, parameter = "value") {
  return {
    $: "Function",
    name,
    exported: false,
    parameter,
    parameter_type: { $: "Some", value: { $: "UnitTy" } },
    result_type: { $: "Some", value: { $: "U32Ty" } },
    body,
  };
}

function module(functions: unknown[]) {
  return {
    $: "Module",
    constants: bendList([]),
    functions: bendList(functions),
    data_types: bendList([]),
    operations: bendList([]),
  };
}

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
        $: "Diagnostic",
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
      $: "Scheduled",
      position: BigInt(position),
      level: BigInt(levels[position]),
      job,
    })).sort((a, b) => Number(a.level - b.level || a.position - b.position));
    equal(actual, expected, `DAG ${trial}`);
  }
});

Deno.test("inference grain preserves ordered results and keeps small or indivisible leaves sequential", () => {
  const tasks: Task[] = Array.from({ length: 16 }, (_, position) => ({
    $: "Task",
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
    const total = tasks.reduce((cost, task) => cost + task.cost, 0n);
    const parts = scheduler["check_scheduler.partition"](
      bendList(tasks),
      bendList([]),
      0n,
      total,
      total / 2n,
      false,
    );
    return scheduler["check_scheduler.batches"](
      BigInt(tasks.length),
      parts,
      grain,
      scheduler["check_scheduler.forkable"](parts, grain),
    );
  };
  equal(tree(tasks.slice(1, 3), 1024n).$, "Sequential");
  equal(tree([{ ...tasks[0], cost: 1_000_000n }], 0n).$, "Sequential");
  equal(tree(tasks, 256n).$, "Parallel");
  const uneven = tree([
    { ...tasks[0], cost: 600n },
    { ...tasks[1], cost: 600n },
    { ...tasks[2], cost: 1500n },
  ], 1024n);
  ok(uneven.$ === "Parallel");
  ok(uneven.left.$ === "Sequential" && uneven.right.$ === "Sequential");
  equal(bendArray(uneven.left.tasks).map(({ position }) => position), [0n, 1n]);
  equal(bendArray(uneven.right.tasks).map(({ position }) => position), [2n]);
});

Deno.test("a later ready inference error cannot hide an earlier blocked group error", () => {
  const source = module([
    fn("seed", integer(1)),
    fn("earlier", add(call("seed"), unit)),
    fn("later", { $: "LocalExpr", name: "missing" }),
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
      $: "Completed",
      interfaces: { $: "MTip" },
      functions: { $: "MTip" },
      constants: { $: "MTip" },
      failure: { $: "None" },
    },
  ));
  const actual = scheduler["check_scheduler.assembled"](source, completed);
  ok(actual.$ === "Fail");
  equal(actual.error.code, "type_mismatch");
  equal(actual.error.subject, "earlier");
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
  const serial = unwrap(scheduler["check.check_module"](source));
  const ready = unwrap(scheduler["check_scheduler.check_module"](source));
  equal(
    scheduler["groups.checked_group"](ready),
    scheduler["groups.checked_group"](serial),
  );
});
