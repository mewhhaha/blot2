import { toBendCst } from "./bend_abi.ts";
import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { bendArray, type BendList, bendList } from "./bend_list.ts";
import { createSourceCompiler } from "./source.ts";
import { createSourceFrontend } from "./source_frontend.ts";
import { type Cst, SourceError } from "./syntax.ts";

type Node = { readonly $: string; readonly [key: string]: unknown };
type Result<T> = { readonly $: "Done"; readonly value: T } | {
  readonly $: "Fail";
  readonly error: { readonly code: string };
};

const core = compiled as unknown as {
  "infer.instance_qualified"(
    variables: BendList<bigint>,
    ty: Node,
    predicates: BendList<Node>,
    next: bigint,
  ): Result<
    {
      readonly inferred_type: Node;
      readonly predicates: BendList<Node>;
      readonly next: bigint;
    }
  >;
  "constraints.free"(predicate: Node): Result<BendList<bigint>>;
  "constraints.free_list"(predicates: BendList<Node>): Result<BendList<bigint>>;
  "constraints.canonical_predicates"(
    predicates: BendList<Node>,
    seen: BendList<Node>,
  ): BendList<Node>;
  "constraints.remove_one"(
    predicates: BendList<Node>,
    wanted: Node,
  ): BendList<Node>;
  "constraints.shape_type"(predicate: Node): Node;
  "constraints.unplanned"(
    plans: BendList<Node>,
    predicates: BendList<Node>,
  ): BendList<Node>;
  "constraints.instantiate_parameters"(
    arguments_: BendList<Node>,
    predicates: BendList<Node>,
    index: bigint,
  ): Result<BendList<Node>>;
  "constraints.relocate_free"(
    predicates: BendList<Node>,
    suffix: string,
  ): Result<BendList<Node>>;
  "types.empty"(): Node;
  "types.difference"(
    variables: BendList<bigint>,
    excluded: BendList<bigint>,
  ): BendList<bigint>;
  "infer.pattern_requirements_closed"(
    predicates: BendList<Node>,
    state: Node,
    subject: string,
  ): Result<Node>;
  "infer.expr"(
    expression: Node,
    context: Node,
    state: Node,
  ): Result<{ readonly inference: Node }>;
  "groups.usage"(
    fuel: bigint,
    work: Node,
    types: Node,
  ): Result<{ readonly nominals: BendList<Node> }>;
  "groups.import_interfaces"(
    interfaces: BendList<Node>,
    operations: BendList<Node>,
    types: BendList<Node>,
    start: bigint,
  ): Result<Node>;
  "lower.source_module"(root: Cst, prelude: Cst, fuel: bigint): Result<Node>;
  "groups.check_group"(
    module: Node,
    dependencies: BendList<Node>,
  ): Result<
    { readonly interfaces: BendList<Node>; readonly uses: BendList<Node> }
  >;
};

function unwrap<T>(result: Result<T>): T {
  if (result.$ === "Fail") throw new Error(result.error.code);
  return result.value;
}

const nominal = {
  $: "model.TypeId",
  module_name: "example",
  declaration: "Tick",
};
const variable = (index: bigint) => ({ $: "model.VariableTy", index });
const rowVariable = (index: bigint) => ({ $: "model.RowVariable", index });
const row = (tail: Node) => ({
  $: "model.EffectRow",
  operations: bendList([nominal, nominal]),
  tail,
});

Deno.test("single-part predicate shapes remain valid annotation types", () => {
  equal(
    core["constraints.shape_type"]({
      $: "model.TypeRepPredicate",
      represented: { $: "model.U32Ty" },
    }),
    { $: "model.U32Ty" },
  );
  const reflected = core["constraints.shape_type"]({
    $: "model.EffectRepPredicate",
    row: {
      $: "model.EffectRow",
      operations: bendList([]),
      tail: { $: "model.ClosedRow" },
    },
  });
  equal(reflected.$, "model.FunctionTy");
  const operation = core["constraints.shape_type"]({
    $: "model.OperationPredicate",
    template: nominal,
    arguments: bendList([]),
    function_type: {
      $: "model.FunctionTy",
      parameter: { $: "model.U32Ty" },
      result: { $: "model.U32Ty" },
      effects: {
        $: "model.EffectRow",
        operations: bendList([]),
        tail: { $: "model.ClosedRow" },
      },
    },
  });
  equal(operation.$, "model.FunctionTy");
});

Deno.test("effect reflection records a qualified scheme without demanding callable evidence", () => {
  const emptyRow = {
    $: "model.EffectRow",
    operations: bendList([]),
    tail: { $: "model.ClosedRow" },
  };
  const binding = {
    $: "infer.Binding",
    name: "twice",
    inferred_type: {
      $: "model.FunctionTy",
      parameter: variable(0n),
      result: variable(0n),
      effects: emptyRow,
    },
    variables: bendList([0n]),
    predicates: bendList([{
      $: "model.AssociatedPredicate",
      member: "add",
      templates: bendList([]),
      left: variable(0n),
      right: variable(0n),
      result: variable(0n),
      invocation: emptyRow,
    }]),
  };
  const context = {
    $: "infer.Context",
    globals: bendList([binding]),
    locals: bendList([]),
    labels: bendList([]),
    data_types: bendList([]),
    operations: bendList([]),
    subject: "offset:20",
    function_names: bendList(["twice"]),
    ambient: emptyRow,
  };
  const state = {
    $: "infer.State",
    substitutions: core["types.empty"](),
    next: 1n,
    annotations: { $: "MTip" },
  };
  const typing = unwrap(core["infer.expr"](
    { $: "model.FunctionEffectsExpr", callee: "twice" },
    context,
    state,
  ));
  const inference = typing.inference as Node & {
    predicates: BendList<Node>;
    reflections: BendList<Node>;
    uses: BendList<Node>;
  };
  equal(bendArray(inference.predicates), []);
  equal(bendArray(inference.uses), []);
  const [reflection] = bendArray(inference.reflections) as Array<
    Node & { predicates: BendList<Node> }
  >;
  equal(bendArray(reflection.predicates).length, 1);
});

Deno.test("qualified instantiation shares type and row renaming without losing duplicate effects", () => {
  const ty = {
    $: "model.FunctionTy",
    parameter: variable(7n),
    result: variable(7n),
    effects: row(rowVariable(8n)),
  };
  const predicate = {
    $: "model.AssociatedPredicate",
    member: "combine",
    templates: bendList([]),
    left: variable(7n),
    right: variable(7n),
    result: variable(7n),
    invocation: row(rowVariable(8n)),
  };

  const free = bendArray(unwrap(core["constraints.free"](predicate))).map(
    Number,
  ).sort();
  equal(free, [7, 8]);
  const instance = unwrap(
    core["infer.instance_qualified"](
      bendList([7n, 8n]),
      ty,
      bendList([predicate]),
      20n,
    ),
  );
  equal(instance.next, 22n);
  const arrow = instance.inferred_type as Node & {
    parameter: Node;
    result: Node;
    effects: { tail: Node; operations: BendList<Node> };
  };
  const [need] = bendArray(instance.predicates) as Array<
    Node & {
      left: Node;
      right: Node;
      result: Node;
      invocation: { tail: Node; operations: BendList<Node> };
    }
  >;
  equal(arrow.parameter, variable(20n));
  equal(arrow.result, variable(20n));
  equal(arrow.effects.tail, rowVariable(21n));
  equal(need.left, variable(20n));
  equal(need.right, variable(20n));
  equal(need.result, variable(20n));
  equal(need.invocation.tail, rowVariable(21n));
  equal(bendArray(need.invocation.operations), [nominal, nominal]);
});

Deno.test("canonical slots preserve separate occurrence ownership", () => {
  const predicate = { $: "model.TypeRepPredicate", represented: variable(4n) };
  equal(
    bendArray(
      core["constraints.canonical_predicates"](
        bendList([predicate, predicate]),
        bendList([]),
      ),
    ).length,
    1,
  );
  const plan = {
    $: "constraints.UsePlan",
    site: 3n,
    subject: "offset:18",
    instantiated_type: variable(4n),
    predicates: bendList([predicate]),
  };
  const remaining = core["constraints.unplanned"](
    bendList([plan]),
    bendList([predicate, predicate]),
  );
  equal(bendArray(remaining), [predicate]);
});

Deno.test("predicate ownership removes one structural occurrence at a time", () => {
  const a = { $: "model.TypeRepPredicate", represented: { $: "model.U32Ty" } };
  const equivalentA = {
    $: "model.TypeRepPredicate",
    represented: { $: "model.U32Ty" },
  };
  const b = { $: "model.TypeRepPredicate", represented: { $: "model.F32Ty" } };
  const c = { $: "model.TypeRepPredicate", represented: { $: "model.BoolTy" } };
  const occurrences = bendList([b, a, c, equivalentA, b]);

  equal(
    bendArray(
      core["constraints.canonical_predicates"](occurrences, bendList([])),
    ),
    [b, a, c],
  );
  equal(
    bendArray(core["constraints.remove_one"](occurrences, equivalentA)),
    [b, c, equivalentA, b],
  );

  const plan = {
    $: "constraints.UsePlan",
    site: 9n,
    subject: "offset:9",
    instantiated_type: { $: "model.UnitTy" },
    predicates: bendList([equivalentA, b, c]),
  };
  equal(
    bendArray(core["constraints.unplanned"](bendList([plan]), occurrences)),
    [equivalentA, b],
  );
});

Deno.test("fresh interface arguments instantiate type and row parameters together", () => {
  const param = (index: bigint) => ({ $: "model.ParameterTy", index });
  const rowParam = (index: bigint) => ({ $: "model.RowParameter", index });
  const original = {
    $: "model.AssociatedPredicate",
    member: "combine",
    templates: bendList([nominal]),
    left: {
      $: "model.FunctionTy",
      parameter: param(7n),
      result: param(100n),
      effects: row(rowParam(8n)),
    },
    right: param(7n),
    result: param(9n),
    invocation: row(rowParam(8n)),
  };
  const result = bendArray(unwrap(core["constraints.instantiate_parameters"](
    bendList([variable(40n), variable(41n), variable(42n)]),
    bendList([original, original]),
    7n,
  ))) as Array<
    Node & {
      left: Node & {
        parameter: Node;
        result: Node;
        effects: { tail: Node; operations: BendList<Node> };
      };
      right: Node;
      result: Node;
      invocation: { tail: Node; operations: BendList<Node> };
    }
  >;
  equal(result.length, 2);
  for (const need of result) {
    equal(need.left.parameter, variable(40n));
    equal(need.left.result, param(100n));
    equal(need.left.effects.tail, rowVariable(41n));
    equal(need.right, variable(40n));
    equal(need.result, variable(42n));
    equal(need.invocation.tail, rowVariable(41n));
    equal(bendArray(need.invocation.operations), [nominal, nominal]);
  }
  equal(
    bendArray(unwrap(core["constraints.instantiate_parameters"](
      bendList([]),
      bendList([original]),
      7n,
    ))),
    [original],
  );
});

Deno.test("nonfresh interface arguments keep left-to-right parameter substitution", () => {
  const original = {
    $: "model.TypeRepPredicate",
    represented: { $: "model.ParameterTy", index: 0n },
  };
  const [result] = bendArray(unwrap(core["constraints.instantiate_parameters"](
    bendList([{ $: "model.ParameterTy", index: 1n }, { $: "model.U32Ty" }]),
    bendList([original]),
    0n,
  ))) as Array<Node & { represented: Node }>;
  equal(result.represented, { $: "model.U32Ty" });
});

Deno.test("predicate free variables retain the original right-fold order", () => {
  const predicates = bendList([3n, 2n, 3n, 1n].map((index) => ({
    $: "model.TypeRepPredicate",
    represented: variable(index),
  })));
  equal(bendArray(unwrap(core["constraints.free_list"](predicates))), [
    2n,
    3n,
    1n,
  ]);
  equal(
    bendArray(core["types.difference"](
      bendList([3n, 2n, 3n, 1n, 2n]),
      bendList([2n]),
    )),
    [3n, 3n, 1n],
  );
});

Deno.test("imported qualified interfaces validate operation templates and arity", () => {
  const templateId = {
    $: "model.TypeId",
    module_name: "example",
    declaration: "State.get",
  };
  const closed = {
    $: "model.EffectRow",
    operations: bendList([]),
    tail: { $: "model.ClosedRow" },
  };
  const interfaceShape = {
    $: "groups.Interface",
    name: "get",
    kind: { $: "groups.FunctionInterface" },
    template: {
      $: "model.FunctionTy",
      parameter: { $: "model.U32Ty" },
      result: { $: "model.U32Ty" },
      effects: closed,
    },
    parameters: 0n,
    effects: bendList([]),
    predicates: bendList([{
      $: "model.OperationPredicate",
      template: templateId,
      arguments: bendList([{ $: "model.U32Ty" }]),
      function_type: {
        $: "model.FunctionTy",
        parameter: { $: "model.U32Ty" },
        result: { $: "model.U32Ty" },
        effects: closed,
      },
    }]),
  };
  const missing = core["groups.import_interfaces"](
    bendList([interfaceShape]),
    bendList([]),
    bendList([]),
    0n,
  );
  equal(missing.$, "Fail");
  if (missing.$ === "Fail") equal(missing.error.code, "unknown_effect");

  const declared = {
    $: "model.OperationTemplate",
    identity: templateId,
    parameters: 2n,
    parameter: { $: "model.ParameterTy", index: 0n },
    result: { $: "model.ParameterTy", index: 1n },
  };
  const wrongArity = core["groups.import_interfaces"](
    bendList([interfaceShape]),
    bendList([declared]),
    bendList([]),
    0n,
  );
  equal(wrongArity.$, "Fail");
  if (wrongArity.$ === "Fail") {
    equal(wrongArity.error.code, "invalid_interface");
  }

  const staleAssociated = {
    ...interfaceShape,
    predicates: bendList([{
      $: "model.AssociatedPredicate",
      member: "read",
      templates: bendList([templateId]),
      left: { $: "model.U32Ty" },
      right: { $: "model.U32Ty" },
      result: { $: "model.U32Ty" },
      invocation: closed,
    }]),
  };
  const stale = core["groups.import_interfaces"](
    bendList([staleAssociated]),
    bendList([]),
    bendList([]),
    0n,
  );
  equal(stale.$, "Fail");
  if (stale.$ === "Fail") equal(stale.error.code, "unknown_effect");

  const unresolvedRow = {
    ...interfaceShape,
    predicates: bendList([{
      $: "model.EffectRepPredicate",
      row: {
        $: "model.EffectRow",
        operations: bendList([]),
        tail: { $: "model.FreeRow", scope: "binding", name: "e" },
      },
    }]),
  };
  const unresolved = core["groups.import_interfaces"](
    bendList([unresolvedRow]),
    bendList([]),
    bendList([]),
    0n,
  );
  equal(unresolved.$, "Fail");
  if (unresolved.$ === "Fail") {
    equal(unresolved.error.code, "unresolved_annotation");
  }
});

Deno.test("imported scheme rejects one parameter used as both a type and row", () => {
  const imported = {
    $: "groups.Interface",
    name: "mixed",
    kind: { $: "groups.FunctionInterface" },
    template: {
      $: "model.FunctionTy",
      parameter: { $: "model.ParameterTy", index: 0n },
      result: { $: "model.ParameterTy", index: 0n },
      effects: {
        $: "model.EffectRow",
        operations: bendList([]),
        tail: { $: "model.ClosedRow" },
      },
    },
    parameters: 1n,
    effects: bendList([]),
    predicates: bendList([{
      $: "model.EffectRepPredicate",
      row: {
        $: "model.EffectRow",
        operations: bendList([]),
        tail: { $: "model.RowParameter", index: 0n },
      },
    }]),
  };
  const result = core["groups.import_interfaces"](
    bendList([imported]),
    bendList([]),
    bendList([]),
    0n,
  );
  equal(result.$, "Fail");
  if (result.$ === "Fail") equal(result.error.code, "kind_mismatch");
});

Deno.test("mutual SCC exports transitive predicates and fills peer creation plans", async () => {
  const frontend = await createSourceFrontend({ prelude: "none" });
  try {
    const prepared = frontend.prepare(`
const first: U32 -> U32 = fn value => do:
  let alias = second
  return alias value
const second: U32 -> U32 where { associated "add" U32 U32 a } = fn value => case #True of
  #True => value
  #False => first value
entry const answer = fn () => first 42
`);
    const module = unwrap(core["lower.source_module"](
      toBendCst(prepared.root),
      toBendCst(prepared.prelude),
      prepared.nodeCount,
    ));
    const group = unwrap(core["groups.check_group"](module, bendList([])));
    const interfaces = bendArray(group.interfaces) as (Node & {
      name: string;
      predicates: BendList<Node>;
    })[];
    const first = interfaces.find((value) => value.name === "first");
    ok(first);
    ok(
      bendArray(first.predicates).some((predicate) =>
        predicate.$ === "model.AssociatedPredicate" &&
        predicate.member === "add"
      ),
    );
    const uses = bendArray(group.uses) as (Node & {
      predicates: BendList<Node>;
    })[];
    ok(
      uses.some((plan) =>
        bendArray(plan.predicates).some((predicate) =>
          predicate.$ === "model.AssociatedPredicate" &&
          predicate.member === "add"
        )
      ),
    );
  } finally {
    frontend.dispose();
  }
});

Deno.test("pure group check enforces an empty local SCC clause and retains a complete one", async () => {
  const frontend = await createSourceFrontend({ prelude: "none" });
  try {
    const check = (clause: string) => {
      const prepared = frontend.prepare(`
const first: a -> a = fn value => do:
  let alias: a -> a where { ${clause} } = second
  return alias value
const second: a -> a = fn value => third value
const third: a -> a = fn value => case #True of
  #True => @type.call "add" value value
  #False => first value
entry const answer = fn () => first 21
`);
      const module = unwrap(core["lower.source_module"](
        toBendCst(prepared.root),
        toBendCst(prepared.prelude),
        prepared.nodeCount,
      ));
      return core["groups.check_group"](module, bendList([]));
    };
    const missing = check("");
    equal(missing.$, "Fail");
    if (missing.$ === "Fail") equal(missing.error.code, "missing_predicate");
    const accepted = check('associated "add" a a a');
    equal(accepted.$, "Done");
    if (accepted.$ === "Done") {
      const interfaces = bendArray(accepted.value.interfaces) as (Node & {
        name: string;
        predicates: BendList<Node>;
      })[];
      const first = interfaces.find((value) => value.name === "first");
      ok(first);
      ok(
        bendArray(first.predicates).some((predicate) =>
          predicate.$ === "model.AssociatedPredicate" &&
          predicate.member === "add"
        ),
      );
    }
  } finally {
    frontend.dispose();
  }
});

Deno.test("source row tails relocate and fail closed before freshening", () => {
  const predicate = {
    $: "model.EffectRepPredicate",
    row: {
      $: "model.EffectRow",
      operations: bendList([]),
      tail: { $: "model.FreeRow", scope: "binding", name: "e" },
    },
  };
  const unresolved = core["constraints.free"](predicate);
  equal(unresolved.$, "Fail");
  if (unresolved.$ === "Fail") {
    equal(unresolved.error.code, "unresolved_annotation");
  }
  const relocated = bendArray(
    unwrap(core["constraints.relocate_free"](bendList([predicate]), "$mono")),
  );
  const effect = relocated[0] as Node & {
    row: { tail: { scope: string; name: string } };
  };
  equal(effect.row.tail.scope, "binding$mono");
  equal(effect.row.tail.name, "e");
  ok(relocated.length === 1);
});

Deno.test("value patterns keep closed old-source requirements but reject open evidence", () => {
  const state = {
    $: "infer.State",
    substitutions: core["types.empty"](),
    next: 0n,
    annotations: { $: "MTip" },
  };
  const concrete = {
    $: "model.AssociatedPredicate",
    member: "add",
    templates: bendList([]),
    left: { $: "model.U32Ty" },
    right: { $: "model.U32Ty" },
    result: { $: "model.U32Ty" },
    invocation: {
      $: "model.EffectRow",
      operations: bendList([]),
      tail: { $: "model.ClosedRow" },
    },
  };
  equal(
    core["infer.pattern_requirements_closed"](
      bendList([concrete]),
      state,
      "offset:10",
    ).$,
    "Done",
  );
  const open = { $: "model.TypeRepPredicate", represented: variable(4n) };
  const rejected = core["infer.pattern_requirements_closed"](
    bendList([open]),
    state,
    "offset:10",
  );
  equal(rejected.$, "Fail");
  if (rejected.$ === "Fail") equal(rejected.error.code, "qualified_pattern");
});

Deno.test("unused explicit requirements keep their type, template, and row dependencies", () => {
  const box = { $: "model.TypeId", module_name: "example", declaration: "Box" };
  const family = {
    $: "model.TypeId",
    module_name: "example",
    declaration: "State",
  };
  const operation = {
    $: "model.TypeId",
    module_name: "example",
    declaration: "Read",
  };
  const wrapped = {
    $: "model.QualifiedExpr",
    offset: 10n,
    annotation: { $: "model.U32Ty" },
    predicates: bendList([{
      $: "model.AssociatedPredicate",
      member: "read",
      templates: bendList([family]),
      left: { $: "model.AppliedTy", identity: box, arguments: bendList([]) },
      right: { $: "model.UnitTy" },
      result: { $: "model.U32Ty" },
      invocation: {
        $: "model.EffectRow",
        operations: bendList([operation]),
        tail: { $: "model.ClosedRow" },
      },
    }]),
    value: { $: "model.U32Expr", value: 1n },
  };
  const usage = unwrap(
    core["groups.usage"](65536n, {
      $: "groups.ExpressionUsage",
      value: wrapped,
    }, {
      $: "MTip",
    }),
  );
  const names = bendArray(usage.nominals).map((value) =>
    String(value.declaration)
  ).sort();
  equal(names, ["Box", "Read", "State"]);
});

Deno.test("a computed qualified let keeps one monomorphic evidence instance", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(`
const twice: a -> a where { associated "add" a a a } = fn value => value + value
entry const run = fn () => do:
  let selected = case #True of
    #True => twice
    #False => twice
  return selected 21
`);
    const exports = new WebAssembly.Instance(
      new WebAssembly.Module(artifact.bytes),
    ).exports;
    equal((exports.run as CallableFunction)(), 42);
  } finally {
    compiler.dispose();
  }
});

Deno.test("a computed qualified let retains the baseline mixed-type mismatch", async () => {
  const compiler = await createSourceCompiler();
  try {
    const source = `
const twice: a -> a where { associated "add" a a a } = fn value => value + value
entry const run = fn () => do:
  let selected = case #True of
    #True => twice
    #False => twice
  return @f32.add (@u32.to_f32 (selected 21)) (selected 1.5)
`;
    throws(() => compiler.compile(source), (error) => {
      ok(error instanceof SourceError, String(error));
      equal(error.code, "type_mismatch");
      return true;
    });
  } finally {
    compiler.dispose();
  }
});

Deno.test("an effectful condition is evaluated once before a computed qualified let", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(`
type Cell is effect = {
  get: Unit -> U32
  set: U32 -> Unit
}
type Tick is effect = Unit -> Bool
const twice: a -> a where { associated "add" a a a } = fn value => value + value
entry const run = fn () => do:
  let (count, result) = do (@effect.state Cell.get Cell.set 0):
    let tick = fn () => do:
      use current <- Cell.get ()
      use Cell.set (@u32.add current 1)
      return #True
    return do (@effect.provider Tick tick):
      use flag <- Tick ()
      let selected = case flag of
        #True => twice
        #False => twice
      return selected 21
  return @u32.add count result
`);
    const exports = new WebAssembly.Instance(
      new WebAssembly.Module(artifact.bytes),
    ).exports;
    equal((exports.run as CallableFunction)(), 43);
  } finally {
    compiler.dispose();
  }
});

Deno.test("a qualified pure annotation still rejects effects in its body", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    throws(() =>
      compiler.compile(`
type Read a is effect = Unit -> a
const illegal: Unit -> U32 where {} = fn () => Read ()
entry const run = fn () => illegal ()
`), (error) => {
      ok(error instanceof SourceError, String(error));
      equal(error.code, "effect_mismatch");
      return true;
    });
  } finally {
    compiler.dispose();
  }
});
