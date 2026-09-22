import { deepStrictEqual as equal, ok } from "node:assert/strict";
import compiled from "../generated/compiler/native_session.js";
import { bendArray, type BendList, bendList } from "./bend_list.ts";

type Node = { readonly $: string; readonly [field: string]: unknown };
type Result<T> = { readonly $: "Done"; readonly value: T } | {
  readonly $: "Fail";
  readonly error: Node;
};
interface Scanned {
  readonly $: "Scanned";
  readonly functions: Result<BendList<Node>>;
  readonly constants: Result<BendList<Node>>;
  readonly costs: Node;
}
interface Nominals {
  readonly $: "Nominals";
  readonly functions: Result<BendList<Node>>;
  readonly constants: Result<BendList<Node>>;
}
const backend = compiled as unknown as {
  "native_plan.nominal_scan"(module: Node, constructors: Node): Nominals;
  "native_plan.merge_nominals"(left: Nominals, right: Nominals): Nominals;
  "native_plan.nominal_usages"(scan: Nominals): Result<BendList<Node>>;
  "groups.prepare_plan_usages"(
    module: Node,
    graph: Result<BendList<Node>>,
    usages: Result<BendList<Node>>,
  ): Result<Node>;
  "refresh_nominals"(lowered: Node, context: Node): Node;
  "cache_nominal_scans"(
    scans: BendList<Scanned>,
    work: bigint,
    count: bigint,
  ): boolean;
  "groups.constructor_index"(types: BendList<Node>, index: Node): Node;
  "native_plan.scan"(module: Node): Scanned;
  "native_plan.graph"(
    module: Node,
    scans: BendList<Scanned>,
  ): Result<BendList<Node>>;
  "check.module_graph"(module: Node): Result<BendList<Node>>;
  "groups.prepare_plan"(module: Node): Result<Node>;
  "groups.prepare_plan_graph"(
    module: Node,
    graph: Result<BendList<Node>>,
  ): Result<Node>;
  "native_plan.collect_costs"(scans: BendList<Scanned>, costs: Node): Node;
  "check_scheduler.catalog_costs"(module: Node, costs: Node): Node;
  "check_scheduler.group_cost"(catalog: Node, job: Node): bigint;
  "check_scheduler.group_module"(catalog: Node, job: Node): Node;
  "check_scheduler.module_cost"(module: Node): bigint;
};
const module = (functions: Node[], constants: Node[] = []): Node => ({
  $: "Module",
  functions: bendList(functions),
  constants: bendList(constants),
  data_types: bendList([]),
  operations: bendList([]),
});
const fn = (name: string, body: Node): Node => ({
  $: "Function",
  name,
  exported: false,
  parameter: "value",
  parameter_type: { $: "None" },
  result_type: { $: "None" },
  body,
});
const constant = (name: string, value: Node): Node => ({
  $: "Constant",
  name,
  exported: false,
  annotation: { $: "None" },
  value,
});
const failure = (code: string): Result<BendList<Node>> => ({
  $: "Fail",
  error: { $: "Diagnostic", code, subject: "probe", message: code },
});
const empty = (): Result<BendList<Node>> => ({
  $: "Done",
  value: bendList([]),
});

Deno.test("cached declaration scans preserve whole-module dependency and planning order", () => {
  const functions = [
    fn("first", { $: "FunctionExpr", name: "second" }),
    fn("second", { $: "U32Expr", value: 1 }),
  ];
  const constants = [constant("saved", { $: "FunctionExpr", name: "first" })];
  const complete = module(functions, constants);
  const fragments = [
    module([], constants),
    module(functions.slice(0, 1)),
    module(functions.slice(1)),
  ];
  const scans = fragments.map((fragment) =>
    backend["native_plan.scan"](fragment)
  );
  const cached = backend["native_plan.graph"](complete, bendList(scans));
  const original = backend["check.module_graph"](complete);
  equal(cached, original);
  ok(cached.$ === "Done");
  equal(bendArray(cached.value).map((node) => node.name), [
    "first",
    "second",
    "saved",
  ]);
  equal(
    backend["groups.prepare_plan_graph"](complete, cached),
    backend["groups.prepare_plan"](complete),
  );
  equal(backend["native_plan.graph"](module([]), bendList([])), empty());
});

Deno.test("cached scan failures retain global validation and function-before-constant precedence", () => {
  const scans: Scanned[] = [
    {
      $: "Scanned",
      functions: empty(),
      constants: failure("constant_scan"),
      costs: { $: "MTip" },
    },
    {
      $: "Scanned",
      functions: failure("function_scan"),
      constants: empty(),
      costs: { $: "MTip" },
    },
  ];
  equal(
    backend["native_plan.graph"](module([]), bendList(scans)),
    failure("function_scan"),
  );
  const repeated = fn("same", { $: "U32Expr", value: 0 });
  const duplicate = module([repeated, repeated]);
  equal(
    backend["native_plan.graph"](duplicate, bendList(scans)),
    backend["check.module_graph"](duplicate),
  );
});

Deno.test("cached scans still reject lambda identities duplicated across fragments", () => {
  const functions = ["first", "second"].map((name) =>
    fn(name, {
      $: "LambdaExpr",
      identity: 42n,
      parameter: "x",
      parameter_type: { $: "None" },
      result_type: { $: "None" },
      body: { $: "LocalExpr", name: "x" },
    })
  );
  const complete = module(functions);
  const scans = functions.map((value) =>
    backend["native_plan.scan"](module([value]))
  );
  const result = backend["native_plan.graph"](complete, bendList(scans));
  equal(result, backend["check.module_graph"](complete));
  ok(result.$ === "Fail");
  equal(result.error.code, "duplicate_lambda");
});

Deno.test("nominal summaries preserve function-before-constant order and validation precedence", () => {
  const fragments = [
    module([], [constant("saved", { $: "U32Expr", value: 1 })]),
    module([fn("read", { $: "U32Expr", value: 2 })]),
  ];
  const complete = module([fn("read", { $: "U32Expr", value: 2 })], [
    constant("saved", { $: "U32Expr", value: 1 }),
  ]);
  const scans = fragments.map((fragment) =>
    backend["native_plan.nominal_scan"](fragment, { $: "MTip" })
  );
  const usages = backend["native_plan.nominal_usages"](
    backend["native_plan.merge_nominals"](scans[0], scans[1]),
  );
  ok(usages.$ === "Done");
  equal(bendArray(usages.value).map((usage) => usage.name), ["read", "saved"]);
  equal(
    backend["groups.prepare_plan_usages"](
      complete,
      backend["check.module_graph"](complete),
      usages,
    ),
    backend["groups.prepare_plan"](complete),
  );
  const failures = backend["native_plan.nominal_usages"](
    backend["native_plan.merge_nominals"](
      {
        $: "Nominals",
        functions: empty(),
        constants: failure("constant_usage"),
      },
      {
        $: "Nominals",
        functions: failure("function_usage"),
        constants: empty(),
      },
    ),
  );
  equal(failures, failure("function_usage"));
  equal(
    backend["groups.prepare_plan_usages"](complete, failure("graph"), failures),
    failure("graph"),
  );
});

Deno.test("retained nominal summaries invalidate when constructor ownership changes", () => {
  const fragment = module([
    fn("construct", { $: "ConstructorRefExpr", constructor: "Carry" }),
  ]);
  const lowered: Node = {
    $: "Lowered",
    node: {
      $: "Cst",
      kind: "function",
      field: "declarations",
      text: "",
      offset: 1n,
      children: bendList([]),
    },
    fuel: 10000n,
    fragment,
    scanned: backend["native_plan.scan"](fragment),
    nominals: { $: "None" },
  };
  const identity = (declaration: string): Node => ({
    $: "TypeId",
    module_name: "main",
    declaration,
  });
  const context = (key: number, declaration: string) => ({
    $: "NominalContext",
    key: bendList([key]),
    constructors: backend["groups.constructor_index"](
      bendList([{
        $: "DataType",
        identity: identity(declaration),
        parameters: 0n,
        constructors: bendList([{
          $: "Constructor",
          name: "Carry",
          payload: { $: "Some", value: { $: "U32Ty" } },
        }]),
      }]),
      { $: "MTip" },
    ),
  });
  const first = backend["refresh_nominals"](
    lowered,
    context(1, "Left"),
  );
  equal(
    backend["refresh_nominals"](first, context(1, "Left")),
    first,
  );
  const changed = backend["refresh_nominals"](
    first,
    context(2, "Right"),
  );
  equal(
    changed,
    backend["refresh_nominals"](lowered, context(2, "Right")),
  );
  equal(changed.nominals, {
    $: "Some",
    value: {
      $: "Cached",
      keys: bendList([bendList([2])]),
      value: backend["native_plan.nominal_scan"](
        fragment,
        context(2, "Right").constructors,
      ),
    },
  });
  ok(
    JSON.stringify(
      first,
      (_, value) => typeof value === "bigint" ? String(value) : value,
    ) !==
      JSON.stringify(
        changed,
        (_, value) => typeof value === "bigint" ? String(value) : value,
      ),
  );
});

Deno.test("nominal caching uses an average work threshold and rejects empty scans", () => {
  const select = (work: bigint, count: bigint) =>
    backend["cache_nominal_scans"](bendList([]), work, count);
  equal(select(0n, 0n), false);
  equal(select(511n, 2n), false);
  equal(select(512n, 2n), true);
  equal(select(513n, 2n), true);
  const tiny = backend["native_plan.scan"](
    module([fn("tiny", { $: "U32Expr", value: 0 })]),
  );
  const large = backend["native_plan.scan"](
    module([
      fn("large", {
        $: "ArrayExpr",
        elements: bendList(
          Array.from({ length: 1024 }, (_, value) => ({ $: "U32Expr", value })),
        ),
      }),
    ]),
  );
  equal(backend["cache_nominal_scans"](bendList([tiny]), 0n, 0n), false);
  equal(backend["cache_nominal_scans"](bendList([tiny, large]), 0n, 0n), true);
});

Deno.test("cached declaration costs preserve group weights and fall back for uncached members", () => {
  const functions = Array.from(
    { length: 8 },
    (_, index) =>
      fn(`work_${index}`, {
        $: "ArrayExpr",
        elements: bendList(
          Array.from(
            { length: index * 31 + 1 },
            (_, value) => ({ $: "U32Expr", value }),
          ),
        ),
      }),
  );
  const complete = module(functions, [
    constant("saved", { $: "U32Expr", value: 42 }),
  ]);
  const scans = functions.map((value) =>
    backend["native_plan.scan"](module([value]))
  );
  const costs = backend["native_plan.collect_costs"](bendList(scans), {
    $: "MTip",
  });
  const catalog = backend["check_scheduler.catalog_costs"](complete, costs);
  for (
    const members of [[], ["work_0"], ["work_7"], ["work_0", "work_7"], [
      "work_0",
      "saved",
    ]]
  ) {
    const job = {
      $: "Job",
      members: bendList(members),
      dependencies: bendList([]),
      type_dependencies: bendList([]),
    };
    equal(
      backend["check_scheduler.group_cost"](catalog, job),
      backend["check_scheduler.module_cost"](
        backend["check_scheduler.group_module"](catalog, job),
      ),
    );
  }
});
