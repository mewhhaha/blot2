import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import {
  analyze,
  compile,
  CompilerError,
  type CoreModule,
  type Expr,
  type Pattern,
} from "./host.ts";
import {
  add,
  call,
  fn,
  integer,
  local,
  module,
  operation,
  u32Type,
} from "./fixtures.ts";

const lambda = (identity: bigint, parameter: string, body: Expr): Expr => ({
  $: "LambdaExpr",
  identity,
  parameter,
  parameter_type: null,
  result_type: null,
  body,
});
const apply = (callee: Expr, argument: Expr): Expr => ({
  $: "ApplyExpr",
  callee,
  argument,
});
const bind = (name: string, value: Expr, body: Expr): Expr => ({
  $: "LetExpr",
  name,
  value,
  body,
});
const block = (label: bigint, body: Expr): Expr => ({
  $: "BlockExpr",
  label,
  body,
});
const exit = (label: bigint, value: Expr): Expr => ({
  $: "ReturnExpr",
  label,
  value,
});
const constructor = (name: string, payload: Expr | null = null): Expr => ({
  $: "ConstructExpr",
  constructor: name,
  payload,
});
const constructorPattern = (
  name: string,
  payload: Pattern | null = null,
): Pattern => ({ $: "ConstructorPattern", constructor: name, payload });
const product = (...elements: Expr[]): Expr => ({ $: "ProductExpr", elements });
const project = (value: Expr, index: bigint): Expr => ({
  $: "ProjectExpr",
  value,
  index,
});

function constantModule(
  value: Expr,
  options: Partial<Omit<CoreModule, "constants">> = {},
): CoreModule {
  return module([], {
    ...options,
    constants: [{ name: "answer", exported: false, annotation: null, value }],
  });
}

function expectNumber(source: CoreModule, expected: number) {
  equal(analyze(source).constants[0].value, {
    $: "U32Value",
    value: expected,
  });
}

const maybe = {
  identity: { $: "TypeId", module_name: "test", declaration: "Maybe" },
  parameters: 1n,
  constructors: [
    { name: "Some", payload: { $: "ParameterTy", index: 0n } },
    { name: "Nothing", payload: null },
  ],
} as const;

Deno.test("const closures capture definition-time bindings across shadowing", () => {
  expectNumber(
    constantModule(bind(
      "outer",
      integer(40),
      bind(
        "add_outer",
        lambda(1n, "argument", add(local("outer"), local("argument"))),
        bind("outer", integer(100), apply(local("add_outer"), integer(2))),
      ),
    )),
    42,
  );
});

Deno.test("const function values can return closures without capturing their caller", () => {
  expectNumber(
    constantModule(
      bind(
        "value",
        integer(999),
        apply(
          apply({ $: "FunctionExpr", name: "make_adder" }, integer(40)),
          integer(2),
        ),
      ),
      {
        functions: [fn(
          "make_adder",
          lambda(2n, "argument", add(local("value"), local("argument"))),
          { parameter_type: u32Type, exported: false },
        )],
      },
    ),
    42,
  );
});

Deno.test("const constructor functions and nested matches share ordinary application", () => {
  const nested: Pattern = constructorPattern(
    "Some",
    constructorPattern("Some", { $: "BindingPattern", name: "value" }),
  );
  expectNumber(
    constantModule({
      $: "MatchExpr",
      values: [apply(
        { $: "ConstructorRefExpr", constructor: "Some" },
        constructor("Some", integer(42)),
      )],
      arms: [
        { patterns: [nested], body: local("value") },
        { patterns: [{ $: "WildcardPattern" }], body: integer(0) },
      ],
    }, { data_types: [maybe] }),
    42,
  );
  expectNumber(
    constantModule({
      $: "MatchExpr",
      values: [{ $: "ConstructorRefExpr", constructor: "Nothing" }],
      arms: [
        { patterns: [constructorPattern("Nothing")], body: integer(42) },
        {
          patterns: [constructorPattern("Some", { $: "WildcardPattern" })],
          body: integer(0),
        },
      ],
    }, { data_types: [maybe] }),
    42,
  );
});

Deno.test("const matching preserves arm order and does not evaluate unused bodies", () => {
  const source = constantModule({
    $: "MatchExpr",
    values: [integer(7)],
    arms: [
      { patterns: [{ $: "U32Pattern", value: 7 }], body: integer(42) },
      { patterns: [{ $: "WildcardPattern" }], body: call("forever") },
    ],
  }, {
    functions: [fn("forever", call("forever"), {
      result_type: u32Type,
      exported: false,
    })],
  });
  equal(analyze(source, { const_steps: 3n }).remaining_steps, 0n);
  expectNumber(source, 42);
});

Deno.test("const guards bind only the successful continuation", () => {
  for (
    const [value, expected] of [
      [constructor("Some", integer(42)), 42],
      [constructor("Nothing"), 7],
    ] as const
  ) {
    expectNumber(
      constantModule(
        bind(
          "value",
          integer(7),
          block(10n, {
            $: "GuardExpr",
            pattern: constructorPattern("Some", {
              $: "BindingPattern",
              name: "value",
            }),
            value,
            alternative: exit(10n, local("value")),
            body: exit(10n, local("value")),
          }),
        ),
        { data_types: [maybe] },
      ),
      expected,
    );
  }
});

Deno.test("const return skips later operands and propagates to its own block", () => {
  const cases: readonly (readonly [Expr, bigint])[] = [
    [{
      $: "SequenceExpr",
      first: block(21n, exit(20n, integer(42))),
      next: call("forever"),
    }, 5n],
    [add(exit(20n, integer(42)), call("forever")), 4n],
  ];
  for (const [body, steps] of cases) {
    const source = constantModule(block(20n, body), {
      functions: [fn("forever", call("forever"), {
        result_type: u32Type,
        exported: false,
      })],
    });
    expectNumber(source, 42);
    equal(analyze(source, { const_steps: steps }).remaining_steps, 0n);
  }
});

Deno.test("const application charges evaluated expressions once against one shared budget", () => {
  const source = constantModule(apply(
    lambda(30n, "value", local("value")),
    integer(42),
  ));
  throws(
    () => analyze(source, { const_steps: 3n }),
    (error) => error instanceof CompilerError && error.code === "const_budget",
  );
  equal(analyze(source, { const_steps: 4n }).remaining_steps, 0n);
  expectNumber(source, 42);
});

Deno.test("const products preserve immutable nested values with exact source-node fuel", () => {
  const source = constantModule(product(
    integer(7),
    product(
      { $: "BoolExpr", value: true },
      { $: "F32Expr", value: -0 },
      { $: "UnitExpr" },
    ),
  ));
  const original = structuredClone(source);
  const analysis = analyze(source, { const_steps: 6n });
  equal(analysis.remaining_steps, 0n);
  equal(analysis.constants[0].value, {
    $: "ProductValue",
    elements: [
      { $: "U32Value", value: 7 },
      {
        $: "ProductValue",
        elements: [
          { $: "BoolValue", value: true },
          { $: "F32Value", value: -0 },
          { $: "UnitValue" },
        ],
      },
    ],
  });
  equal(source, original);
  throws(
    () => analyze(source, { const_steps: 5n }),
    (error) => error instanceof CompilerError && error.code === "const_budget",
  );
});

Deno.test("const projection evaluates the product once and can reuse every element", () => {
  const direct = constantModule(project(product(integer(40), integer(2)), 1n));
  equal(analyze(direct, { const_steps: 4n }).remaining_steps, 0n);
  expectNumber(direct, 2);
  throws(
    () => analyze(direct, { const_steps: 3n }),
    (error) => error instanceof CompilerError && error.code === "const_budget",
  );
  const reused = constantModule(bind(
    "pair",
    product(integer(40), integer(2)),
    add(project(local("pair"), 0n), project(local("pair"), 1n)),
  ));
  equal(analyze(reused, { const_steps: 9n }).remaining_steps, 0n);
  expectNumber(reused, 42);
});

Deno.test("const products evaluate left-to-right even when projection ignores a later field", () => {
  const first: Expr = { $: "PanicExpr", message: "first product element" };
  const second: Expr = { $: "PanicExpr", message: "second product element" };
  for (
    const [value, detail] of [
      [product(first, second), "first product element"],
      [project(product(integer(42), second), 0n), "second product element"],
    ] as const
  ) {
    throws(() => analyze(constantModule(value)), (error) => {
      ok(error instanceof CompilerError);
      equal(error.code, "const_panic");
      equal(error.detail, detail);
      return true;
    });
  }
});

Deno.test("product returns skip pending elements without extra fuel charges", () => {
  const returning = exit(89n, integer(42));
  const skipped: Expr = { $: "PanicExpr", message: "unreachable element" };
  for (
    const [expression, steps] of [
      [product(returning, skipped), 4n],
      [product(integer(9), returning, skipped), 5n],
      [project(returning, 0n), 4n],
      [project(product(returning, skipped), 1n), 5n],
    ] as const
  ) {
    const analysis = analyze(constantModule(block(89n, expression)), {
      const_steps: steps,
    });
    equal(analysis.remaining_steps, 0n);
    equal(analysis.constants[0].value, { $: "U32Value", value: 42 });
  }
});

Deno.test("const product closures remain reachable in runtime serialization", async () => {
  const source = module([fn(
    "entry",
    apply(
      project({ $: "ConstantExpr", name: "bundle" }, 1n),
      project({ $: "ConstantExpr", name: "bundle" }, 0n),
    ),
  )], {
    constants: [{
      name: "bundle",
      exported: false,
      annotation: null,
      value: bind(
        "offset",
        integer(2),
        product(
          integer(40),
          lambda(40n, "argument", add(local("argument"), local("offset"))),
        ),
      ),
    }],
  });
  const artifact = compile(source);
  const value = artifact.analysis.constants[0].value;
  ok(value.$ === "ProductValue");
  ok(value.elements[1].$ === "ClosureValue");
  const { instance } = await WebAssembly.instantiate(artifact.bytes);
  const entry = instance.exports.entry;
  ok(typeof entry === "function");
  equal(entry(0), 42);
  equal(entry(0), 42);
});

Deno.test("products may contain const-only descriptors but cannot leak them into Wasm", () => {
  const ask = operation("Reader.ask");
  const constants = [{
    name: "bundle",
    exported: false,
    annotation: null,
    value: product(
      { $: "OperationDescriptorExpr", identity: ask.identity },
      integer(42),
    ),
  }];
  const answer = project({ $: "ConstantExpr", name: "bundle" }, 1n);
  const artifact = compile(module([], {
    operations: [ask],
    constants: [...constants, {
      name: "answer",
      exported: true,
      annotation: null,
      value: answer,
    }],
  }));
  equal(artifact.analysis.constants[1].value, { $: "U32Value", value: 42 });
  throws(
    () =>
      compile(module([fn("entry", answer)], {
        operations: [ask],
        constants,
      })),
    (error) =>
      error instanceof CompilerError && error.code === "backend_const_only",
  );
});

Deno.test("malformed products and projections fail explicitly", () => {
  for (
    const [value, code] of [
      [product(), "product_arity"],
      [product(integer(1)), "product_arity"],
      [project(product(integer(1), integer(2)), 2n), "product_index"],
      [project(integer(1), 0n), "type_mismatch"],
    ] as const
  ) {
    throws(
      () => analyze(constantModule(value)),
      (error) => error instanceof CompilerError && error.code === code,
    );
  }
});

Deno.test("const and Wasm agree on block exits from pending expression operands", async () => {
  const returning = exit(90n, integer(42));
  const forever = call("forever");
  const expressions: Expr[] = [
    add(integer(100), returning),
    add(returning, forever),
    call("identity", returning),
    apply({ $: "FunctionExpr", name: "identity" }, returning),
    apply(returning, forever),
    constructor("Some", returning),
    product(returning, forever),
    product(integer(9), returning, forever),
    project(returning, 0n),
    project(product(returning, forever), 1n),
    {
      $: "MatchExpr",
      values: [returning],
      arms: [{ patterns: [{ $: "WildcardPattern" }], body: forever }],
    },
    {
      $: "IfExpr",
      condition: returning,
      consequent: forever,
      alternative: forever,
    },
    bind("unused", returning, forever),
    exit(90n, returning),
  ];
  for (const expression of expressions) {
    const body = block(90n, expression);
    const source = constantModule(body, {
      data_types: [maybe],
      functions: [
        fn("entry", body),
        fn("identity", local("value"), {
          parameter_type: u32Type,
          exported: false,
        }),
        fn("forever", forever, { result_type: u32Type, exported: false }),
      ],
    });
    const artifact = compile(source);
    equal(artifact.analysis.constants[0].value, { $: "U32Value", value: 42 });
    equal(WebAssembly.validate(artifact.bytes), true);
    const { instance } = await WebAssembly.instantiate(artifact.bytes);
    equal((instance.exports.entry as (argument: number) => number)(0), 42);
  }
});
