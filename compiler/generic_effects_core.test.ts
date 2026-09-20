import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import {
  analyze,
  compile,
  CompilerError,
  type CoreModule,
  type Expr,
  type TypeId,
} from "./host.ts";

function executable(body: Expr): CoreModule {
  return {
    constants: [{
      name: "expected",
      exported: true,
      annotation: null,
      value: body,
    }],
    functions: [{
      name: "answer",
      exported: true,
      parameter: "_",
      parameter_type: { $: "UnitTy" },
      result_type: { $: "U32Ty" },
      body,
    }],
  };
}

Deno.test("multi-match collection does not add const fuel or expose a tuple", () => {
  const source = executable({
    $: "MatchExpr",
    values: [
      { $: "BoolExpr", value: true },
      { $: "BoolExpr", value: false },
      { $: "U32Expr", value: 39 },
    ],
    arms: [{
      patterns: [
        { $: "BoolPattern", value: true },
        { $: "BoolPattern", value: false },
        { $: "BindingPattern", name: "number" },
      ],
      body: {
        $: "ScalarExpr",
        operator: { $: "Add" },
        left: { $: "LocalExpr", name: "number" },
        right: { $: "U32Expr", value: 3 },
      },
    }, {
      patterns: [
        { $: "WildcardPattern" },
        { $: "WildcardPattern" },
        { $: "WildcardPattern" },
      ],
      body: { $: "PanicExpr", message: "unused row" },
    }],
  });
  const artifact = compile(source, { const_steps: 7n });
  equal(artifact.analysis.remaining_steps, 0n);
  equal(artifact.analysis.constants[0].value, { $: "U32Value", value: 42 });
  const instance = new WebAssembly.Instance(
    new WebAssembly.Module(artifact.bytes),
  );
  const answer = instance.exports.answer;
  ok(typeof answer === "function");
  equal(answer(0), 42);
  throws(
    () => analyze(source, { const_steps: 6n }),
    (error) => error instanceof CompilerError && error.code === "const_budget",
  );
});

Deno.test("a return from an earlier match column skips later columns and arms", () => {
  const source = executable({
    $: "BlockExpr",
    label: 70n,
    body: {
      $: "MatchExpr",
      values: [{
        $: "ReturnExpr",
        label: 70n,
        value: { $: "U32Expr", value: 42 },
      }, { $: "PanicExpr", message: "later column" }],
      arms: [{
        patterns: [{ $: "WildcardPattern" }, { $: "WildcardPattern" }],
        body: { $: "PanicExpr", message: "later arm" },
      }],
    },
  });
  const artifact = compile(source, { const_steps: 4n });
  equal(artifact.analysis.remaining_steps, 0n);
  equal(artifact.analysis.constants[0].value, { $: "U32Value", value: 42 });
  const instance = new WebAssembly.Instance(
    new WebAssembly.Module(artifact.bytes),
  );
  const answer = instance.exports.answer;
  ok(typeof answer === "function");
  equal(answer(0), 42);
});

Deno.test("a later returning column makes an empty pattern matrix unreachable", () => {
  const source = executable({
    $: "BlockExpr",
    label: 71n,
    body: {
      $: "MatchExpr",
      values: [{ $: "U32Expr", value: 1 }, {
        $: "ReturnExpr",
        label: 71n,
        value: { $: "U32Expr", value: 42 },
      }],
      arms: [],
    },
  });
  const artifact = compile(source, { const_steps: 5n });
  equal(artifact.analysis.remaining_steps, 0n);
  equal(artifact.analysis.constants[0].value, { $: "U32Value", value: 42 });
  const instance = new WebAssembly.Instance(
    new WebAssembly.Module(artifact.bytes),
  );
  const answer = instance.exports.answer;
  ok(typeof answer === "function");
  equal(answer(0), 42);
});

Deno.test("descriptor equality distinguishes same-spelled operations from different modules", () => {
  const left: TypeId = {
    $: "TypeId",
    module_name: "left/module",
    declaration: "Reader.ask",
  };
  const right: TypeId = { ...left, module_name: "right/module" };
  const invoke = (identity: TypeId): Expr => ({
    $: "ApplyExpr",
    callee: { $: "OperationExpr", identity },
    argument: { $: "UnitExpr" },
  });
  const requirements: Expr = { $: "FunctionEffectsExpr", callee: "read_both" };
  const source: CoreModule = {
    operations: [left, right].map((identity) => ({
      identity,
      parameter: { $: "UnitTy" },
      result: { $: "U32Ty" },
    })),
    functions: [{
      name: "read_both",
      exported: false,
      parameter: "_",
      parameter_type: { $: "UnitTy" },
      result_type: { $: "U32Ty" },
      body: {
        $: "ScalarExpr",
        operator: { $: "Add" },
        left: invoke(left),
        right: invoke(right),
      },
    }],
    constants: ([
      ["same", {
        $: "EffectSameExpr",
        left: { $: "OperationDescriptorExpr", identity: left },
        right: { $: "OperationDescriptorExpr", identity: right },
      }],
      ["count", { $: "EffectCountExpr", set: requirements }],
      ["left", {
        $: "EffectHasExpr",
        set: requirements,
        operation: { $: "OperationDescriptorExpr", identity: left },
      }],
      ["right", {
        $: "EffectHasExpr",
        set: requirements,
        operation: { $: "OperationDescriptorExpr", identity: right },
      }],
    ] satisfies readonly (readonly [string, Expr])[]).map(([name, value]) => ({
      name,
      value,
      exported: false,
      annotation: null,
    })),
  };
  equal(analyze(source).constants, [
    { name: "same", value: { $: "BoolValue", value: false } },
    { name: "count", value: { $: "U32Value", value: 2 } },
    { name: "left", value: { $: "BoolValue", value: true } },
    { name: "right", value: { $: "BoolValue", value: true } },
  ]);
});
