import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import generated from "../generated/compiler/compiler.js";
import { toBendModel } from "./bend_abi.ts";
import {
  compile,
  type CoreModule,
  type DataType,
  type Expr,
  type Pattern,
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

const product = (...elements: Expr[]): Expr => ({ $: "ProductExpr", elements });
const productPattern = (...elements: Pattern[]): Pattern => ({
  $: "ProductPattern",
  elements,
});
const wildcard: Pattern = { $: "WildcardPattern" };
const capture = (name: string): Pattern => ({ $: "BindingPattern", name });
const literal = (value: number): Pattern => ({ $: "U32Pattern", value });
const construct = (constructor: string, payload: Expr | null = null): Expr => ({
  $: "ConstructExpr",
  constructor,
  payload,
});
const variant = (
  constructor: string,
  payload: Pattern | null = null,
): Pattern => ({ $: "ConstructorPattern", constructor, payload });
const apply = (callee: Expr, argument: Expr): Expr => ({
  $: "ApplyExpr",
  callee,
  argument,
});
const lambda = (identity: bigint, parameter: string, body: Expr): Expr => ({
  $: "LambdaExpr",
  identity,
  parameter,
  parameter_type: null,
  result_type: null,
  body,
});
const constant = (name: string): Expr => ({ $: "ConstantExpr", name });
const bind = (name: string, value: Expr, body: Expr): Expr => ({
  $: "LetExpr",
  name,
  value,
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
  const instance = new WebAssembly.Instance(wasm, imports);
  return {
    artifact,
    wasm,
    instance,
    exports: instance.exports as Record<string, (value: unknown) => number>,
  };
}

Deno.test("Wasm nested tuple and constructor patterns preserve scalar word representations", () => {
  const compiled = instantiate(module([
    fn("coordinate", {
      $: "MatchExpr",
      values: [product(
        local("value"),
        construct(
          "Some",
          product({ $: "BoolExpr", value: true }, { $: "F32Expr", value: -0 }),
        ),
        unit,
      )],
      arms: [{
        patterns: [productPattern(
          capture("number"),
          variant(
            "Some",
            productPattern(
              { $: "BoolPattern", value: true },
              capture("coordinate"),
            ),
          ),
          { $: "UnitPattern" },
        )],
        body: local("coordinate"),
      }, {
        patterns: [wildcard],
        body: { $: "F32Expr", value: 1.25 },
      }],
    }, { parameter_type: u32Type }),
    fn("unsigned", {
      $: "MatchExpr",
      values: [
        product(unit, product(local("value"), { $: "BoolExpr", value: true })),
      ],
      arms: [{
        patterns: [
          productPattern(wildcard, productPattern(capture("number"), wildcard)),
        ],
        body: local("number"),
      }],
    }, { parameter_type: u32Type }),
  ], { data_types: [maybe] }));
  ok(Object.is(compiled.exports.coordinate(42), -0));
  equal(compiled.exports.unsigned(0xffffffff) >>> 0, 0xffffffff);
});

Deno.test("Wasm tuple patterns short-circuit constructor payloads before nested field tests", () => {
  const compiled = instantiate(module([
    fn("answer", {
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
        alternative: construct(
          "Some",
          product(
            local("value"),
            construct("Some", product(integer(1), integer(2))),
          ),
        ),
      }],
      arms: [{
        patterns: [variant(
          "Some",
          productPattern(
            literal(0xffffffff),
            variant("Some", productPattern(literal(1), capture("extra"))),
          ),
        )],
        body: add(integer(40), local("extra")),
      }, {
        patterns: [wildcard],
        body: integer(0),
      }],
    }, { parameter_type: u32Type }),
  ], { data_types: [maybe] }));
  equal(compiled.exports.answer(0), 0);
  equal(compiled.exports.answer(40), 0);
  equal(compiled.exports.answer(0xffffffff), 42);
});

Deno.test("a failed tuple field skips an invalid later constructor pointer", () => {
  type List<T> =
    | { readonly $: "Nil" }
    | { readonly $: "Con"; readonly head: T; readonly tail: List<T> };
  type RawPattern = {
    readonly $: string;
    readonly [field: string]: unknown;
  };
  type Fragment =
    | { readonly $: "wasm.Bytes"; readonly bytes: List<number> }
    | { readonly $: "wasm.ConstructorIndex"; readonly name: string };
  function list<T>(values: readonly T[]): List<T> {
    let result: List<T> = { $: "Nil" };
    for (let index = values.length - 1; index >= 0; index--) {
      result = { $: "Con", head: values[index], tail: result };
    }
    return result;
  }
  function array<T>(values: List<T>): T[] {
    const result: T[] = [];
    for (let cursor = values; cursor.$ === "Con"; cursor = cursor.tail) {
      result.push(cursor.head);
    }
    return result;
  }
  const backend = generated as unknown as {
    "wasm.pattern_test_work"(
      fuel: bigint,
      work: RawPattern,
      locals: List<unknown>,
    ):
      | { readonly $: "Done"; readonly value: List<Fragment> }
      | { readonly $: "Fail"; readonly error: unknown };
  };
  const result = backend["wasm.pattern_test_work"](
    16384n,
    toBendModel({
      $: "wasm.PatternTest",
      location: { $: "wasm.Location", local: 0n, offsets: list([]) },
      pattern: {
        $: "ProductPattern",
        elements: list<RawPattern>([
          { $: "U32Pattern", value: 1 },
          {
            $: "ConstructorPattern",
            constructor: "Some",
            payload: {
              $: "Some",
              value: {
                $: "ProductPattern",
                elements: list([
                  { $: "U32Pattern", value: 2 },
                  { $: "U32Pattern", value: 3 },
                ]),
              },
            },
          },
        ]),
      },
    }),
    list([]),
  );
  ok(result.$ === "Done");
  const instructions = array(result.value).flatMap((fragment) => {
    if (fragment.$ === "wasm.Bytes") return array(fragment.bytes);
    equal(fragment.name, "Some");
    return [65, 0];
  });
  const leb = (value: number): number[] => {
    const bytes: number[] = [];
    do {
      const word = value & 0x7f;
      value >>>= 7;
      bytes.push(word | (value === 0 ? 0 : 0x80));
    } while (value !== 0);
    return bytes;
  };
  const section = (id: number, bytes: number[]) => [
    id,
    ...leb(bytes.length),
    ...bytes,
  ];
  const body = [0, ...instructions, 11];
  // This predicate-only harness exposes test memory so the later pointer can
  // be invalid; well-typed source values cannot otherwise demonstrate a read.
  const wasm = new WebAssembly.Module(Uint8Array.from([
    0,
    97,
    115,
    109,
    1,
    0,
    0,
    0,
    ...section(1, [1, 96, 1, 127, 1, 127]),
    ...section(3, [1, 0]),
    ...section(5, [1, 0, 1]),
    ...section(7, [
      2,
      4,
      116,
      101,
      115,
      116,
      0,
      0,
      6,
      109,
      101,
      109,
      111,
      114,
      121,
      2,
      0,
    ]),
    ...section(10, [1, ...leb(body.length), ...body]),
  ]));
  const instance = new WebAssembly.Instance(wasm);
  const test = instance.exports.test as (address: number) => number;
  const memory = instance.exports.memory as WebAssembly.Memory;
  const words = new DataView(memory.buffer);
  words.setUint32(16, 0, true);
  words.setUint32(20, 0xfffffff0, true);
  equal(test(16), 0);
  words.setUint32(16, 1, true);
  throws(() => test(16), WebAssembly.RuntimeError);
  words.setUint32(20, 32, true);
  words.setUint32(32, 0, true);
  words.setUint32(36, 48, true);
  words.setUint32(48, 2, true);
  words.setUint32(52, 3, true);
  equal(test(16), 1);
  words.setUint32(48, 9, true);
  equal(test(16), 0);
});

Deno.test("multiple tuple scrutinees evaluate once left-to-right before ordered row matching", () => {
  const calls: number[] = [];
  const token = {};
  const effect = (value: number) => apply(local("value"), integer(value));
  const compiled = instantiate(
    module([
      fn("answer", {
        $: "MatchExpr",
        values: [
          product(effect(1), effect(2)),
          product(effect(3), effect(4)),
        ],
        arms: [{
          patterns: [
            productPattern(literal(1), capture("left")),
            productPattern(capture("right"), literal(4)),
          ],
          body: add(add(local("left"), local("right")), integer(37)),
        }, {
          patterns: [wildcard, wildcard],
          body: integer(0),
        }],
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
  equal(compiled.exports.answer(token), 42);
  equal(calls, [1, 2, 3, 4]);
});

Deno.test("closures capture tuple bindings after shadowing in runtime and constant environments", () => {
  const compiled = instantiate(module([
    fn(
      "build",
      bind(
        "left",
        integer(999),
        lambda(1n, "pair", {
          $: "MatchExpr",
          values: [local("pair")],
          arms: [{
            patterns: [productPattern(capture("left"), capture("right"))],
            body: lambda(
              2n,
              "extra",
              add(
                add(local("left"), local("right")),
                add(local("value"), local("extra")),
              ),
            ),
          }],
        }),
      ),
      { parameter_type: u32Type, exported: false },
    ),
    fn(
      "dynamic",
      apply(
        apply(call("build", integer(1)), product(local("value"), integer(20))),
        integer(1),
      ),
      { parameter_type: u32Type },
    ),
    fn("saved", apply(constant("saved_reader"), integer(1))),
  ], {
    constants: [{
      name: "saved_reader",
      exported: false,
      annotation: null,
      value: apply(
        call("build", integer(1)),
        product(integer(20), integer(20)),
      ),
    }],
  }));
  equal(compiled.exports.dynamic(20), 42);
  equal(compiled.exports.dynamic(5), 27);
  equal(compiled.exports.saved(0), 42);
});

Deno.test("guarded tuple destructuring binds lambda locals and preserves early returns", () => {
  const compiled = instantiate(module([
    fn(
      "answer",
      apply(
        lambda(3n, "pair", {
          $: "BlockExpr",
          label: 7n,
          body: {
            $: "SequenceExpr",
            first: {
              $: "GuardExpr",
              pattern: productPattern(variant("Some", capture("number")), {
                $: "BoolPattern",
                value: true,
              }),
              value: local("pair"),
              alternative: { $: "ReturnExpr", label: 7n, value: integer(0) },
              body: {
                $: "ReturnExpr",
                label: 7n,
                value: add(local("number"), integer(2)),
              },
            },
            next: {
              $: "PanicExpr",
              message: "unreachable tuple guard continuation",
            },
          },
        }),
        product({
          $: "IfExpr",
          condition: {
            $: "ScalarExpr",
            operator: { $: "Equal" },
            left: local("value"),
            right: integer(0),
          },
          consequent: construct("Nothing"),
          alternative: construct("Some", local("value")),
        }, { $: "BoolExpr", value: true }),
      ),
      { parameter_type: u32Type },
    ),
  ], { data_types: [maybe] }));
  equal(compiled.exports.answer(40), 42);
  equal(compiled.exports.answer(0), 0);
});

Deno.test("tuple case returns preserve enclosing block depths and pending scalar operands", () => {
  const compiled = instantiate(module([
    fn("answer", {
      $: "BlockExpr",
      label: 1n,
      body: add(integer(40), {
        $: "BlockExpr",
        label: 2n,
        body: {
          $: "MatchExpr",
          values: [
            product(
              local("value"),
              construct("Some", product(integer(2), integer(3))),
            ),
          ],
          arms: [{
            patterns: [productPattern(literal(0), wildcard)],
            body: { $: "ReturnExpr", label: 1n, value: integer(7) },
          }, {
            patterns: [
              productPattern(
                wildcard,
                variant("Some", productPattern(capture("extra"), wildcard)),
              ),
            ],
            body: { $: "ReturnExpr", label: 2n, value: local("extra") },
          }, {
            patterns: [wildcard],
            body: { $: "ReturnExpr", label: 1n, value: integer(99) },
          }],
        },
      }),
    }, { parameter_type: u32Type }),
  ], { data_types: [maybe] }));
  equal(compiled.exports.answer(1), 42);
  equal(compiled.exports.answer(0), 7);
});

Deno.test("constant and runtime tuple patterns agree on correlated ordered cases", () => {
  const classify: Expr = {
    $: "MatchExpr",
    values: [local("value")],
    arms: [{
      patterns: [productPattern({ $: "BoolPattern", value: true }, literal(0))],
      body: integer(10),
    }, {
      patterns: [productPattern({ $: "BoolPattern", value: false }, wildcard)],
      body: integer(20),
    }, {
      patterns: [productPattern({ $: "BoolPattern", value: true }, wildcard)],
      body: integer(30),
    }],
  };
  const values = [
    product({ $: "BoolExpr", value: true }, integer(0)),
    product({ $: "BoolExpr", value: false }, integer(0)),
    product({ $: "BoolExpr", value: true }, integer(1)),
    product({ $: "BoolExpr", value: false }, integer(0xffffffff)),
  ];
  const compiled = instantiate(module([
    fn("classify", classify, { parameter_type: null, exported: false }),
    ...values.map((value, index) =>
      fn("runtime_" + index, call("classify", value))
    ),
  ], {
    constants: values.map((value, index) => ({
      name: "constant_" + index,
      exported: true,
      annotation: null,
      value: call("classify", value),
    })),
  }));
  for (let index = 0; index < values.length; index++) {
    equal(
      compiled.exports["runtime_" + index](0),
      (compiled.instance.exports["constant_" + index] as WebAssembly.Global)
        .value,
    );
  }
  equal(values.map((_, index) => compiled.exports["runtime_" + index](0)), [
    10,
    20,
    30,
    20,
  ]);
});

Deno.test("wide tuple pattern field offsets cross LEB boundaries", () => {
  const count = 128;
  const compiled = instantiate(module([
    fn("answer", {
      $: "MatchExpr",
      values: [
        product(...Array.from({ length: count }, (_, index) => integer(index))),
      ],
      arms: [{
        patterns: [productPattern(
          ...Array.from({ length: count - 1 }, () => wildcard),
          capture("last"),
        )],
        body: local("last"),
      }],
    }),
  ]));
  equal(compiled.exports.answer(0), count - 1);
});
