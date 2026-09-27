import { toBendCst } from "./bend_abi.ts";
import { deepStrictEqual as equal, ok } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { bendArray, type BendList, bendList } from "./bend_list.ts";
import { createSourceFrontend } from "./source_frontend.ts";

type Node = { readonly $: string; readonly [field: string]: unknown };
type Result<T> = { readonly $: "Done"; readonly value: T } | {
  readonly $: "Fail";
  readonly error: Node;
};
type Maybe<T> = { readonly $: "Some"; readonly value: T } | {
  readonly $: "None";
};
const api = compiled as unknown as Record<
  string,
  (...args: unknown[]) => unknown
>;
const nil = bendList<Node>([]);
const none: Node = { $: "None" };
const some = (value: Node): Node => ({ $: "Some", value });
const local = (name: string): Node => ({ $: "model.LocalExpr", name });
const at = (offset: bigint, value: Node): Node => ({
  $: "model.SourceExpr",
  offset,
  annotation: none,
  value,
});
const localAt = (offset: bigint, name: string): Node =>
  at(offset, {
    $: "model.InstantiationExpr",
    site: offset * 16n,
    value: local(name),
  });
const id = (declaration: string): Node => ({
  $: "model.TypeId",
  module_name: "std/prelude",
  declaration,
});
const typeCatalog = bendList<Node>([{
  $: "model.DataType",
  identity: id("Type"),
  parameters: 1n,
  constructors: bendList<Node>([{
    $: "model.Constructor",
    name: "$prelude.Type",
    payload: some({ $: "model.ParameterTy", index: 0n }),
    fields: nil,
  }]),
}]);

// The import-free lowered shape of std/prelude's Type.eq. Source offsets and
// pattern names are real syntax evidence used by the exact clone guard.
function sourceFunction(): Node {
  const pattern = (name: string): Node => ({
    $: "model.ConstructorPattern",
    constructor: "$prelude.Type",
    payload: some({ $: "model.BindingPattern", name }),
  });
  return {
    $: "model.Function",
    name: "$prelude.Type.eq",
    exported: false,
    parameter: "left$379",
    parameter_type: none,
    result_type: none,
    body: at(381n, {
      $: "model.LambdaExpr",
      identity: 381n,
      parameter: "right$382",
      parameter_type: none,
      result_type: none,
      body: at(384n, {
        $: "model.MatchExpr",
        values: bendList([
          localAt(385n, "left$379"),
          localAt(387n, "right$382"),
        ]),
        arms: bendList<Node>([{
          $: "model.MatchArm",
          patterns: bendList([pattern("a$390"), pattern("b$393")]),
          body: at(395n, {
            $: "model.AssociatedExpr",
            identity: 395n,
            dispatch: { $: "model.BinaryDispatch" },
            member: "@type.same",
            templates: nil,
            left: localAt(396n, "a$390"),
            right: localAt(397n, "b$393"),
          }),
        }]),
      }),
    }),
  };
}

const captureClosed = api["staging_scheme.capture_closed"] as (
  closed: boolean,
  functions: BendList<Node>,
  operations: BendList<Node>,
  types: BendList<Node>,
) => BendList<Node>;
const expand = api["monomorph.expand"] as (
  fuel: bigint,
  work: Node,
  configuration: Node,
  stack: BendList<Node>,
  base: bigint,
  counter: bigint,
) => Result<Node>;
const candidate = api["staging_scheme.candidate"] as (
  clone: Node,
  schemes: BendList<Node>,
) => Maybe<Node>;
const exactClone = api["monomorph.exact_staged_clone"] as (
  candidate: Node,
  clone: Node,
  stride: bigint,
) => boolean;
const replay = api["staging_scheme.replay"] as (
  candidate: Node,
  clone: Node,
  stride: bigint,
  environment: Node,
  types: BendList<Node>,
  exact: boolean,
) => Maybe<Node>;
const stagedCandidate = api["monomorph.staged_candidate"] as (
  candidate: Maybe<Node>,
  clone: Node,
  stride: bigint,
  environment: Node,
  types: BendList<Node>,
) => Maybe<Node>;
const stagedOrInfer = api["monomorph.staged_or_infer"] as (
  staged: Maybe<Node>,
  declaration: Node,
  environment: Node,
  operations: BendList<Node>,
  types: BendList<Node>,
  functions: BendList<string>,
  index: Maybe<Node>,
) => Result<Node>;
const declarations = api["globals.function_declarations"] as (
  functions: BendList<Node>,
) => BendList<Node>;
const initialBindings = api["globals.initial_bindings"] as (
  declarations: BendList<Node>,
  start: bigint,
) => BendList<Node>;
const initialNext = api["globals.initial_next"] as (
  declarations: BendList<Node>,
  start: bigint,
) => bigint;
const emptySubstitutions = api["types.empty"] as () => Node;
const appendSubstitution = api["types.append_substitution"] as (
  substitutions: Node,
  substitution: Node,
) => Node;
const dataTypesClosed = api["parallel_infer.data_types_closed"] as (
  types: BendList<Node>,
) => boolean;
const resolveInference = api["staging_residual.resolve"] as (
  inference: Node,
  substitutions: Node,
) => Result<Node>;
const inferDeclaration = api["globals.infer_declaration_prepared"] as (
  declaration: Node,
  environment: Node,
  operations: BendList<Node>,
  types: BendList<Node>,
  functions: BendList<string>,
  index: Maybe<Node>,
) => Result<Node>;

function environment(clone: Node, start = 0n, constrained?: Node): Node {
  const declaration = declarations(bendList([clone]));
  return {
    $: "globals.Environment",
    bindings: initialBindings(declaration, start),
    definitions: nil,
    state: {
      $: "infer.State",
      substitutions: constrained
        ? appendSubstitution(emptySubstitutions(), {
          $: "types.Substitution",
          variable: start,
          replacement: constrained,
        })
        : emptySubstitutions(),
      next: initialNext(declaration, start),
      annotations: { $: "MTip" },
    },
  };
}

function resolvedDefinition(result: Maybe<Node> | Result<Node>): {
  next: bigint;
  inference: Node;
} {
  ok(result.$ === "Some" || result.$ === "Done");
  if (result.$ !== "Some" && result.$ !== "Done") {
    throw new Error("inference did not succeed");
  }
  const env = result.value;
  const definitions = bendArray(env.definitions as BendList<Node>);
  equal(definitions.length, 1);
  const state = env.state as Node;
  const resolved = resolveInference(
    definitions[0].inference as Node,
    state.substitutions as Node,
  );
  equal(resolved.$, "Done");
  if (resolved.$ !== "Done") throw new Error("inference resolution failed");
  return { next: state.next as bigint, inference: resolved.value };
}

function ordinaryInference(clone: Node, env: Node): Result<Node> {
  return ordinaryInferenceWith(clone, env, typeCatalog);
}

function ordinaryInferenceWith(
  clone: Node,
  env: Node,
  types: BendList<Node>,
): Result<Node> {
  const declaration = bendArray(declarations(bendList([clone])))[0];
  return inferDeclaration(
    declaration,
    env,
    nil,
    types,
    bendList([clone.name as string]),
    { $: "None" },
  );
}

Deno.test("staging captures actual lowered std/prelude Type.eq use sites", async () => {
  const frontend = await createSourceFrontend();
  try {
    const prepared = frontend.prepare("entry const sentinel = fn () => 0");
    const lowered = api["lower.source_module"](
      toBendCst(prepared.root),
      toBendCst(prepared.prelude),
      prepared.nodeCount,
    ) as Result<Node>;
    equal(lowered.$, "Done");
    if (lowered.$ !== "Done") throw new Error("prelude lowering failed");
    const module = lowered.value;
    const source = bendArray(module.functions as BendList<Node>).find(
      (functionValue) => functionValue.name === "$prelude.Type.eq",
    );
    ok(source, "lowered prelude Type.eq is present");
    const types = module.data_types as BendList<Node>;
    const schemes = captureClosed(true, bendList([source]), nil, types);
    equal(bendArray(schemes).length, 1);
    const inference = bendArray(schemes)[0].inference as Node;
    const uses = bendArray(inference.uses as BendList<Node>);
    equal(uses.length, 4);
    for (const use of uses) {
      equal((use.site as bigint) % 16n, 0n);
      equal(bendArray(use.predicates as BendList<Node>).length, 0);
    }
    const sourceExpressions = api["monomorph.module_expressions"](
      module.functions,
      module.constants,
    );
    const measured = api["monomorph.identity_limit"](
      1048576n,
      sourceExpressions,
      0n,
    ) as Result<bigint>;
    equal(measured.$, "Done");
    if (measured.$ !== "Done") throw new Error("identity scan failed");
    const stride = measured.value;
    const configuration: Node = {
      $: "monomorph.Configuration",
      functions: bendList([source]),
      templates: bendList([source.name as string]),
      entry: "",
      locals: nil,
      affected: nil,
      stride,
      constants: nil,
      family_templates: nil,
      step: 1n,
      schema: nil,
    };
    const expanded = expand(
      65536n,
      { $: "monomorph.Clone", function: source },
      configuration,
      nil,
      0n,
      1n,
    );
    equal(expanded.$, "Done");
    if (expanded.$ !== "Done") throw new Error("Type.eq expansion failed");
    const clones = bendArray(expanded.value.functions as BendList<Node>);
    equal(clones.length, 1);
    const clone = clones[0];
    const found = candidate(clone, schemes);
    equal(found.$, "Some");
    if (found.$ !== "Some") throw new Error("Type.eq clone was not recognized");
    ok(exactClone(found.value, clone, stride));
    const staged = stagedCandidate(
      found,
      clone,
      stride,
      environment(clone),
      types,
    );
    equal(staged.$, "Some");
    equal(
      resolvedDefinition(staged),
      resolvedDefinition(
        ordinaryInferenceWith(clone, environment(clone), types),
      ),
    );
  } finally {
    frontend.dispose();
  }
});

function fixture() {
  const source = sourceFunction();
  const schemes = captureClosed(true, bendList([source]), nil, typeCatalog);
  equal(bendArray(schemes).length, 1, "independent Type.eq body must capture");
  const inference = bendArray(schemes)[0].inference as Node;
  const predicates = bendArray(inference.predicates as BendList<Node>);
  equal(predicates.length, 1);
  equal(predicates[0].member, "@type.same");
  const guarded = api["staging_scheme.type_equality_inference"];
  const uses = bendArray(inference.uses as BendList<Node>);
  equal(uses.length, 4);
  equal(guarded(source, { ...inference, uses: nil }), false);
  equal(
    guarded(source, {
      ...inference,
      uses: bendList([
        { ...uses[0], site: (uses[0].site as bigint) + 1n },
        ...uses.slice(1),
      ]),
    }),
    false,
  );
  equal(
    guarded(source, {
      ...inference,
      uses: bendList([...uses, uses[0]]),
    }),
    false,
  );
  equal(
    guarded(source, {
      ...inference,
      uses: bendList([
        { ...uses[0], predicates: bendList([predicates[0]]) },
        ...uses.slice(1),
      ]),
    }),
    false,
  );
  equal(guarded(source, { ...inference, predicates: nil }), false);
  equal(
    guarded(source, {
      ...inference,
      predicates: bendList([{ ...predicates[0], member: "add" }]),
    }),
    false,
  );
  equal(
    guarded(source, {
      ...inference,
      predicates: bendList([{ ...predicates[0], left: { $: "model.U32Ty" } }]),
    }),
    false,
  );
  equal(
    guarded(source, {
      ...inference,
      predicates: bendList([predicates[0], predicates[0]]),
    }),
    false,
  );
  const stride = 500n;
  const configuration: Node = {
    $: "monomorph.Configuration",
    functions: bendList([source]),
    templates: bendList([source.name as string]),
    entry: "",
    locals: nil,
    affected: nil,
    stride,
    constants: nil,
    family_templates: nil,
    step: 1n,
    schema: nil,
  };
  const expanded = expand(
    65536n,
    { $: "monomorph.Clone", function: source },
    configuration,
    nil,
    0n,
    1n,
  );
  equal(expanded.$, "Done");
  if (expanded.$ !== "Done") throw new Error("Type.eq expansion failed");
  const clones = bendArray(expanded.value.functions as BendList<Node>);
  equal(clones.length, 1);
  const clone = clones[0];
  const found = candidate(clone, schemes);
  equal(found.$, "Some");
  if (found.$ !== "Some") throw new Error("Type.eq clone was not recognized");
  ok(exactClone(found.value, clone, stride));
  return { source, schemes, stride, clone, candidate: found.value };
}

Deno.test("staging captures and replays the independently inferred Type.eq clone", () => {
  const { source, schemes, stride, clone, candidate: found } = fixture();
  equal(captureClosed(false, bendList([source]), nil, typeCatalog), nil);
  const result = stagedCandidate(
    { $: "Some", value: found },
    clone,
    stride,
    environment(clone),
    typeCatalog,
  );
  equal(result.$, "Some");
  const staged = resolvedDefinition(result);
  const ordinary = resolvedDefinition(
    ordinaryInference(clone, environment(clone)),
  );
  equal(staged, ordinary);
  const needs = bendArray(staged.inference.coverage as BendList<Node>);
  equal(needs.map((need) => need.$), [
    "infer.Coverage",
    "infer.AssociatedNeed",
  ]);
  equal(needs[0].subject, "offset:384");
  equal(needs[1].identity, 895n);
  equal(needs[1].subject, "offset:395");
  equal(bendArray(schemes).length, 1);
});

Deno.test("one captured scheme replays independently under distinct constrained seeds", () => {
  const { stride, clone, candidate: found } = fixture();
  const witness = (type: Node): Node => ({
    $: "model.AppliedTy",
    identity: id("Type"),
    arguments: bendList([type]),
  });
  for (
    const [start, type] of [
      [1000n, { $: "model.U32Ty" }],
      [2000n, { $: "model.F32Ty" }],
      [1000n, { $: "model.U32Ty" }],
    ] as const
  ) {
    const env = environment(clone, start, witness(type));
    const staged = stagedCandidate(
      { $: "Some", value: found },
      clone,
      stride,
      env,
      typeCatalog,
    );
    equal(staged.$, "Some");
    equal(
      resolvedDefinition(staged),
      resolvedDefinition(ordinaryInference(clone, env)),
    );
  }
});

Deno.test("staging rejects altered clones and preserves the original first diagnostic", () => {
  const { stride, clone, candidate: found } = fixture();
  const invalid: Node = {
    ...clone,
    body: at(381n, { $: "model.FunctionExpr", name: "missing" }),
  };
  ok(!exactClone(found, invalid, stride));
  const env = environment(invalid);
  const proposed = stagedCandidate(
    { $: "Some", value: found },
    invalid,
    stride,
    env,
    typeCatalog,
  );
  equal(proposed.$, "None");
  const declaration = bendArray(declarations(bendList([invalid])))[0];
  const names = bendList([invalid.name as string]);
  const original = inferDeclaration(declaration, env, nil, typeCatalog, names, {
    $: "None",
  });
  const fallback = stagedOrInfer(
    proposed,
    declaration,
    env,
    nil,
    typeCatalog,
    names,
    { $: "None" },
  );
  equal(fallback, original);
  equal(fallback.$, "Fail");
});

Deno.test("staging rejects changed and open nominal catalogs", () => {
  const { source, stride, clone, candidate: found } = fixture();
  const changed: BendList<Node> = bendList([{
    ...bendArray(typeCatalog)[0],
    constructors: bendList<Node>([{
      $: "model.Constructor",
      name: "$prelude.Type",
      payload: some({ $: "model.F32Ty" }),
      fields: nil,
    }]),
  }]);
  equal(
    replay(found, clone, stride, environment(clone), changed, true).$,
    "None",
  );
  const open: BendList<Node> = bendList([{
    ...bendArray(typeCatalog)[0],
    constructors: bendList<Node>([{
      $: "model.Constructor",
      name: "$prelude.Type",
      payload: some({ $: "model.VariableTy", index: 12n }),
      fields: nil,
    }]),
  }]);
  equal(dataTypesClosed(open), false);
  equal(
    captureClosed(dataTypesClosed(open), bendList([source]), nil, open),
    nil,
  );
});

Deno.test("staging falls back before allocating beyond Nat48", () => {
  const { stride, clone, candidate: found } = fixture();
  const nearLimit = (1n << 48n) - 4n;
  const env = environment(clone);
  const state = { ...(env.state as Node), next: nearLimit };
  equal(
    replay(found, clone, stride, { ...env, state }, typeCatalog, true).$,
    "None",
  );
});
