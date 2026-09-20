import { deepStrictEqual as equal, throws } from "node:assert/strict";
import {
  analyze,
  compile,
  CompilerError,
  type CoreModule,
  type Expr,
  type Pattern,
} from "./host.ts";
import { add, call, fn, integer, local, module, u32Type } from "./fixtures.ts";

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
      value: apply(
        { $: "ConstructorRefExpr", constructor: "Some" },
        constructor("Some", integer(42)),
      ),
      arms: [
        { pattern: nested, body: local("value") },
        { pattern: { $: "WildcardPattern" }, body: integer(0) },
      ],
    }, { data_types: [maybe] }),
    42,
  );
  expectNumber(
    constantModule({
      $: "MatchExpr",
      value: { $: "ConstructorRefExpr", constructor: "Nothing" },
      arms: [
        { pattern: constructorPattern("Nothing"), body: integer(42) },
        {
          pattern: constructorPattern("Some", { $: "WildcardPattern" }),
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
    value: integer(7),
    arms: [
      { pattern: { $: "U32Pattern", value: 7 }, body: integer(42) },
      { pattern: { $: "WildcardPattern" }, body: call("forever") },
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
    {
      $: "MatchExpr",
      value: returning,
      arms: [{ pattern: { $: "WildcardPattern" }, body: forever }],
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
