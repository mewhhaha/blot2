import { deepStrictEqual as equal, ok } from "node:assert/strict";
import generated from "../generated/compiler/compiler.js";
import { bendArray, type BendList, bendList } from "./bend_list.ts";

type Node = { readonly $: string; readonly [field: string]: unknown };
interface Job {
  readonly $: "CodegenJob";
  readonly key: string;
  readonly parameter: string;
  readonly body: Node;
  readonly captures: BendList<string>;
}
type Entry = Omit<Job, "$"> & { readonly $: "Entry" };
interface WeightedEntry<JobType = Job> {
  readonly $: "WeightedEntry";
  readonly job: JobType;
  readonly weight: bigint;
}
type Batch<JobType = Job> =
  | {
    readonly $: "SequentialEntries";
    readonly entries: BendList<WeightedEntry<JobType>>;
  }
  | {
    readonly $: "ParallelEntries";
    readonly left: Batch<JobType>;
    readonly right: Batch<JobType>;
  };
type Result<T> =
  | { readonly $: "Done"; readonly value: T }
  | {
    readonly $: "Fail";
    readonly error: {
      readonly code: string;
      readonly subject: string;
      readonly message: string;
    };
  };
type Fragment =
  | { readonly $: "Bytes"; readonly bytes: BendList<number> }
  | { readonly $: "NamedCall" | "EntryIndex"; readonly key: string }
  | { readonly $: "Allocate" }
  | {
    readonly $: "ConstantReference" | "ConstructorIndex";
    readonly name: string;
  }
  | { readonly $: "OperationIndex"; readonly identity: Node };
interface EntryCode {
  readonly $: "EntryCode";
  readonly key: string;
  readonly code: {
    readonly $: "Code";
    readonly fragments: BendList<Fragment>;
    readonly locals: bigint;
  };
}
const backend = generated as unknown as {
  "wasm.codegen_grain"(): bigint;
  "wasm.codegen_weight"(job: Job): bigint;
  "wasm.plan_entries"(jobs: BendList<Job>, grain: bigint): Batch;
  "wasm.compile_entry"(job: Job): Result<EntryCode>;
  "wasm.compile_entries_with_grain"(
    grain: bigint,
    jobs: BendList<Job>,
  ): Result<BendList<EntryCode>>;
  "wasm.preparation_grain"(): bigint;
  "wasm.plan_preparations"(
    entries: BendList<Entry>,
    grain: bigint,
  ): Batch<Entry>;
  "wasm.prepare_jobs_with_grain"(
    grain: bigint,
    entries: BendList<Entry>,
    projection: Node,
  ): Result<BendList<Job>>;
  "codegen_ir.prepare"(body: Node, projection: Node): Result<Node>;
  "codegen_ir.metadata"(lambdas: BendList<Node>, constructors: Node): Node;
};
const integer = (value: number): Node => ({ $: "U32Expr", value });
const array = (length: number): Node => ({
  $: "ArrayExpr",
  elements: bendList(Array.from({ length }, (_, index) => integer(index))),
});
const job = (key: string, body: Node = integer(42)): Job => ({
  $: "CodegenJob",
  key,
  parameter: "value",
  body,
  captures: bendList([]),
});

function leaves<JobType>(batch: Batch<JobType>): WeightedEntry<JobType>[][] {
  const result: WeightedEntry<JobType>[][] = [];
  const pending = [batch];
  for (let current = pending.pop(); current; current = pending.pop()) {
    if (current.$ === "SequentialEntries") {
      result.push(bendArray(current.entries));
    } else {
      pending.push(current.right, current.left);
    }
  }
  return result;
}

function comparableEntries(entries: BendList<EntryCode>) {
  return bendArray(entries).map((entry) => ({
    ...entry,
    code: {
      ...entry.code,
      fragments: bendArray(entry.code.fragments).map((fragment) =>
        fragment.$ === "Bytes"
          ? { ...fragment, bytes: bendArray(fragment.bytes) }
          : fragment
      ),
    },
  }));
}

Deno.test("codegen work estimates include IR, pattern, and capture work", () => {
  equal(backend["wasm.codegen_weight"](job("scalar")), 9n);
  equal(backend["wasm.codegen_weight"](job("array", array(3))), 12n);
  equal(
    backend["wasm.codegen_weight"](job("closure", {
      $: "ClosureExpr",
      key: "fn:target",
      captures: bendList(["first", "second", "third"]),
    })),
    12n,
  );
  equal(
    backend["wasm.codegen_weight"](job("pattern", {
      $: "MatchExpr",
      values: bendList([integer(1)]),
      arms: bendList([{
        $: "MatchArm",
        patterns: bendList([{
          $: "ProductPattern",
          elements: bendList([
            { $: "WildcardPattern" },
            { $: "WildcardPattern" },
          ]),
        }]),
        body: integer(42),
      }]),
    })),
    15n,
  );
});

Deno.test("codegen grain boundaries form sequential leaves without tiny fork tasks", () => {
  const grain = backend["wasm.codegen_grain"]();
  ok(grain > 9n);
  const minimum = Number((grain + 8n) / 9n);
  const tiny = Array.from(
    { length: minimum * 2 },
    (_, index) => job("tiny_" + index),
  );
  const below = backend["wasm.plan_entries"](
    bendList(tiny.slice(1)),
    grain,
  );
  equal(below.$, "SequentialEntries");
  const at = backend["wasm.plan_entries"](bendList(tiny), grain);
  equal(at.$, "ParallelEntries");
  const batches = leaves(at);
  equal(batches.length, 2);
  ok(
    batches.every((batch) =>
      batch.reduce((sum, entry) => sum + entry.weight, 0n) >= grain
    ),
  );
  equal(batches.flat().map(({ job }) => job.key), tiny.map(({ key }) => key));
  for (const jobs of [[], [job("only")]]) {
    equal(
      backend["wasm.plan_entries"](bendList(jobs), 0n).$,
      "SequentialEntries",
    );
  }
});

Deno.test("codegen partitions by estimated work at the nearer ordered boundary", () => {
  const jobs = [
    job("first", array(2551)),
    job("heavy", array(4087)),
    job("last", array(503)),
  ];
  const plan = backend["wasm.plan_entries"](bendList(jobs), 512n);
  ok(plan.$ === "ParallelEntries");
  equal(leaves(plan.left).flat().map(({ job }) => job.key), ["first"]);
  equal(leaves(plan.right).flat().map(({ job }) => job.key), ["heavy", "last"]);
  equal(
    backend["wasm.plan_entries"](bendList([jobs[1], job("tiny")]), 512n).$,
    "SequentialEntries",
  );
});

Deno.test("serial and coarse codegen preserve complete entry output and ordering", () => {
  const jobs = Array.from({ length: 12 }, (_, index) =>
    job("entry_" + index, {
      $: "ArrayGetExpr",
      array: array(160),
      index: integer(index),
    }));
  jobs.splice(4, 0, {
    ...job("captured", { $: "LocalExpr", name: "capture" }),
    captures: bendList(["capture"]),
  });
  const serial = backend["wasm.compile_entries_with_grain"](
    1_000_000n,
    bendList(jobs),
  );
  ok(serial.$ === "Done");
  const expected = comparableEntries(serial.value);
  equal(
    expected.map(({ key }) => key),
    jobs.map(({ key }) => key),
  );
  for (const grain of [0n, 1n, 128n, 512n, 1024n, 2048n, 0xffff_ffff_ffffn]) {
    const actual = backend["wasm.compile_entries_with_grain"](
      grain,
      bendList(jobs),
    );
    ok(actual.$ === "Done");
    equal(comparableEntries(actual.value), expected);
  }
});

Deno.test("parallel codegen keeps the first source-order diagnostic across batches", () => {
  const invalid = (name: string) =>
    job(name, {
      $: "SequenceExpr",
      first: array(600),
      next: { $: "LocalExpr", name },
    });
  const first = invalid("missing_first");
  const expected = backend["wasm.compile_entry"](first);
  ok(expected.$ === "Fail");
  const jobs = [job("valid", array(600)), first, invalid("missing_later")];
  for (const grain of [0n, 1n, 512n, 1_000_000n]) {
    equal(
      backend["wasm.compile_entries_with_grain"](grain, bendList(jobs)),
      expected,
    );
  }
  const scalar = job("scalar", {
    $: "ScalarExpr",
    operator: { $: "Add" },
    left: { $: "LocalExpr", name: "left_missing" },
    right: { $: "LocalExpr", name: "right_missing" },
  });
  const error = backend["wasm.compile_entry"](scalar);
  ok(error.$ === "Fail");
  equal(error.error.subject, "left_missing");
});

const entry = (key: string, body: Node = integer(42)): Entry => ({
  ...job(key, body),
  $: "Entry",
});

Deno.test("projection batches keep tiny work serial and balance clustered expensive entries", () => {
  const grain = backend["wasm.preparation_grain"]();
  const tiny = Array.from({ length: 64 }, (_, index) => entry(`tiny_${index}`));
  equal(
    backend["wasm.plan_preparations"](bendList(tiny), grain).$,
    "SequentialEntries",
  );
  for (const entries of [[], [entry("single", array(10_000))]]) {
    equal(
      backend["wasm.plan_preparations"](bendList(entries), 0n).$,
      "SequentialEntries",
    );
  }
  const clustered = [
    ...Array.from(
      { length: 8 },
      (_, index) => entry(`large_${index}`, array(2048)),
    ),
    ...tiny,
  ];
  const batches = leaves(
    backend["wasm.plan_preparations"](bendList(clustered), grain),
  );
  equal(
    batches.flat().map(({ job }) => job.key),
    clustered.map(({ key }) => key),
  );
  ok(
    batches.filter((batch) =>
      batch.some(({ job }) => job.key.startsWith("large_"))
    ).length >= 7,
  );
  ok(
    batches.every((batch) =>
      batch.reduce((total, entry) => total + entry.weight, 0n) >= grain
    ),
  );
  const lambda = entry("reference", {
    $: "LambdaExpr",
    identity: 7n,
    parameter: "argument",
    parameter_type: { $: "None" },
    result_type: { $: "None" },
    body: array(10_000),
  });
  equal(
    leaves(backend["wasm.plan_preparations"](bendList([lambda]), grain))[0][0]
      .weight,
    9n,
  );
});

Deno.test("parallel projection matches ordered independent preparation across grains", () => {
  const lambda: Node = {
    $: "Lambda",
    identity: 7n,
    parameter: "argument",
    body: integer(42),
    captures: bendList(["capture"]),
  };
  const metadata = backend["codegen_ir.metadata"](bendList([lambda]), {
    $: "MTip",
  });
  const entries = Array.from(
    { length: 64 },
    (_, index) =>
      entry(
        `entry_${index}`,
        index === 32
          ? {
            $: "LambdaExpr",
            identity: 7n,
            parameter: "argument",
            parameter_type: { $: "None" },
            result_type: { $: "None" },
            body: integer(99),
          }
          : array(index < 8 ? 1024 : 8),
      ),
  );
  const expected = entries.map(({ key, parameter, body, captures }): Job => {
    const prepared = backend["codegen_ir.prepare"](body, metadata);
    ok(prepared.$ === "Done");
    return { $: "CodegenJob", key, parameter, body: prepared.value, captures };
  });
  for (const grain of [0n, 128n, 512n, 2048n, 0xffff_ffff_ffffn]) {
    const actual = backend["wasm.prepare_jobs_with_grain"](
      grain,
      bendList(entries),
      metadata,
    );
    ok(actual.$ === "Done");
    equal(bendArray(actual.value), expected);
  }
});

Deno.test("parallel projection preserves the first error across batch boundaries", () => {
  const metadata = backend["codegen_ir.metadata"](bendList([]), { $: "MTip" });
  const invalid = (constructor: string) =>
    entry(constructor, {
      $: "SequenceExpr",
      first: array(1024),
      next: { $: "ConstructorRefExpr", constructor },
    });
  const first = invalid("missing_first");
  const expected = backend["codegen_ir.prepare"](first.body, metadata);
  ok(expected.$ === "Fail");
  equal(expected.error.subject, "missing_first");
  const entries = [
    entry("valid", array(1024)),
    first,
    ...Array.from({ length: 30 }, (_, index) => invalid(`later_${index}`)),
  ];
  for (const grain of [0n, 128n, 512n, 2048n, 0xffff_ffff_ffffn]) {
    equal(
      backend["wasm.prepare_jobs_with_grain"](
        grain,
        bendList(entries),
        metadata,
      ),
      expected,
    );
  }
});
