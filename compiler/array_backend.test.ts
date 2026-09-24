import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import generated from "../generated/compiler/compiler.js";
import {
  compile,
  CompilerError,
  type CoreModule,
  type Expr,
  type FunctionDefinition,
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
} from "./fixtures.ts";

const arrayType = (element: Type): Type => ({ $: "ArrayTy", element });
const array = (...elements: Expr[]): Expr => ({ $: "ArrayExpr", elements });
const get = (array: Expr, index: Expr): Expr => ({
  $: "ArrayGetExpr",
  array,
  index,
});
const set = (array: Expr, index: Expr, value: Expr): Expr => ({
  $: "ArraySetExpr",
  array,
  index,
  value,
});
const length = (array: Expr): Expr => ({ $: "ArrayLengthExpr", array });
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
const sequence = (first: Expr, next: Expr): Expr => ({
  $: "SequenceExpr",
  first,
  next,
});
const lambda = (identity: bigint, parameter: string, body: Expr): Expr => ({
  $: "LambdaExpr",
  identity,
  parameter,
  parameter_type: null,
  result_type: null,
  body,
});
const product = (...elements: Expr[]): Expr => ({ $: "ProductExpr", elements });
const project = (value: Expr, index: bigint): Expr => ({
  $: "ProjectExpr",
  value,
  index,
});
const callbackType = {
  $: "FunctionTy",
  parameter: u32Type,
  result: u32Type,
  effects: {
    $: "EffectRow",
    operations: [{
      $: "TypeId",
      module_name: "blot:compiler",
      declaration: "Foreign",
    }],
    tail: { $: "ClosedRow" },
  },
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

Deno.test("Wasm arrays preserve scalar words and empty lengths without exporting memory", () => {
  const compiled = instantiate(module([
    fn("unsigned", get(array(local("value"), integer(42)), integer(0)), {
      parameter_type: u32Type,
    }),
    fn("negative_zero", get(array({ $: "F32Expr", value: -0 }), integer(0))),
    fn("boolean", get(array({ $: "BoolExpr", value: true }), integer(0))),
    fn("unit", get(array(unit), integer(0))),
    fn("empty", length(array())),
    fn("constant_empty", length(constant("empty_values"))),
    fn("constant_unsigned", get(constant("numbers"), integer(0))),
    fn("count", length(array(integer(1), integer(2), integer(3)))),
  ], {
    constants: [
      {
        name: "empty_values",
        exported: false,
        annotation: null,
        value: array(),
      },
      {
        name: "numbers",
        exported: false,
        annotation: null,
        value: array(integer(0xffffffff)),
      },
    ],
  }));
  equal(compiled.exports.unsigned(0xffffffff) >>> 0, 0xffffffff);
  equal(compiled.exports.constant_unsigned(0) >>> 0, 0xffffffff);
  ok(Object.is(compiled.exports.negative_zero(0), -0));
  equal(compiled.exports.boolean(0), 1);
  equal(compiled.exports.unit(0), 0);
  equal(compiled.exports.empty(0), 0);
  equal(compiled.exports.constant_empty(0), 0);
  equal(compiled.exports.count(0), 3);
  equal(WebAssembly.Module.imports(compiled.wasm), []);
  ok(
    WebAssembly.Module.exports(compiled.wasm).every(({ kind }) =>
      kind !== "memory"
    ),
  );
  equal(compiled.artifact.analysis.constants[1].value, {
    $: "ArrayValue",
    elements: [{ $: "U32Value", value: 0xffffffff }],
  });
});

Deno.test("Wasm array updates preserve dynamic and static aliases", () => {
  const unchangedAndUpdated = (original: Expr): Expr =>
    bind(
      "original",
      original,
      bind(
        "updated",
        set(local("original"), integer(1), integer(40)),
        add(
          get(local("original"), integer(1)),
          get(local("updated"), integer(1)),
        ),
      ),
    );
  const compiled = instantiate(module([
    fn(
      "dynamic",
      unchangedAndUpdated(array(integer(1), integer(2), integer(3))),
    ),
    fn("static", unchangedAndUpdated(constant("numbers"))),
    fn("original", get(constant("numbers"), integer(1))),
    fn(
      "nested",
      bind(
        "outer",
        array(array(integer(2), integer(3)), array(integer(4))),
        bind(
          "updated",
          set(
            local("outer"),
            integer(0),
            set(get(local("outer"), integer(0)), integer(0), integer(40)),
          ),
          add(
            get(get(local("outer"), integer(0)), integer(0)),
            get(get(local("updated"), integer(0)), integer(0)),
          ),
        ),
      ),
    ),
  ], {
    constants: [{
      name: "numbers",
      exported: false,
      annotation: null,
      value: array(integer(1), integer(2), integer(3)),
    }],
  }));
  equal(compiled.exports.dynamic(0), 42);
  equal(compiled.exports.static(0), 42);
  equal(compiled.exports.original(0), 2);
  equal(compiled.exports.nested(0), 42);
  equal(compiled.exports.original(0), 2);
});

Deno.test("Wasm arrays hold product and constructor values without flattening them", () => {
  const identity = {
    $: "TypeId",
    module_name: "test",
    declaration: "Points",
  } as const;
  const point: Type = { $: "ProductTy", elements: [u32Type, { $: "F32Ty" }] };
  const compiled = instantiate(module([
    fn("coordinate", {
      $: "MatchExpr",
      values: [{
        $: "ConstructExpr",
        constructor: "Points",
        payload: array(
          product(integer(1), { $: "F32Expr", value: 1.25 }),
          product(integer(2), { $: "F32Expr", value: -0 }),
        ),
      }],
      arms: [{
        patterns: [{
          $: "ConstructorPattern",
          constructor: "Points",
          payload: { $: "BindingPattern", name: "points" },
        }],
        body: project(get(local("points"), integer(1)), 1n),
      }],
    }),
  ], {
    data_types: [{
      identity,
      parameters: 0n,
      constructors: [{ name: "Points", payload: arrayType(point) }],
    }],
  }));
  ok(Object.is(compiled.exports.coordinate(0), -0));
});

Deno.test("Wasm array constants retain named functions and closures capture array aliases", () => {
  const compiled = instantiate(module([
    fn("increment", add(local("value"), integer(1)), {
      parameter_type: u32Type,
      exported: false,
    }),
    fn("named", apply(get(constant("functions"), integer(0)), integer(41))),
    fn("saved", apply(constant("saved_reader"), integer(2))),
    fn(
      "captured",
      bind(
        "original",
        array(local("value")),
        bind(
          "read",
          lambda(
            2n,
            "extra",
            add(get(local("original"), integer(0)), local("extra")),
          ),
          sequence(
            set(local("original"), integer(0), integer(99)),
            apply(local("read"), integer(2)),
          ),
        ),
      ),
      { parameter_type: u32Type },
    ),
  ], {
    constants: [
      {
        name: "functions",
        exported: false,
        annotation: null,
        value: array({ $: "FunctionExpr", name: "increment" }),
      },
      {
        name: "saved_reader",
        exported: false,
        annotation: null,
        value: bind(
          "captured",
          array(integer(40)),
          lambda(
            1n,
            "extra",
            add(get(local("captured"), integer(0)), local("extra")),
          ),
        ),
      },
    ],
  }));
  equal(compiled.exports.named(0), 42);
  equal(compiled.exports.saved(0), 42);
  equal(compiled.exports.captured(40), 42);
  equal(compiled.exports.captured(5), 7);
});

Deno.test("Wasm array operands execute once in source order before set bounds checks", () => {
  const calls: number[] = [];
  const token = {};
  const effect = (value: number) => apply(local("value"), integer(value));
  const compiled = instantiate(
    module([
      fn(
        "get",
        get(array(effect(1), effect(2)), sequence(effect(3), integer(1))),
        {
          parameter_type: callbackType,
        },
      ),
      fn(
        "set",
        get(
          set(
            array(effect(1), effect(2)),
            sequence(effect(3), integer(1)),
            effect(4),
          ),
          integer(1),
        ),
        { parameter_type: callbackType },
      ),
      fn("length", length(array(effect(5))), { parameter_type: callbackType }),
      fn("invalid", length(set(array(effect(1)), effect(2), effect(3))), {
        parameter_type: callbackType,
      }),
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
  equal(compiled.exports.get(token), 2);
  equal(calls.splice(0), [1, 2, 3]);
  equal(compiled.exports.set(token), 4);
  equal(calls.splice(0), [1, 2, 3, 4]);
  equal(compiled.exports.length(token), 1);
  equal(calls.splice(0), [5]);
  throws(() => compiled.exports.invalid(token), WebAssembly.RuntimeError);
  equal(calls.splice(0), [1, 2, 3]);
});

Deno.test("Wasm array indexes trap at length and cannot wrap through word arithmetic", () => {
  const compiled = instantiate(module([
    fn("get", get(array(integer(42), integer(43)), local("value")), {
      parameter_type: u32Type,
    }),
    fn(
      "set",
      length(set(array(integer(42), integer(43)), local("value"), integer(1))),
      {
        parameter_type: u32Type,
      },
    ),
    fn("empty_get", get(array(), local("value")), {
      parameter_type: u32Type,
      result_type: u32Type,
    }),
    fn("empty_set", length(set(array(), local("value"), integer(1))), {
      parameter_type: u32Type,
    }),
  ]));
  for (const index of [2, 0x40000000, 0x80000000, 0xffffffff]) {
    throws(() => compiled.exports.get(index), WebAssembly.RuntimeError);
    throws(() => compiled.exports.set(index), WebAssembly.RuntimeError);
  }
  throws(() => compiled.exports.empty_get(0), WebAssembly.RuntimeError);
  throws(() => compiled.exports.empty_set(0), WebAssembly.RuntimeError);
  equal(compiled.exports.get(0), 42);
  equal(compiled.exports.get(1), 43);
  equal(compiled.exports.set(0), 2);
});

Deno.test("Wasm nonlocal returns skip remaining array operands and invalid access", () => {
  const calls: number[] = [];
  const token = {};
  const effect = (value: number) => apply(local("value"), integer(value));
  const returned: Expr = { $: "ReturnExpr", label: 7n, value: integer(42) };
  const branches = [
    array(effect(1), returned, effect(2)),
    get(array(effect(1)), returned),
    set(array(effect(1)), returned, effect(2)),
    set(array(effect(1)), effect(2), returned),
    length(sequence(returned, array(effect(2)))),
  ];
  const compiled = instantiate(
    module(branches.map((branch, index) =>
      fn(`early_${index}`, {
        $: "BlockExpr",
        label: 7n,
        body: sequence(branch, {
          $: "PanicExpr",
          message: "unreachable array continuation",
        }),
      }, { parameter_type: callbackType })
    )),
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
  const expected = [[1], [1], [1], [1, 2], []];
  for (let index = 0; index < branches.length; index++) {
    equal(compiled.exports[`early_${index}`](token), 42);
    equal(calls.splice(0), expected[index]);
  }
});

Deno.test("Wasm array local indices and element offsets cross LEB boundaries", () => {
  const compiled = instantiate(module([
    fn(
      "wide",
      get(
        set(
          array(...Array.from({ length: 512 }, (_, index) => integer(index))),
          integer(511),
          local("value"),
        ),
        integer(511),
      ),
      { parameter_type: u32Type },
    ),
  ]));
  for (let iteration = 0; iteration < 16; iteration++) {
    equal(compiled.exports.wide(iteration), iteration);
  }
});

Deno.test("Wasm immutable array allocation grows safely, traps at the arena limit, and resets after traps", () => {
  const numbers = arrayType(u32Type);
  const functions: FunctionDefinition[] = [
    fn("copy_0", set(local("value"), integer(0), integer(42)), {
      parameter_type: numbers,
      exported: false,
    }),
  ];
  for (let depth = 1; depth <= 12; depth++) {
    functions.push(fn(
      `copy_${depth}`,
      sequence(
        call(`copy_${depth - 1}`, local("value")),
        call(`copy_${depth - 1}`, local("value")),
      ),
      { parameter_type: numbers, exported: false },
    ));
  }
  functions.push(
    fn("grow", get(call("copy_6", constant("numbers")), integer(0))),
    fn("exhaust", get(call("copy_12", constant("numbers")), integer(0))),
    fn("original", get(constant("numbers"), integer(0))),
  );
  const compiled = instantiate(module(functions, {
    constants: [{
      name: "numbers",
      exported: false,
      annotation: numbers,
      value: array(
        ...Array.from({ length: 1024 }, (_, index) => integer(index)),
      ),
    }],
  }));
  for (let iteration = 0; iteration < 70; iteration++) {
    equal(compiled.exports.grow(0), 42);
  }
  throws(() => compiled.exports.exhaust(0), WebAssembly.RuntimeError);
  equal(compiled.exports.original(0), 0);
  equal(compiled.exports.grow(0), 42);
});

Deno.test("array lengths are checked before conversion to Wasm byte counts", () => {
  const backend = generated as unknown as {
    "wasm.array_size"(count: bigint):
      | { $: "Done"; value: number }
      | { $: "Fail"; error: { code: string } };
  };
  equal(backend["wasm.array_size"](0n), { $: "Done", value: 4 });
  equal(backend["wasm.array_size"](4194303n), { $: "Done", value: 16777216 });
  for (const count of [4194304n, 1073741824n, 4294967295n, 281474976710655n]) {
    const result = backend["wasm.array_size"](count);
    ok(result.$ === "Fail");
    equal(result.error.code, "backend_limit");
  }
});

Deno.test("arrays cannot be exported constants or cross scalar callbacks", () => {
  const numbers = arrayType(u32Type);
  const cases = [
    module([], {
      constants: [{
        name: "numbers",
        exported: true,
        annotation: numbers,
        value: array(integer(1)),
      }],
    }),
    module([fn("callback_argument", integer(0), {
      parameter_type: { ...callbackType, parameter: numbers },
    })]),
    module([fn("callback_result", integer(0), {
      parameter_type: { ...callbackType, result: numbers },
    })]),
  ];
  for (const source of cases) {
    throws(
      () => compile(source),
      (error: unknown) =>
        error instanceof CompilerError &&
        error.code === "backend_type",
    );
  }
});
