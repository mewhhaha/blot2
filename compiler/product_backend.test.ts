import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import {
  compile,
  CompilerError,
  type CoreModule,
  type Expr,
  type Type,
} from "./host.ts";
import {
  add,
  call,
  fn,
  integer,
  local,
  module,
  u32Type,
  unit,
  unitType,
} from "./fixtures.ts";

const f32Type: Type = { $: "F32Ty" };
const productType = (...elements: Type[]): Type => ({
  $: "ProductTy",
  elements,
});
const product = (...elements: Expr[]): Expr => ({ $: "ProductExpr", elements });
const project = (value: Expr, index: bigint): Expr => ({
  $: "ProjectExpr",
  value,
  index,
});
const apply = (callee: Expr, argument: Expr): Expr => ({
  $: "ApplyExpr",
  callee,
  argument,
});
const constant = (name: string): Expr => ({ $: "ConstantExpr", name });
const bind = (name: string, value: Expr, body: Expr): Expr => ({
  $: "LetExpr",
  name,
  value,
  body,
});
const lambda = (identity: bigint, parameter: string, body: Expr): Expr => ({
  $: "LambdaExpr",
  identity,
  parameter,
  parameter_type: null,
  result_type: null,
  body,
});
const foreign = {
  $: "TypeId",
  module_name: "blot:compiler",
  declaration: "Foreign",
} as const;
const callbackType = {
  $: "FunctionTy",
  parameter: u32Type,
  result: u32Type,
  effects: { $: "EffectRow", operations: [foreign], tail: { $: "ClosedRow" } },
} satisfies Type;

function instantiate(source: CoreModule, imports: WebAssembly.Imports = {}) {
  const artifact = compile(source);
  ok(WebAssembly.validate(artifact.bytes));
  const wasm = new WebAssembly.Module(artifact.bytes);
  return {
    artifact,
    wasm,
    exports: new WebAssembly.Instance(wasm, imports).exports as Record<
      string,
      (value: unknown) => number
    >,
  };
}

Deno.test("Wasm nested products preserve mixed scalar fields and unsigned bit patterns", () => {
  const source = module([
    fn(
      "make",
      product(local("value"), product({ $: "F32Expr", value: -0 }, unit)),
      {
        parameter_type: u32Type,
        exported: false,
      },
    ),
    fn("number", project(call("make", local("value")), 0n), {
      parameter_type: u32Type,
    }),
    fn("negative_zero", project(project(call("make", integer(42)), 1n), 0n)),
    fn("unit_field", project(project(call("make", integer(42)), 1n), 1n)),
  ]);
  const compiled = instantiate(source);
  equal(compiled.exports.number(0xffffffff) >>> 0, 0xffffffff);
  ok(Object.is(compiled.exports.negative_zero(0), -0));
  equal(compiled.exports.unit_field(0), 0);
  equal(WebAssembly.Module.imports(compiled.wasm), []);
});

Deno.test("Wasm tuple closures preserve lexical captures and constant product environments", () => {
  const compiled = instantiate(module([
    fn(
      "make",
      bind(
        "pair",
        product(local("value"), integer(1)),
        lambda(1n, "extra", add(project(local("pair"), 0n), local("extra"))),
      ),
      {
        parameter_type: u32Type,
        exported: false,
      },
    ),
    fn("dynamic", apply(call("make", local("value")), integer(2)), {
      parameter_type: u32Type,
    }),
    fn("constant", apply(constant("saved"), integer(2))),
  ], {
    constants: [{
      name: "saved",
      exported: false,
      annotation: null,
      value: bind(
        "pair",
        product(integer(40), { $: "BoolExpr", value: true }),
        lambda(2n, "extra", add(project(local("pair"), 0n), local("extra"))),
      ),
    }],
  }));
  equal(compiled.exports.dynamic(40), 42);
  equal(compiled.exports.dynamic(5), 7);
  equal(compiled.exports.constant(0), 42);
});

Deno.test("Wasm product constants retain nested values and reachable named functions", () => {
  const compiled = instantiate(module([
    fn("increment", add(local("value"), integer(1)), {
      parameter_type: u32Type,
      exported: false,
    }),
    fn(
      "answer",
      apply(
        project(constant("functions"), 0n),
        project(project(constant("functions"), 1n), 0n),
      ),
    ),
    fn("negative_zero", project(project(constant("functions"), 1n), 1n)),
  ], {
    constants: [{
      name: "functions",
      exported: false,
      annotation: null,
      value: product(
        { $: "FunctionExpr", name: "increment" },
        product(integer(41), { $: "F32Expr", value: -0 }),
      ),
    }],
  }));
  equal(compiled.exports.answer(0), 42);
  ok(Object.is(compiled.exports.negative_zero(0), -0));
  equal(compiled.artifact.analysis.constants[0].value.$, "ProductValue");
});

Deno.test("Wasm constructor payload products project without losing F32 representation", () => {
  const identity = {
    $: "TypeId",
    module_name: "test",
    declaration: "Point",
  } as const;
  const compiled = instantiate(module([
    fn("coordinate", {
      $: "MatchExpr",
      values: [{
        $: "ConstructExpr",
        constructor: "Point",
        payload: product(integer(42), { $: "F32Expr", value: 1.25 }),
      }],
      arms: [{
        patterns: [{
          $: "ConstructorPattern",
          constructor: "Point",
          payload: { $: "BindingPattern", name: "coordinates" },
        }],
        body: project(local("coordinates"), 1n),
      }],
    }),
  ], {
    data_types: [{
      identity,
      parameters: 0n,
      constructors: [{ name: "Point", payload: productType(u32Type, f32Type) }],
    }],
  }));
  equal(compiled.exports.coordinate(0), 1.25);
});

Deno.test("Wasm product elements and nested projection bases execute exactly once in order", () => {
  const calls: number[] = [];
  const token = {};
  const compiled = instantiate(
    module([
      fn(
        "ordered",
        project(
          project(
            product(
              product(
                apply(local("value"), integer(1)),
                apply(local("value"), integer(2)),
              ),
              apply(local("value"), integer(3)),
            ),
            0n,
          ),
          1n,
        ),
        { parameter_type: callbackType },
      ),
    ]),
    {
      "blot:host/1": {
        call_u32_u32: (received: unknown, value: number) => {
          equal(received, token);
          calls.push(value);
          return value + 40;
        },
      },
    },
  );
  equal(compiled.exports.ordered(token), 42);
  equal(calls, [1, 2, 3]);
});

Deno.test("Wasm nonlocal return skips remaining product elements and continuation", () => {
  const calls: number[] = [];
  const token = {};
  const compiled = instantiate(
    module([
      fn("early", {
        $: "BlockExpr",
        label: 7n,
        body: {
          $: "SequenceExpr",
          first: product(
            apply(local("value"), integer(1)),
            { $: "ReturnExpr", label: 7n, value: integer(42) },
            apply(local("value"), integer(2)),
          ),
          next: { $: "PanicExpr", message: "unreachable product continuation" },
        },
      }, { parameter_type: callbackType }),
    ]),
    {
      "blot:host/1": {
        call_u32_u32: (received: unknown, value: number) => {
          equal(received, token);
          calls.push(value);
          return value;
        },
      },
    },
  );
  equal(compiled.exports.early(token), 42);
  equal(calls, [1]);
});

Deno.test("Wasm product local indices and load offsets cross LEB boundaries", () => {
  const compiled = instantiate(module([
    fn(
      "wide",
      project(
        product(...Array.from({ length: 512 }, (_, index) => integer(index))),
        511n,
      ),
    ),
  ]));
  for (let iteration = 0; iteration < 16; iteration++) {
    equal(compiled.exports.wide(0), 511);
  }
});

Deno.test("products remain private to an invocation and cannot cross ABI1", () => {
  const pairType = productType(u32Type, u32Type);
  const cases = [
    module([fn("result", product(integer(1), integer(2)))]),
    module([fn("parameter", integer(0), { parameter_type: pairType })]),
    module([], {
      constants: [{
        name: "pair",
        exported: true,
        annotation: null,
        value: product(integer(1), integer(2)),
      }],
    }),
    module([
      fn("callback_argument", integer(0), {
        parameter_type: { ...callbackType, parameter: pairType },
      }),
    ]),
    module([
      fn("callback_result", integer(0), {
        parameter_type: { ...callbackType, result: pairType },
      }),
    ]),
  ];
  for (const source of cases) {
    throws(
      () => compile(source),
      (error) =>
        error instanceof CompilerError && error.code === "backend_type",
    );
  }
  const unitResult = instantiate(
    module([fn("unit", unit, { result_type: unitType })]),
  );
  equal(unitResult.exports.unit(0), 0);
});

Deno.test("product projection bounds are rejected before Wasm memory access", () => {
  for (const index of [2n, 4194304n, 281474976710655n]) {
    throws(
      () =>
        compile(
          module([
            fn("outside", project(product(integer(1), integer(2)), index)),
          ]),
        ),
      (error) =>
        error instanceof CompilerError && error.code === "product_index",
    );
  }
});
