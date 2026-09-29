import {
  deepStrictEqual as equal,
  ok,
  rejects,
  throws,
} from "node:assert/strict";
import {
  analyze,
  compile,
  CompilerError,
  type CoreModule,
  type Expr,
  type ScalarOp,
  type Type,
  type UnaryOp,
} from "./host.ts";
import { createSourceCompiler } from "./source.ts";
import { createNativeCompiler } from "./native.ts";
import { SourceError } from "./syntax.ts";

const f32Type: Type = { $: "F32Ty" };
const u32Type: Type = { $: "U32Ty" };
const f32 = (value: number): Expr => ({ $: "F32Expr", value });
const u32 = (value: number): Expr => ({ $: "U32Expr", value });
const binary = (operator: ScalarOp["$"], left: Expr, right: Expr): Expr => ({
  $: "ScalarExpr",
  operator: { $: operator },
  left,
  right,
});
const unary = (operator: UnaryOp["$"], value: Expr): Expr => ({
  $: "UnaryExpr",
  operator: { $: operator },
  value,
});
const local: Expr = { $: "LocalExpr", name: "value" };

function call(exports: WebAssembly.Exports, name: string, value = 0): number {
  const fn = exports[name];
  ok(typeof fn === "function", name);
  return fn(value) as number;
}

async function exportsOf(bytes: Uint8Array<ArrayBuffer>) {
  ok(WebAssembly.validate(bytes));
  return (await WebAssembly.instantiate(bytes)).instance.exports;
}

function numericModule(expressions: readonly Expr[]): CoreModule {
  return {
    operations: [],
    constants: expressions.map((value, index) => ({
      name: `constant_${index}`,
      exported: true,
      annotation: null,
      value,
    })),
    functions: expressions.map((body, index) => ({
      name: `runtime_${index}`,
      exported: true,
      parameter: "value",
      parameter_type: { $: "UnitTy" },
      result_type: null,
      body,
    })),
  };
}

Deno.test("F32 core rounds arithmetic and preserves IEEE comparisons in const and Wasm", async () => {
  const cases: readonly [Expr, number | boolean][] = [
    [f32(0.1), Math.fround(0.1)],
    [f32(-0), -0],
    [binary("F32Add", f32(16_777_216), f32(1)), 16_777_216],
    [binary("F32Subtract", f32(0.25), f32(2.5)), -2.25],
    [
      binary("F32Multiply", f32(0.1), f32(0.2)),
      Math.fround(Math.fround(0.1) * Math.fround(0.2)),
    ],
    [binary("F32Divide", f32(1), f32(3)), Math.fround(1 / 3)],
    [binary("F32Divide", f32(1), f32(0)), Infinity],
    [binary("F32Divide", f32(-1), f32(0)), -Infinity],
    [binary("F32Divide", f32(0), f32(0)), NaN],
    [binary("F32Equal", f32(0), f32(-0)), true],
    [binary("F32Equal", f32(NaN), f32(NaN)), false],
    [binary("F32NotEqual", f32(NaN), f32(1)), true],
    [binary("F32LessThan", f32(-0.5), f32(0)), true],
    [binary("F32LessEqual", f32(1), f32(1)), true],
    [binary("F32GreaterThan", f32(2), f32(1)), true],
    [binary("F32GreaterEqual", f32(NaN), f32(0)), false],
  ];
  const artifact = compile(
    numericModule(cases.map(([expression]) => expression)),
  );
  const exports = await exportsOf(artifact.bytes);
  cases.forEach(([, expected], index) => {
    const value = artifact.analysis.constants[index].value;
    equal(value, {
      $: typeof expected === "boolean" ? "BoolValue" : "F32Value",
      value: expected,
    });
    equal(
      call(exports, `runtime_${index}`),
      typeof expected === "boolean" ? Number(expected) : expected,
    );
    ok(exports[`constant_${index}`] instanceof WebAssembly.Global);
    equal(
      (exports[`constant_${index}`] as WebAssembly.Global).value,
      typeof expected === "boolean" ? Number(expected) : expected,
    );
  });
});

Deno.test("F32 core unary math and saturating conversions agree across const and typed exports", async () => {
  const cases: readonly [UnaryOp["$"], number, number, Type, Type][] = [
    ["F32Negate", 0, -0, f32Type, f32Type],
    ["F32Absolute", -0, 0, f32Type, f32Type],
    ["F32SquareRoot", 2, Math.fround(Math.sqrt(2)), f32Type, f32Type],
    ["F32SquareRoot", -1, NaN, f32Type, f32Type],
    ["F32Floor", -1.25, -2, f32Type, f32Type],
    ["F32Ceiling", -0.25, -0, f32Type, f32Type],
    ["F32Truncate", -1.75, -1, f32Type, f32Type],
    ["U32ToF32", 0xFFFFFFFF, Math.fround(0xFFFFFFFF), u32Type, f32Type],
    ["F32ToU32", 42.75, 42, f32Type, u32Type],
    ["F32ToU32", -42.75, 0, f32Type, u32Type],
    ["F32ToU32", NaN, 0, f32Type, u32Type],
    ["F32ToU32", Infinity, 0xFFFFFFFF, f32Type, u32Type],
    ["F32ToU32", 4_294_967_040, 4_294_967_040, f32Type, u32Type],
    ["F32ToU32", 4_294_967_296, 0xFFFFFFFF, f32Type, u32Type],
  ];
  const expressions = cases.map(([operator, input, , parameter]) =>
    unary(operator, parameter.$ === "U32Ty" ? u32(input) : f32(input))
  );
  const base = numericModule(expressions);
  const artifact = compile({
    ...base,
    functions: cases.map((
      [operator, , , parameter_type, result_type],
      index,
    ) => ({
      name: `runtime_${index}`,
      exported: true,
      parameter: "value",
      parameter_type,
      result_type,
      body: unary(operator, local),
    })),
  });
  const exports = await exportsOf(artifact.bytes);
  cases.forEach(([, input, expected, , result], index) => {
    equal(artifact.analysis.constants[index].value, {
      $: result.$ === "U32Ty" ? "U32Value" : "F32Value",
      value: expected,
    });
    const actual = call(exports, `runtime_${index}`, input);
    equal(result.$ === "U32Ty" ? actual >>> 0 : actual, expected);
  });
});

Deno.test("F32 core rejects implicit U32 conversion", () => {
  for (
    const expression of [
      binary("F32Add", u32(1), f32(2)),
      binary("Add", f32(1), u32(2)),
      unary("F32SquareRoot", u32(4)),
      unary("U32ToF32", f32(4)),
    ]
  ) {
    throws(
      () => analyze(numericModule([expression])),
      (error) =>
        error instanceof CompilerError && error.code === "type_mismatch",
    );
  }
});

Deno.test("F32 primitive traversal preserves latent operation effects on function values", () => {
  const identity = {
    $: "TypeId" as const,
    module_name: "numeric",
    declaration: "Amount.read",
  };
  const analysis = analyze({
    constants: [],
    operations: [{ identity, parameter: { $: "UnitTy" }, result: f32Type }],
    functions: [{
      name: "read",
      exported: false,
      parameter: "value",
      parameter_type: { $: "UnitTy" },
      result_type: f32Type,
      body: unary("F32Negate", {
        $: "ApplyExpr",
        callee: { $: "OperationExpr", identity },
        argument: { $: "UnitExpr" },
      }),
    }, {
      name: "capture",
      exported: false,
      parameter: "value",
      parameter_type: { $: "UnitTy" },
      result_type: null,
      body: { $: "FunctionExpr", name: "read" },
    }],
  });
  const captured = analysis.functions.find((fn) => fn.name === "capture");
  ok(captured);
  equal(captured.effects, []);
  const result = captured.result;
  ok(result.$ === "FunctionTy");
  equal(result.effects.operations, [identity]);
});

const sourceMath = `
const make_offset = fn captured => fn value => F32.add captured value
entry const offset = make_offset (-0.25)
const nested = #Some (#Some 0.125)
entry const rounded = F32.add 16_777_216.0 1.0
entry const negative_zero = -0.0
entry const infinity = F32.div 1.0 0.0
entry const not_a_number = F32.div 0.0 0.0
entry const negative = fn (value: F32) => -value
entry const length = fn () => F32.length3 2.0 3.0 6.0
entry const partial = fn (value: F32) => offset (identity value)
entry const extract = fn () => case nested of
  #Some (#Some value) => value
  _ => 0.0
entry const decimal = fn () => 1_2.5_0e-1
entry const integer = fn (value: F32) => F32.to_u32 value
entry const floating = fn (value: U32) => U32.to_f32 value
entry const finite = fn (value: F32) => F32.is_finite value
`;

Deno.test("F32 source literals, negative values, prelude math and generic closures execute", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(sourceMath);
    const exports = await exportsOf(artifact.bytes);
    equal(call(exports, "negative", 1.25), -1.25);
    equal(call(exports, "negative", 0), -0);
    equal(call(exports, "length"), 7);
    equal(call(exports, "partial", 2), 1.75);
    equal(call(exports, "extract"), 0.125);
    equal(call(exports, "decimal"), 1.25);
    equal(call(exports, "integer", 2.75), 2);
    equal(call(exports, "floating", 16_777_217), 16_777_216);
    equal(call(exports, "finite", Infinity), 0);
    equal(call(exports, "finite", NaN), 0);
    equal(call(exports, "finite", 1.25), 1);
    equal((exports.negative_zero as WebAssembly.Global).value, -0);
    for (
      const [source, code] of [
        ["const bad = 3.5e38", "float_range"],
        ["const bad = @f32.add 1 2.0", "type_mismatch"],
        ["const bad = @f32.sqrt 4.0 2.0", "call_arity"],
        ["const bad = @f32.add 1.0", "call_arity"],
        ["const bad = @f32.missing 1.0", "unknown_intrinsic"],
      ]
    ) {
      throws(
        () => compiler.compile(source),
        (error) => error instanceof SourceError && error.code === code,
        source,
      );
    }
  } finally {
    compiler.dispose();
  }
});

Deno.test("F32 native analysis, closures and Wasm match the JS reference", async () => {
  const reference = await createSourceCompiler();
  const native = await createNativeCompiler();
  try {
    equal(await native.analyze(sourceMath), reference.analyze(sourceMath));
    const actual = await native.compile(sourceMath);
    const expected = reference.compile(sourceMath);
    equal(actual, expected);
    equal(call(await exportsOf(actual.bytes), "partial", 2), 1.75);
    await rejects(
      () => native.compile("const bad = 3.5e38"),
      (error) => error instanceof SourceError && error.code === "float_range",
    );
    equal(
      call(
        await exportsOf(
          (await native.compile("entry const ok = fn () => 0.125")).bytes,
        ),
        "ok",
      ),
      0.125,
    );
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("F32 decimal literals round once, ties-to-even, including subnormal and overflow edges", async () => {
  const reference = await createSourceCompiler({ prelude: "none" });
  const native = await createNativeCompiler({ prelude: "none" });
  const scratch = new DataView(new ArrayBuffer(4));
  const fromBits = (bits: number) => {
    scratch.setUint32(0, bits, true);
    return scratch.getFloat32(0, true);
  };
  const cases: { text: string; expected: number }[] = [];
  const boundaries = [
    0,
    1,
    2,
    0x007FFFFF,
    0x00800000,
    0x3F7FFFFF,
    0x3F800000,
    0x3F800001,
    0x7F7FFFFF,
  ];
  let random = 0xB107F32;
  for (let count = 0; count < 24; count++) {
    random = (Math.imul(random, 1664525) + 1013904223) >>> 0;
    boundaries.push(random % 0x7F7FFFFF);
  }
  for (const lower of boundaries) {
    const exponent = lower >>> 23;
    const significand = (lower & 0x7FFFFF) + (exponent === 0 ? 0 : 0x800000);
    const power = (exponent === 0 ? 1 : exponent) - 151;
    const decimalPlaces = Math.max(0, -power);
    const midpoint = BigInt(2 * significand + 1) *
      (power < 0 ? 5n ** BigInt(-power) : 2n ** BigInt(power));
    for (const delta of [-1n, 0n, 1n]) {
      const bits = delta < 0n
        ? lower
        : delta > 0n
        ? lower + 1
        : lower + (lower & 1);
      cases.push({
        text: `${midpoint + delta}e-${decimalPlaces}`,
        expected: fromBits(bits),
      });
    }
  }
  try {
    const finite = cases.filter(({ expected }) => Number.isFinite(expected));
    const source = finite.map(({ text }, index) =>
      `entry const value_${index} = ${text}`
    ).join("\n");
    const expected = reference.compile(source);
    const actual = await native.compile(source);
    equal(actual, expected);
    const exports = await exportsOf(actual.bytes);
    finite.forEach(({ expected }, index) => {
      equal(actual.analysis.constants[index].value, {
        $: "F32Value",
        value: expected,
      });
      equal((exports[`value_${index}`] as WebAssembly.Global).value, expected);
    });
    for (
      const { text } of cases.filter(({ expected }) =>
        !Number.isFinite(expected)
      )
    ) {
      const source = `const too_large = ${text}`;
      throws(
        () => reference.analyze(source),
        (error) => error instanceof SourceError && error.code === "float_range",
      );
      await rejects(
        () => native.analyze(source),
        (error) => error instanceof SourceError && error.code === "float_range",
      );
    }
  } finally {
    reference.dispose();
    await native.dispose();
  }
});
