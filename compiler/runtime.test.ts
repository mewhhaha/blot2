import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import {
  compile,
  CompilerError,
  type CoreModule,
  type DataType,
  type Expr,
  type Pattern,
} from "./host.ts";
import {
  add,
  boolType,
  call,
  fn,
  integer,
  local,
  module,
  u32Type,
  unit,
} from "./fixtures.ts";

const maybe: DataType = {
  identity: { $: "TypeId", module_name: "test", declaration: "Maybe" },
  parameters: 1n,
  constructors: [
    { name: "Some", payload: { $: "ParameterTy", index: 0n } },
    { name: "Nothing", payload: null },
  ],
};

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
const binding = (name: string, value: Expr, body: Expr): Expr => ({
  $: "LetExpr",
  name,
  value,
  body,
});
const construct = (constructor: string, payload: Expr | null = null): Expr => ({
  $: "ConstructExpr",
  constructor,
  payload,
});
const constructorPattern = (
  constructor: string,
  payload: Pattern | null = null,
): Pattern => ({ $: "ConstructorPattern", constructor, payload });
const wildcard: Pattern = { $: "WildcardPattern" };
const capture = (name: string): Pattern => ({ $: "BindingPattern", name });

async function instantiate(source: CoreModule) {
  const compiled = compile(source);
  ok(WebAssembly.validate(compiled.bytes), "backend must emit valid Wasm");
  const { instance } = await WebAssembly.instantiate(compiled.bytes);
  return {
    ...compiled,
    exports: instance.exports as Record<string, (value: number) => number>,
    module: new WebAssembly.Module(compiled.bytes),
  };
}

Deno.test("Wasm closures escape lexical scopes and preserve captured shadowed values", async () => {
  const compiled = await instantiate(module([
    fn(
      "make_adder",
      lambda(1n, "number", add(local("value"), local("number"))),
      {
        exported: false,
        parameter_type: null,
      },
    ),
    fn(
      "answer",
      binding(
        "adder",
        call("make_adder", local("value")),
        binding("value", integer(900), apply(local("adder"), integer(2))),
      ),
      {
        parameter_type: u32Type,
      },
    ),
  ]));
  equal(compiled.exports.answer(40), 42);
  equal(compiled.exports.answer(5), 7);
});

Deno.test("Wasm first-class named functions and constructor functions share application", async () => {
  const compiled = await instantiate(module([
    fn("increment", add(local("value"), integer(1)), {
      exported: false,
      parameter_type: null,
    }),
    fn(
      "answer",
      binding("wrap", {
        $: "ConstructorRefExpr",
        constructor: "Some",
      }, {
        $: "MatchExpr",
        values: [apply(
          local("wrap"),
          apply({ $: "FunctionExpr", name: "increment" }, local("value")),
        )],
        arms: [
          {
            patterns: [constructorPattern("Some", capture("number"))],
            body: local("number"),
          },
          { patterns: [constructorPattern("Nothing")], body: integer(0) },
        ],
      }),
      { parameter_type: u32Type },
    ),
  ], { data_types: [maybe] }));
  equal(compiled.exports.answer(41), 42);
});

Deno.test("Wasm nested constructor patterns guard payload access and capture pattern bindings", async () => {
  const matched: Expr = {
    $: "MatchExpr",
    values: [{
      $: "IfExpr",
      condition: {
        $: "ScalarExpr",
        operator: { $: "Equal" },
        left: local("value"),
        right: integer(0),
      },
      consequent: construct("Nothing"),
      alternative: construct("Some", construct("Some", local("value"))),
    }],
    arms: [
      {
        patterns: [constructorPattern("Some", constructorPattern("Nothing"))],
        body: lambda(3n, "extra", integer(1)),
      },
      {
        patterns: [constructorPattern(
          "Some",
          constructorPattern("Some", capture("number")),
        )],
        body: lambda(4n, "extra", add(local("number"), local("extra"))),
      },
      {
        patterns: [constructorPattern("Nothing")],
        body: lambda(5n, "extra", integer(0)),
      },
    ],
  };
  const compiled = await instantiate(module([
    fn("answer", apply(matched, integer(2)), { parameter_type: u32Type }),
  ], { data_types: [maybe] }));
  equal(compiled.exports.answer(40), 42);
  equal(compiled.exports.answer(0), 0);
});

Deno.test("Wasm serializes nested algebraic constants and captured constant closures", async () => {
  const compiled = await instantiate(module([
    fn("answer", {
      $: "MatchExpr",
      values: [{ $: "ConstantExpr", name: "wrapped" }],
      arms: [
        {
          patterns: [constructorPattern("Some", capture("number"))],
          body: apply({ $: "ConstantExpr", name: "adder" }, local("number")),
        },
        { patterns: [constructorPattern("Nothing")], body: integer(0) },
      ],
    }),
  ], {
    data_types: [maybe],
    constants: [
      {
        name: "wrapped",
        exported: false,
        annotation: null,
        value: construct("Some", integer(2)),
      },
      {
        name: "adder",
        exported: false,
        annotation: null,
        value: binding(
          "captured",
          integer(40),
          lambda(6n, "number", add(local("captured"), local("number"))),
        ),
      },
    ],
  }));
  equal(compiled.exports.answer(0), 42);
  equal(compiled.exports.answer(0), 42);
});

Deno.test("Wasm guarded destructuring exits its lexical block without duplicated continuations", async () => {
  const compiled = await instantiate(module([
    fn("answer", {
      $: "BlockExpr",
      label: 1n,
      body: {
        $: "GuardExpr",
        pattern: constructorPattern("Some", capture("number")),
        value: {
          $: "IfExpr",
          condition: {
            $: "ScalarExpr",
            operator: { $: "Equal" },
            left: local("value"),
            right: integer(0),
          },
          consequent: construct("Nothing"),
          alternative: construct("Some", local("value")),
        },
        alternative: { $: "ReturnExpr", label: 1n, value: integer(0) },
        body: {
          $: "ReturnExpr",
          label: 1n,
          value: add(local("number"), integer(2)),
        },
      },
    }, { parameter_type: u32Type }),
  ], { data_types: [maybe] }));
  equal(compiled.exports.answer(40), 42);
  equal(compiled.exports.answer(0), 0);
});

Deno.test("Wasm nested block exits preserve pending operands and enclosing return labels", async () => {
  const compiled = await instantiate(module([
    fn("answer", {
      $: "BlockExpr",
      label: 1n,
      body: {
        $: "SequenceExpr",
        first: {
          $: "IfExpr",
          condition: {
            $: "ScalarExpr",
            operator: { $: "Equal" },
            left: local("value"),
            right: integer(0),
          },
          consequent: { $: "ReturnExpr", label: 1n, value: integer(7) },
          alternative: unit,
        },
        next: add(integer(40), {
          $: "BlockExpr",
          label: 2n,
          body: {
            $: "MatchExpr",
            values: [construct("Some", integer(2))],
            arms: [
              {
                patterns: [constructorPattern("Some", capture("number"))],
                body: { $: "ReturnExpr", label: 2n, value: local("number") },
              },
              {
                patterns: [constructorPattern("Nothing")],
                body: { $: "ReturnExpr", label: 1n, value: integer(99) },
              },
            ],
          },
        }),
      },
    }, { parameter_type: u32Type }),
  ], { data_types: [maybe] }));
  equal(compiled.exports.answer(1), 42);
  equal(compiled.exports.answer(0), 7);
});

Deno.test("Wasm export calls reset their private arena after memory growth", async () => {
  let allocate: Expr = call("churn", {
    $: "ScalarExpr",
    operator: { $: "Subtract" },
    left: local("value"),
    right: integer(1),
  });
  for (let i = 0; i < 64; i++) {
    allocate = {
      $: "SequenceExpr",
      first: construct("Some", integer(i)),
      next: allocate,
    };
  }
  const compiled = await instantiate(module([
    fn("churn", {
      $: "IfExpr",
      condition: {
        $: "ScalarExpr",
        operator: { $: "Equal" },
        left: local("value"),
        right: integer(0),
      },
      consequent: integer(42),
      alternative: allocate,
    }, { exported: false, parameter_type: u32Type }),
    fn("answer", call("churn", local("value")), { parameter_type: u32Type }),
  ], { data_types: [maybe] }));
  // Each call allocates 128 KiB; together these exceed the bounded 16 MiB arena.
  for (let call = 0; call < 140; call++) {
    equal(compiled.exports.answer(256), 42);
  }
  equal(WebAssembly.Module.imports(compiled.module), []);
  equal(
    WebAssembly.Module.exports(compiled.module).map((
      { name, kind },
    ) => [name, kind]),
    [["answer", "function"]],
  );
});

Deno.test("Wasm rejects algebraic and closure exports until a persistent host ABI exists", () => {
  for (
    const body of [
      construct("Some", integer(1)),
      lambda(7n, "number", local("number")),
    ]
  ) {
    throws(
      () => compile(module([fn("escape", body)], { data_types: [maybe] })),
      (error) =>
        error instanceof CompilerError && error.code === "backend_type",
    );
  }
  throws(
    () =>
      compile(module([], {
        data_types: [maybe],
        constants: [{
          name: "escape",
          exported: true,
          annotation: null,
          value: construct("Some", integer(1)),
        }],
      })),
    (error) => error instanceof CompilerError && error.code === "backend_type",
  );
});

Deno.test("Wasm U32 pattern literals compare complete unsigned bit patterns", async () => {
  const compiled = await instantiate(module([
    fn("answer", {
      $: "MatchExpr",
      values: [local("value")],
      arms: [
        {
          patterns: [{ $: "U32Pattern", value: 0xffff_ffff }],
          body: integer(42),
        },
        { patterns: [wildcard], body: integer(0) },
      ],
    }, { parameter_type: u32Type }),
  ]));
  equal(compiled.exports.answer(0xffff_ffff), 42);
  equal(compiled.exports.answer(1), 0);
});

Deno.test("Wasm scalar wrappers canonicalize host Bool and Unit inputs", async () => {
  const compiled = await instantiate(module([
    fn("boolean", {
      $: "MatchExpr",
      values: [local("value")],
      arms: [
        { patterns: [{ $: "BoolPattern", value: true }], body: integer(42) },
        { patterns: [{ $: "BoolPattern", value: false }], body: integer(0) },
      ],
    }, { parameter_type: boolType }),
    fn("unit", local("value")),
  ]));
  equal(compiled.exports.boolean(0), 0);
  equal(compiled.exports.boolean(2), 42);
  equal(compiled.exports.boolean(-1), 42);
  equal(compiled.exports.unit(999), 0);
});

Deno.test("Wasm serializes first-class named and constructor function constants", async () => {
  const compiled = await instantiate(module([
    fn("increment", add(local("value"), integer(1)), {
      exported: false,
      parameter_type: u32Type,
    }),
    fn("answer", {
      $: "MatchExpr",
      values: [apply(
        { $: "ConstantExpr", name: "wrap" },
        apply({ $: "ConstantExpr", name: "increment_alias" }, local("value")),
      )],
      arms: [
        {
          patterns: [constructorPattern("Some", capture("number"))],
          body: local("number"),
        },
        { patterns: [constructorPattern("Nothing")], body: integer(0) },
      ],
    }, { parameter_type: u32Type }),
  ], {
    data_types: [maybe],
    constants: [
      {
        name: "increment_alias",
        exported: false,
        annotation: null,
        value: { $: "FunctionExpr", name: "increment" },
      },
      {
        name: "wrap",
        exported: false,
        annotation: null,
        value: { $: "ConstructorRefExpr", constructor: "Some" },
      },
    ],
  }));
  equal(compiled.exports.answer(41), 42);
});
