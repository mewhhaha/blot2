import {
  deepStrictEqual as equal,
  notDeepStrictEqual as differs,
  ok,
  throws,
} from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import type { CoreModule, DataType, Expr, TypeId } from "./host.ts";
import {
  add,
  boolType,
  call,
  descriptor,
  fn,
  integer,
  local,
  module,
  read,
  scalarExample,
  u32Type,
  unit,
} from "./fixtures.ts";

type List<A> =
  | { readonly $: "Nil" }
  | { readonly $: "Con"; readonly head: A; readonly tail: List<A> };

interface Diagnostic {
  readonly $: "Diagnostic";
  readonly code: string;
  readonly subject: string;
  readonly message: string;
}

type Result<A> =
  | { readonly $: "Done"; readonly value: A }
  | { readonly $: "Fail"; readonly error: Diagnostic };

interface Job {
  readonly $: "Job";
  readonly members: List<string>;
  readonly dependencies: List<string>;
  readonly type_dependencies: List<TypeId>;
}

interface Interface {
  readonly $: "Interface";
  readonly name: string;
  readonly kind: {
    readonly $: "groups.FunctionInterface" | "groups.ConstantInterface";
  };
  readonly template: unknown;
  readonly parameters: bigint;
  readonly effects: List<unknown>;
}

interface CheckedGroup {
  readonly $: "CheckedGroup";
  readonly checked: unknown;
  readonly interfaces: List<Interface>;
}

const groups = compiled as unknown as {
  "groups.prepare_plan"(module: unknown): Result<unknown>;
  "groups.finish_plan"(planning: unknown): Result<List<Job>>;
  "groups.plan"(module: unknown): Result<List<Job>>;
  "groups.job_module"(module: unknown, job: Job): Result<unknown>;
  "groups.check_group"(
    module: unknown,
    dependencies: List<Interface>,
  ): Result<CheckedGroup>;
  "groups.checked_group"(checked: unknown): Result<CheckedGroup>;
  "check.check_module"(module: unknown): Result<unknown>;
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

function unwrap<A>(result: Result<A>): A {
  if (result.$ === "Fail") throw result.error;
  return result.value;
}

const nullary = new Set([
  "UnitTy",
  "U32Ty",
  "BoolTy",
  "NeverTy",
  "UnitExpr",
  "WildcardPattern",
  "UnitPattern",
  "Add",
  "Subtract",
  "Multiply",
  "Equal",
  "LessThan",
  "Component",
  "Resource",
  "Read",
  "Write",
  "Insert",
]);
const optional = new Set([
  "annotation",
  "parameter_type",
  "result_type",
  "payload",
]);
const elementTag = new Map([
  ["functions", "Function"],
  ["constants", "Constant"],
  ["data_types", "DataType"],
  ["constructors", "Constructor"],
  ["arms", "MatchArm"],
]);

// A test-only adapter for trusted fixtures, not a second inference path.
function wire(value: unknown, tag?: string): unknown {
  if (Array.isArray(value)) return list(value.map((entry) => wire(entry, tag)));
  if (value === null || typeof value !== "object") return value;
  const record: Record<string, unknown> = tag ? { $: tag } : {};
  for (const [field, child] of Object.entries(value)) {
    if (optional.has(field)) {
      record[field] = child === null
        ? { $: "None" }
        : { $: "Some", value: wire(child) };
    } else if (field === "$" && typeof child === "string") {
      record[field] = nullary.has(child) ? `model.${child}` : child;
    } else {
      record[field] = wire(child, elementTag.get(field));
    }
  }
  return record;
}

function byName(interfaces: readonly Interface[]) {
  return [...interfaces].sort((left, right) =>
    left.name.localeCompare(right.name)
  );
}

function grouped(source: CoreModule) {
  const module = wire(source, "Module");
  const jobs = array(unwrap(groups["groups.plan"](module)));
  const interfaces = new Map<string, Interface>();
  const checked: CheckedGroup[] = [];
  for (const job of jobs) {
    const dependencies = array(job.dependencies).map((name) => {
      const dependency = interfaces.get(name);
      ok(dependency, `planned dependency ${name} must have a closed interface`);
      return dependency;
    });
    const result = unwrap(groups["groups.check_group"](
      unwrap(groups["groups.job_module"](module, job)),
      list(dependencies),
    ));
    checked.push(result);
    for (const signature of array(result.interfaces)) {
      interfaces.set(signature.name, signature);
    }
  }
  return { jobs, checked, interfaces: byName([...interfaces.values()]) };
}

function agrees(source: CoreModule) {
  const result = grouped(source);
  const baseline = unwrap(groups["groups.checked_group"](
    unwrap(groups["check.check_module"](wire(source, "Module"))),
  ));
  equal(result.interfaces, byName(array(baseline.interfaces)));
  return result;
}

const boolean = (value: boolean): Expr => ({ $: "BoolExpr", value });
const ctor = (constructor: string, payload: Expr | null = null): Expr => ({
  $: "ConstructExpr",
  constructor,
  payload,
});
const lambda = (identity: bigint, body: Expr): Expr => ({
  $: "LambdaExpr",
  identity,
  parameter: "value",
  parameter_type: null,
  result_type: null,
  body,
});
const maybe: DataType = {
  identity: { $: "TypeId", module_name: "test", declaration: "Maybe" },
  parameters: 1n,
  constructors: [
    { name: "Some", payload: { $: "ParameterTy", index: 0n } },
    { name: "Nothing", payload: null },
  ],
};

Deno.test("independent groups agree with whole-module polymorphic inference", () => {
  agrees(scalarExample);
  const result = agrees(module([
    fn("number", call("identity", integer(42))),
    fn("truth", call("identity", boolean(true))),
    fn("identity", local("value"), { parameter_type: null, exported: false }),
  ]));
  equal(result.jobs.length, 3);
  equal(
    result.interfaces.find((entry) => entry.name === "identity")?.template,
    {
      $: "FunctionTy",
      parameter: { $: "ParameterTy", index: 0n },
      result: { $: "ParameterTy", index: 0n },
    },
  );
});

Deno.test("recursive groups import a shared generic dependency without merging it", () => {
  const result = agrees(module([
    fn("number", call("left", integer(42))),
    fn("truth", call("right", boolean(true))),
    fn("left", {
      $: "IfExpr",
      condition: boolean(true),
      consequent: call("identity", local("value")),
      alternative: call("right", local("value")),
    }, { parameter_type: null, exported: false }),
    fn("right", call("left", local("value")), {
      parameter_type: null,
      exported: false,
    }),
    fn("identity", local("value"), { parameter_type: null, exported: false }),
  ]));
  equal(
    result.jobs.map((job) => array(job.members).sort()).sort(),
    [["identity"], ["left", "right"], ["number"], ["truth"]],
  );
});

Deno.test("pure constants, constructors and higher-order functions cross group interfaces", () => {
  agrees(module([
    fn("make", ctor("Some", local("value")), { parameter_type: null }),
    fn("use_number", call("make", integer(42))),
    fn("use_bool", call("make", boolean(true))),
    fn("apply_identity", {
      $: "ApplyExpr",
      callee: { $: "ConstantExpr", name: "identity" },
      argument: integer(7),
    }),
  ], {
    data_types: [maybe],
    constants: [{
      name: "identity",
      exported: false,
      annotation: null,
      value: lambda(10n, local("value")),
    }],
  }));
});

Deno.test("all callers constraining an effectful monomorphic helper share one job", () => {
  const position = descriptor("Position");
  const nominal = { $: "NominalTy" as const, identity: position.identity };
  const result = agrees(module([
    fn("set_position", { $: "WriteExpr", value: local("value") }, {
      parameter_type: null,
      exported: false,
    }),
    fn("read_position", read(position.identity), { exported: false }),
    fn("move", call("set_position", call("read_position"))),
    fn("again", call("set_position", local("value")), {
      parameter_type: nominal,
    }),
    fn("pure", integer(1)),
  ], { descriptors: [position] }));
  equal(
    result.jobs.map((job) => array(job.members).sort()).sort(),
    [["again", "move", "read_position", "set_position"], ["pure"]],
  );
});

Deno.test("metadata catalogs follow inferred dependency results but exclude unrelated layouts", () => {
  const position = descriptor("Position");
  const velocity = descriptor("Velocity");
  const positionType: DataType = {
    identity: position.identity,
    parameters: 0n,
    constructors: [{ name: "Position", payload: u32Type }],
  };
  const velocityType: DataType = {
    identity: velocity.identity,
    parameters: 0n,
    constructors: [{ name: "Velocity", payload: u32Type }],
  };
  const source = module([
    fn("make_position", ctor("Position", integer(42)), { exported: false }),
    fn("set_position", { $: "WriteExpr", value: call("make_position") }),
    fn("read_velocity", read(velocity.identity)),
  ], {
    descriptors: [position, velocity],
    data_types: [positionType, velocityType],
  });
  const result = agrees(source);
  for (const job of result.jobs) {
    const members = array(job.members);
    equal(
      array(job.type_dependencies),
      [
        members.includes("read_velocity")
          ? velocity.identity
          : position.identity,
      ],
    );
  }
  const changed = {
    ...source,
    data_types: [{
      ...positionType,
      constructors: [{ name: "Position", payload: boolType }],
    }, velocityType],
  };
  const originalJob = result.jobs.find((job) =>
    array(job.members).includes("read_velocity")
  )!;
  const changedJobs = array(
    unwrap(groups["groups.plan"](wire(changed, "Module"))),
  );
  const changedJob = changedJobs.find((job) =>
    array(job.members).includes("read_velocity")
  )!;
  equal(
    groups["groups.job_module"](wire(source, "Module"), originalJob),
    groups["groups.job_module"](wire(changed, "Module"), changedJob),
  );
});

Deno.test("metadata catalogs include transitive constructor payload types and patterns", () => {
  const inner: DataType = {
    identity: { $: "TypeId", module_name: "test", declaration: "Inner" },
    parameters: 0n,
    constructors: [{ name: "Inner", payload: u32Type }],
  };
  const outer: DataType = {
    identity: { $: "TypeId", module_name: "test", declaration: "Outer" },
    parameters: 0n,
    constructors: [{
      name: "Outer",
      payload: { $: "AppliedTy", identity: inner.identity, arguments: [] },
    }],
  };
  const result = agrees(module([
    fn("unwrap", {
      $: "MatchExpr",
      value: local("value"),
      arms: [{
        pattern: {
          $: "ConstructorPattern",
          constructor: "Outer",
          payload: { $: "BindingPattern", name: "inner" },
        },
        body: local("inner"),
      }],
    }, { parameter_type: null }),
  ], { data_types: [inner, outer] }));
  equal(
    new Set(
      array(result.jobs[0].type_dependencies).map((identity) =>
        identity.declaration
      ),
    ),
    new Set(["Inner", "Outer"]),
  );
});

Deno.test("interfaces are stable under fresh-variable shifts and same-type body edits", () => {
  const identity = fn("identity", local("value"), { parameter_type: null });
  const first = agrees(module([identity])).interfaces;
  const second = agrees(module([
    fn("unrelated", lambda(99n, local("value"))),
    {
      ...identity,
      body: { $: "SequenceExpr", first: integer(1), next: local("value") },
    },
  ])).interfaces.filter((entry) => entry.name === "identity");
  equal(first, second);
});

Deno.test("planning preparation excludes bodies while preserving semantic dependencies", () => {
  const original = module([
    fn("identity", local("value"), { parameter_type: null }),
    fn("number", call("identity", integer(1))),
  ]);
  const edited = module([
    original.functions[0],
    fn("number", call("identity", integer(999))),
  ]);
  const prepared = unwrap(
    groups["groups.prepare_plan"](wire(original, "Module")),
  );
  equal(
    prepared,
    unwrap(groups["groups.prepare_plan"](wire(edited, "Module"))),
  );
  equal(
    groups["groups.finish_plan"](prepared),
    groups["groups.plan"](wire(edited, "Module")),
  );
  differs(
    prepared,
    unwrap(groups["groups.prepare_plan"](wire(
      module([
        original.functions[0],
        fn("number", integer(999)),
      ]),
      "Module",
    ))),
  );
  const position = descriptor("Position");
  differs(
    unwrap(groups["groups.prepare_plan"](wire(
      module([fn("number", unit)], {
        descriptors: [position],
      }),
      "Module",
    ))),
    unwrap(groups["groups.prepare_plan"](wire(
      module([
        fn("number", read(position.identity)),
      ], { descriptors: [position] }),
      "Module",
    ))),
  );
});

Deno.test("reusable planning still rejects duplicate lambda identities before cache lookup", () => {
  const prepared = groups["groups.prepare_plan"](wire(
    module([
      fn("left", lambda(77n, integer(1))),
      fn("right", lambda(77n, integer(2))),
    ]),
    "Module",
  ));
  ok(prepared.$ === "Fail");
  equal(prepared.error.code, "duplicate_lambda");
});

Deno.test("planning keys ignore repeated references, reference order and validated lambda IDs", () => {
  const program = (body: Expr, identity: bigint) =>
    module([
      fn("left", local("value"), { parameter_type: null }),
      fn("right", local("value"), { parameter_type: null }),
      fn("use", body),
      fn("closure", lambda(identity, local("value"))),
    ]);
  const original = program(
    add(call("left", integer(1)), call("right", integer(2))),
    10n,
  );
  const edited = program(
    add(
      call("right", integer(3)),
      add(call("left", integer(4)), call("right", integer(5))),
    ),
    999n,
  );
  equal(
    groups["groups.prepare_plan"](wire(original, "Module")),
    groups["groups.prepare_plan"](wire(edited, "Module")),
  );
  agrees(original);
  agrees(edited);
});

function rejectsLikeWhole(source: CoreModule, code: string) {
  const baseline = groups["check.check_module"](wire(source, "Module"));
  ok(baseline.$ === "Fail");
  equal(baseline.error.code, code);
  throws(
    () => grouped(source),
    (error) =>
      typeof error === "object" && error !== null && "code" in error &&
      error.code === code,
  );
}

Deno.test("grouped checking preserves monomorphic caller conflicts and occurs checks", () => {
  const position = descriptor("Position");
  const velocity = descriptor("Velocity");
  rejectsLikeWhole(
    module([
      fn("write", { $: "WriteExpr", value: local("value") }, {
        parameter_type: null,
      }),
      fn("position", call("write", read(position.identity))),
      fn("velocity", call("write", read(velocity.identity))),
    ], { descriptors: [position, velocity] }),
    "type_mismatch",
  );
  rejectsLikeWhole(
    module([fn(
      "self_apply",
      lambda(1n, {
        $: "ApplyExpr",
        callee: local("value"),
        argument: local("value"),
      }),
    )]),
    "infinite_type",
  );
});

Deno.test("grouped checking preserves effect purity, exhaustive matching and unknown-name failures", () => {
  const position = descriptor("Position");
  for (
    const value of [
      call("get"),
      { $: "FunctionExpr", name: "get" } as Expr,
    ]
  ) {
    rejectsLikeWhole(
      module([
        fn("get", read(position.identity), { exported: false }),
        fn("bad", { $: "LetExpr", name: "bound", value, body: unit }),
      ], { descriptors: [position] }),
      value.$ === "CallExpr" ? "let_effect" : "effectful_function_value",
    );
  }
  rejectsLikeWhole(
    module([fn("missing", call("unknown"))]),
    "unknown_function",
  );
  rejectsLikeWhole(
    module([fn("partial", {
      $: "MatchExpr",
      value: local("value"),
      arms: [{
        pattern: {
          $: "ConstructorPattern",
          constructor: "Nothing",
          payload: null,
        },
        body: integer(0),
      }],
    }, { parameter_type: null })], { data_types: [maybe] }),
    "non_exhaustive_match",
  );
});

Deno.test("planning validates unused declarations before selecting minimal catalogs", () => {
  const invalid: DataType = {
    identity: maybe.identity,
    parameters: 0n,
    constructors: [{ name: "Bad", payload: { $: "ParameterTy", index: 0n } }],
  };
  rejectsLikeWhole(
    module([fn("unrelated", integer(1))], { data_types: [invalid] }),
    "invalid_annotation",
  );
  rejectsLikeWhole(
    module([fn("duplicate", integer(1)), fn("duplicate", integer(2))]),
    "duplicate_name",
  );
});

Deno.test("terminal open monomorphic members remain checked but are not exported as schemes", () => {
  const position = descriptor("Position");
  const result = agrees(module([
    fn("read_ignoring_argument", read(position.identity), {
      parameter_type: null,
    }),
  ], { descriptors: [position] }));
  equal(result.interfaces, []);
  equal(result.checked.length, 1);
});

Deno.test("dependency boundaries reject open variables, wrong kinds and polymorphic effects", () => {
  const source = wire(
    module([fn("use_dependency", call("dependency"))]),
    "Module",
  );
  const base: Interface = {
    $: "Interface",
    name: "dependency",
    kind: { $: "groups.FunctionInterface" },
    template: {
      $: "FunctionTy",
      parameter: { $: "model.UnitTy" },
      result: { $: "model.U32Ty" },
    },
    parameters: 0n,
    effects: list([]),
  };
  const malformed = groups["groups.check_group"](
    source,
    list([{
      ...base,
      template: { $: "VariableTy", index: 0n },
    }]),
  );
  ok(malformed.$ === "Fail");
  equal(malformed.error.code, "invalid_annotation");
  const wrongKind = groups["groups.check_group"](
    source,
    list([{
      ...base,
      kind: { $: "groups.ConstantInterface" },
    }]),
  );
  ok(wrongKind.$ === "Fail");
  equal(wrongKind.error.code, "unknown_function");
  const position = descriptor("Position");
  const effectfulSource = wire(
    module([fn("use_dependency", call("dependency"))], {
      descriptors: [position],
    }),
    "Module",
  );
  const effects = list([wire({
    $: "Effect",
    access: { $: "Read" },
    descriptor: position,
  })]);
  const polymorphic = groups["groups.check_group"](
    effectfulSource,
    list([{
      ...base,
      template: {
        $: "FunctionTy",
        parameter: { $: "ParameterTy", index: 0n },
        result: { $: "model.UnitTy" },
      },
      parameters: 1n,
      effects,
    }]),
  );
  ok(polymorphic.$ === "Fail");
  equal(polymorphic.error.code, "invalid_interface");
  const effectfulConstant = groups["groups.check_group"](
    effectfulSource,
    list([{
      ...base,
      kind: { $: "groups.ConstantInterface" },
      effects,
    }]),
  );
  ok(effectfulConstant.$ === "Fail");
  equal(effectfulConstant.error.code, "invalid_interface");
  const inconsistent = groups["groups.check_group"](
    effectfulSource,
    list([{
      ...base,
      effects: list([wire({
        $: "Effect",
        access: { $: "Read" },
        descriptor: { ...position, storage: { $: "Resource" } },
      })]),
    }]),
  );
  ok(inconsistent.$ === "Fail");
  equal(inconsistent.error.code, "invalid_interface");
});

interface DeclarationSummary {
  readonly name: string;
  readonly references: readonly string[];
  readonly effectful: boolean;
  readonly nominals: readonly TypeId[];
}

interface NominalSummary {
  readonly identity: TypeId;
  readonly references: readonly TypeId[];
}

function plannedSummaries(
  declarations: readonly DeclarationSummary[],
  nominals: readonly NominalSummary[],
) {
  return array(unwrap(groups["groups.finish_plan"]({
    $: "Planning",
    nodes: list(declarations.map(({ name, references }) => ({
      $: "Node",
      name,
      references: list(references),
      lambdas: list([]),
    }))),
    usages: list(declarations.map(({ name, effectful, nominals }) => ({
      $: "DeclarationUsage",
      name,
      usage: { $: "Usage", effectful, nominals: list(nominals) },
    }))),
    type_dependencies: list(nominals.map(({ identity, references }) => ({
      $: "TypeDependencies",
      identity,
      references: list(references),
    }))),
  })));
}

function transitiveClosure(edges: readonly (readonly boolean[])[]) {
  const reachable = edges.map((row, from) =>
    row.map((edge, to) => edge || from === to)
  );
  for (let via = 0; via < reachable.length; via++) {
    for (let from = 0; from < reachable.length; from++) {
      for (let to = 0; to < reachable.length; to++) {
        reachable[from][to] ||= reachable[from][via] && reachable[via][to];
      }
    }
  }
  return reachable;
}

const identityKey = ({ module_name, declaration }: TypeId) =>
  JSON.stringify([module_name, declaration]);

function plannerAgreesWithReachability(
  declarations: readonly DeclarationSummary[],
  nominals: readonly NominalSummary[],
) {
  const jobs = plannedSummaries(declarations, nominals);
  const edges = declarations.map(({ references }) =>
    declarations.map(({ name }) => references.includes(name))
  );
  const reachable = transitiveClosure(edges);
  const effectful = declarations.map((_, index) =>
    declarations.some((declaration, target) =>
      declaration.effectful && reachable[index][target]
    )
  );
  const coupled = transitiveClosure(
    edges.map((row, from) =>
      row.map((edge, to) => edge || effectful[from] && edges[to][from])
    ),
  );
  const groupOf = new Map(
    jobs.flatMap((job, index) =>
      array(job.members).map((name) => [name, index] as const)
    ),
  );
  equal(jobs.flatMap((job) => array(job.members)).length, declarations.length);
  equal(groupOf.size, declarations.length);
  for (let from = 0; from < declarations.length; from++) {
    for (let to = 0; to < declarations.length; to++) {
      const source = groupOf.get(declarations[from].name);
      const target = groupOf.get(declarations[to].name);
      ok(source !== undefined && target !== undefined);
      equal(source === target, coupled[from][to] && coupled[to][from]);
      if (edges[from][to]) ok(target <= source, "dependency-first jobs");
    }
  }

  const names = new Set(declarations.map(({ name }) => name));
  const nominalById = new Map(
    nominals.map((nominal) =>
      [identityKey(nominal.identity), nominal] as const
    ),
  );
  for (const job of jobs) {
    const members = new Set(array(job.members));
    const dependencies = new Set(
      declarations.flatMap(({ name, references }) =>
        members.has(name)
          ? references.filter((target) =>
            names.has(target) && !members.has(target)
          )
          : []
      ),
    );
    equal(new Set(array(job.dependencies)), dependencies);
    equal(array(job.dependencies).length, dependencies.size);

    const roots = declarations.flatMap(({ name }, index) =>
      members.has(name) ? [index] : []
    );
    const pending = declarations.flatMap(({ nominals }, target) =>
      roots.some((root) => reachable[root][target]) ? nominals : []
    );
    const required = new Set<string>();
    while (pending.length) {
      const identity = pending.pop()!;
      const key = identityKey(identity);
      if (required.has(key)) continue;
      required.add(key);
      pending.push(...nominalById.get(key)?.references ?? []);
    }
    equal(new Set(array(job.type_dependencies).map(identityKey)), required);
    equal(array(job.type_dependencies).length, required.size);
  }
  return jobs;
}

Deno.test("job summaries agree with graph reachability across nominal cycles and effect coupling", () => {
  let seed = 719;
  const random = () => {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    return seed >>> 8;
  };
  for (let trial = 0; trial < 128; trial++) {
    const declarationCount = 1 + random() % 8;
    const typeCount = random() % 8;
    const identities = Array.from({ length: typeCount + 2 }, (_, index) => ({
      $: "TypeId" as const,
      module_name: "oracle",
      declaration: `Type${index}`,
    }));
    const names = Array.from(
      { length: declarationCount },
      (_, index) => `declaration_${index}`,
    );
    const references = <T>(possible: readonly T[]) => {
      const selected = possible.filter(() => random() % 4 === 0);
      return selected.length && trial % 3 === 0
        ? [...selected, selected[0]]
        : selected;
    };
    const declarations = names.map((name) => ({
      name,
      references: references([...names, "unknown_definition"]),
      effectful: random() % 5 === 0,
      nominals: references(identities),
    }));
    const nominals = identities.slice(0, typeCount).map((identity) => ({
      identity,
      references: references(identities),
    }));
    try {
      plannerAgreesWithReachability(declarations, nominals);
    } catch (cause) {
      throw new Error(`planner graph ${trial}`, { cause });
    }
  }
});

Deno.test("nominal indexes distinguish separators, empty modules and Unicode identities", () => {
  const identities: TypeId[] = [
    { $: "TypeId", module_name: "a::b", declaration: "c" },
    { $: "TypeId", module_name: "a", declaration: "b::c" },
    { $: "TypeId", module_name: "", declaration: "a::b::c" },
    { $: "TypeId", module_name: "雪🙂", declaration: "Type" },
    { $: "TypeId", module_name: "雪", declaration: "🙂Type" },
  ];
  const declarations = identities.map((identity, index) => ({
    name: `read_${index}`,
    references: ["unknown_definition"],
    effectful: false,
    nominals: [identity],
  }));
  const nominals = identities.map((identity, index) => ({
    identity,
    references: index % 2 === 0
      ? [identities[(index + 1) % identities.length]]
      : [],
  }));
  const jobs = plannerAgreesWithReachability(declarations, nominals);
  equal(jobs.length, declarations.length);
  equal(plannedSummaries([], nominals), []);
});

Deno.test("shared recursive nominal closures stay exact across pure and coupled jobs", () => {
  const identities: TypeId[] = Array.from({ length: 6 }, (_, index) => ({
    $: "TypeId",
    module_name: "recursive",
    declaration: `Type${index}`,
  }));
  const nominals = identities.map((identity, index) => ({
    identity,
    references: index < 3 ? [identities[(index + 1) % 3], identities[3]] : [],
  }));
  const declarations: DeclarationSummary[] = [
    {
      name: "pure",
      references: [],
      effectful: false,
      nominals: [identities[0]],
    },
    { name: "store", references: [], effectful: true, nominals: [] },
    {
      name: "writer_one",
      references: ["store", "pure"],
      effectful: false,
      nominals: [identities[4]],
    },
    {
      name: "writer_two",
      references: ["store"],
      effectful: false,
      nominals: [identities[5]],
    },
    {
      name: "pure_user",
      references: ["pure"],
      effectful: false,
      nominals: [],
    },
  ];
  const jobs = plannerAgreesWithReachability(declarations, nominals);
  equal(jobs.length, 3);
  equal(
    new Set(
      array(
        jobs.find((job) => array(job.members).includes("pure_user"))!
          .type_dependencies,
      ).map(identityKey),
    ),
    new Set(identities.slice(0, 4).map(identityKey)),
  );
  equal(
    new Set(array(
      jobs.find((job) => array(job.members).includes("store"))!
        .members,
    )),
    new Set(["store", "writer_one", "writer_two"]),
  );
});

Deno.test("grouped checking includes mutually recursive payload catalogs", () => {
  const identities: TypeId[] = ["Left", "Right"].map((declaration) => ({
    $: "TypeId",
    module_name: "recursive",
    declaration,
  }));
  const recursiveTypes: DataType[] = identities.map((identity, index) => ({
    identity,
    parameters: 0n,
    constructors: [{
      name: identity.declaration,
      payload: {
        $: "AppliedTy",
        identity: identities[1 - index],
        arguments: [],
      },
    }],
  }));
  const result = agrees(module([
    fn("ignore_left", unit, {
      parameter_type: {
        $: "AppliedTy",
        identity: identities[0],
        arguments: [],
      },
    }),
    fn("ignore_right", unit, {
      parameter_type: {
        $: "AppliedTy",
        identity: identities[1],
        arguments: [],
      },
    }),
  ], { data_types: recursiveTypes }));
  equal(result.jobs.length, 2);
  for (const job of result.jobs) {
    equal(
      new Set(array(job.type_dependencies).map(identityKey)),
      new Set(identities.map(identityKey)),
    );
  }
});
