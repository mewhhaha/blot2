import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import {
  analyze,
  compile,
  CompilerError,
  type CoreModule,
  type Expr,
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

const array = (...elements: Expr[]): Expr => ({ $: "ArrayExpr", elements });
const fill = (count: Expr, value: Expr): Expr => ({
  $: "ArrayFillExpr",
  count,
  value,
});
const generate = (count: Expr, generator: Expr): Expr => ({
  $: "ArrayGenerateExpr",
  count,
  generator,
});
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
const panic = (message: string): Expr => ({ $: "PanicExpr", message });
const product = (...elements: Expr[]): Expr => ({ $: "ProductExpr", elements });

function constantModule(
  value: Expr,
  options: Partial<Omit<CoreModule, "constants">> = {},
): CoreModule {
  return module([], {
    ...options,
    constants: [{ name: "answer", exported: false, annotation: null, value }],
  });
}

function errorCode(code: string) {
  return (error: unknown) =>
    error instanceof CompilerError && error.code === code;
}

function constantNumber(value: Expr, expected: number, steps?: bigint) {
  const result = analyze(constantModule(value), { const_steps: steps });
  equal(result.constants[0].value, { $: "U32Value", value: expected });
  if (steps !== undefined) equal(result.remaining_steps, 0n);
}

Deno.test("array literals retain nested products and charge each source element", () => {
  const source = constantModule(array(
    product(integer(0xffffffff), { $: "F32Expr", value: -0 }),
    product(integer(2), { $: "F32Expr", value: 1.25 }),
  ));
  const original = structuredClone(source);
  const result = analyze(source, { const_steps: 7n });
  equal(result.remaining_steps, 0n);
  equal(result.constants[0].value, {
    $: "ArrayValue",
    elements: [
      {
        $: "ProductValue",
        elements: [{ $: "U32Value", value: 0xffffffff }, {
          $: "F32Value",
          value: -0,
        }],
      },
      {
        $: "ProductValue",
        elements: [{ $: "U32Value", value: 2 }, { $: "F32Value", value: 1.25 }],
      },
    ],
  });
  equal(source, original);
  throws(() => analyze(source, { const_steps: 6n }), errorCode("const_budget"));
  constantNumber(length(array()), 0, 2n);
  constantNumber(length(array(array(), array(integer(9)))), 2, 5n);
});

Deno.test("array indexing is checked without wrapping U32 indices", () => {
  constantNumber(get(array(integer(40), integer(42)), integer(1)), 42, 5n);
  for (const index of [0, 1, 0x80000000, 0xffffffff]) {
    throws(
      () => analyze(constantModule(get(array(), integer(index)))),
      errorCode("array_bounds"),
    );
  }
  for (const index of [2, 0x80000000, 0xffffffff]) {
    throws(
      () =>
        analyze(
          constantModule(get(array(integer(1), integer(2)), integer(index))),
        ),
      errorCode("array_bounds"),
    );
    throws(
      () =>
        analyze(
          constantModule(
            set(array(integer(1), integer(2)), integer(index), integer(3)),
          ),
        ),
      errorCode("array_bounds"),
    );
  }
});

Deno.test("array updates retain old snapshots and charge every copied element", () => {
  const source = constantModule(
    set(array(integer(1), integer(2), integer(3)), integer(1), integer(42)),
  );
  const result = analyze(source, { const_steps: 10n });
  equal(result.constants[0].value, {
    $: "ArrayValue",
    elements: [{ $: "U32Value", value: 1 }, { $: "U32Value", value: 42 }, {
      $: "U32Value",
      value: 3,
    }],
  });
  equal(result.remaining_steps, 0n);
  throws(() => analyze(source, { const_steps: 9n }), errorCode("const_budget"));
  const snapshots = analyze(constantModule(bind(
    "old",
    array(integer(1), integer(2)),
    bind(
      "next",
      set(local("old"), integer(1), integer(42)),
      product(local("old"), local("next")),
    ),
  ))).constants[0].value;
  equal(snapshots, {
    $: "ProductValue",
    elements: [
      {
        $: "ArrayValue",
        elements: [{ $: "U32Value", value: 1 }, { $: "U32Value", value: 2 }],
      },
      {
        $: "ArrayValue",
        elements: [{ $: "U32Value", value: 1 }, { $: "U32Value", value: 42 }],
      },
    ],
  });
});

Deno.test("array operands are eager left-to-right before bounds validation", () => {
  for (
    const [value, message] of [
      [array(panic("first"), panic("second")), "first"],
      [get(panic("array"), panic("index")), "array"],
      [get(array(integer(1)), panic("index")), "index"],
      [set(panic("array"), panic("index"), panic("value")), "array"],
      [set(array(integer(1)), panic("index"), panic("value")), "index"],
      [set(array(), integer(0), panic("value")), "value"],
    ] as const
  ) {
    throws(() => analyze(constantModule(value)), (error) => {
      ok(error instanceof CompilerError);
      equal(error.code, "const_panic");
      equal(error.detail, message);
      return true;
    });
  }
});

Deno.test("array returns skip pending operands and copy charges", () => {
  const returning = exit(301n, integer(42));
  const skipped = panic("unreachable array operand");
  for (
    const [value, steps] of [
      [array(returning, skipped), 4n],
      [fill(returning, skipped), 4n],
      [generate(returning, panic("unreachable generator")), 4n],
      [generate(integer(2), returning), 5n],
      [fill(integer(2), returning), 5n],
      [get(returning, skipped), 4n],
      [get(array(integer(1)), returning), 6n],
      [set(returning, skipped, skipped), 4n],
      [set(array(integer(1)), returning, skipped), 6n],
      [set(array(integer(1)), integer(0), returning), 7n],
      [length(returning), 4n],
    ] as const
  ) constantNumber(block(301n, value), 42, steps);
});

Deno.test("array const closures remain reachable in Wasm", async () => {
  const source = module([fn("entry", {
    $: "ApplyExpr",
    callee: get({ $: "ConstantExpr", name: "callbacks" }, integer(0)),
    argument: integer(40),
  })], {
    constants: [{
      name: "callbacks",
      exported: false,
      annotation: null,
      value: bind(
        "offset",
        integer(2),
        array({
          $: "LambdaExpr",
          identity: 302n,
          parameter: "argument",
          parameter_type: null,
          result_type: null,
          body: add(local("offset"), local("argument")),
        }),
      ),
    }],
  });
  const artifact = compile(source);
  const value = artifact.analysis.constants[0].value;
  ok(value.$ === "ArrayValue" && value.elements[0].$ === "ClosureValue");
  const { instance } = await WebAssembly.instantiate(artifact.bytes);
  const entry = instance.exports.entry;
  ok(typeof entry === "function");
  equal(entry(0), 42);
  equal(entry(0), 42);
});

Deno.test("const-only array elements cannot be silently erased in runtime serialization", () => {
  const ask = operation("Reader.ask");
  const constants = [{
    name: "descriptors",
    exported: false,
    annotation: null,
    value: array({ $: "OperationDescriptorExpr", identity: ask.identity }),
  }];
  const count = length({ $: "ConstantExpr", name: "descriptors" });
  const artifact = compile(module([], {
    operations: [ask],
    constants: [...constants, {
      name: "count",
      exported: true,
      annotation: null,
      value: count,
    }],
  }));
  equal(artifact.analysis.constants[1].value, { $: "U32Value", value: 1 });
  throws(
    () =>
      compile(module([fn("entry", count)], { operations: [ask], constants })),
    errorCode("backend_const_only"),
  );
});

Deno.test("Wasm immutable arrays preserve high-bit values and old storage across updates", async () => {
  const source = module([
    fn("read", get(array(integer(0xffffffff), integer(42)), local("value")), {
      parameter_type: u32Type,
    }),
    fn(
      "snapshots",
      bind(
        "old",
        array(integer(1), integer(2)),
        bind(
          "next",
          set(local("old"), integer(1), integer(40)),
          add(get(local("old"), integer(1)), get(local("next"), integer(1))),
        ),
      ),
    ),
  ]);
  const { instance } = await WebAssembly.instantiate(compile(source).bytes);
  const read = instance.exports.read;
  const snapshots = instance.exports.snapshots;
  ok(typeof read === "function" && typeof snapshots === "function");
  equal(read(0) >>> 0, 0xffffffff);
  equal(read(1), 42);
  for (const index of [2, 0x80000000, 0xffffffff]) {
    throws(() => read(index), WebAssembly.RuntimeError);
    equal(read(1), 42);
  }
  equal(snapshots(0), 42);
  equal(snapshots(0), 42);
});

Deno.test("const and Wasm agree on returns from every array operand", async () => {
  const returning = exit(303n, integer(42));
  const skipped = call("forever");
  for (
    const value of [
      array(returning, skipped),
      fill(returning, skipped),
      generate(returning, panic("unreachable generator")),
      generate(integer(2), returning),
      fill(integer(2), returning),
      get(returning, skipped),
      get(array(integer(1)), returning),
      set(returning, skipped, skipped),
      set(array(integer(1)), returning, skipped),
      set(array(integer(1)), integer(0), returning),
      length(returning),
    ]
  ) {
    const body = block(303n, value);
    const source = module([
      fn("entry", body),
      fn("forever", call("forever"), { result_type: u32Type, exported: false }),
    ], {
      constants: [{
        name: "answer",
        exported: false,
        annotation: null,
        value: body,
      }],
    });
    const artifact = compile(source);
    equal(artifact.analysis.constants[0].value, { $: "U32Value", value: 42 });
    const { instance } = await WebAssembly.instantiate(artifact.bytes);
    const entry = instance.exports.entry;
    ok(typeof entry === "function");
    equal(entry(0), 42);
  }
});

Deno.test("array element and index types are checked", () => {
  for (
    const value of [
      array(integer(1), { $: "BoolExpr", value: true }),
      get(integer(1), integer(0)),
      get(array(integer(1)), { $: "BoolExpr", value: false }),
      set(array(integer(1)), integer(0), { $: "BoolExpr", value: false }),
      length(integer(1)),
    ]
  ) throws(() => analyze(constantModule(value)), errorCode("type_mismatch"));
});
