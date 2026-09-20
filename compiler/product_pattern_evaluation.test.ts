import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { bendArray, type BendList, bendList } from "./bend_list.ts";
import {
  analyze,
  compile,
  CompilerError,
  type Expr,
  type Pattern,
} from "./host.ts";
import { add, fn, integer, local, module, unit } from "./fixtures.ts";

type RawMatch =
  | {
    readonly $: "Done";
    readonly value: { readonly $: "None" } | {
      readonly $: "Some";
      readonly value: BendList<
        { readonly name: string; readonly value: unknown }
      >;
    };
  }
  | {
    readonly $: "Fail";
    readonly error: { readonly code: string };
  };
const evaluator = compiled as unknown as {
  "const_eval.match_pattern"(pattern: unknown, value: unknown): RawMatch;
  "const_eval.match_pattern_work"(fuel: bigint, work: unknown): RawMatch;
};

const product = (...elements: Expr[]): Expr => ({ $: "ProductExpr", elements });
const tuple = (...elements: Pattern[]): Pattern => ({
  $: "ProductPattern",
  elements,
});
const binding = (name: string): Pattern => ({ $: "BindingPattern", name });
const wildcard: Pattern = { $: "WildcardPattern" };
const matching = (value: Expr, pattern: Pattern, body: Expr): Expr => ({
  $: "MatchExpr",
  values: [value],
  arms: [{ patterns: [pattern], body }],
});
const constant = (value: Expr) =>
  module([], {
    constants: [{ name: "answer", exported: false, annotation: null, value }],
  });

Deno.test("tuple patterns bind nested fields without charging expression fuel twice", () => {
  const value = matching(
    product(integer(40), product({ $: "BoolExpr", value: true }, integer(2))),
    tuple(binding("left"), tuple(wildcard, binding("right"))),
    add(local("left"), local("right")),
  );
  const result = analyze(constant(value), { const_steps: 9n });
  equal(result.constants[0].value, { $: "U32Value", value: 42 });
  equal(result.remaining_steps, 0n);
  throws(
    () => analyze(constant(value), { const_steps: 8n }),
    (error) => error instanceof CompilerError && error.code === "const_budget",
  );
});

Deno.test("a failed tuple guard never publishes partially matched bindings", () => {
  for (const accepted of [true, false]) {
    const value: Expr = {
      $: "LetExpr",
      name: "value",
      value: integer(7),
      body: {
        $: "BlockExpr",
        label: 601n,
        body: {
          $: "GuardExpr",
          pattern: tuple(binding("value"), { $: "BoolPattern", value: true }),
          value: product(integer(42), { $: "BoolExpr", value: accepted }),
          alternative: { $: "ReturnExpr", label: 601n, value: local("value") },
          body: local("value"),
        },
      },
    };
    equal(analyze(constant(value)).constants[0].value, {
      $: "U32Value",
      value: accepted ? 42 : 7,
    });
  }
});

Deno.test("const tuple bindings remain captured by escaping runtime closures", async () => {
  const source = module([fn("entry", {
    $: "ApplyExpr",
    callee: { $: "ConstantExpr", name: "saved" },
    argument: unit,
  })], {
    constants: [{
      name: "saved",
      exported: false,
      annotation: null,
      value: matching(
        product(integer(40), integer(2)),
        tuple(binding("first"), binding("second")),
        {
          $: "LambdaExpr",
          identity: 602n,
          parameter: "unused",
          parameter_type: null,
          result_type: null,
          body: add(local("first"), local("second")),
        },
      ),
    }],
  });
  const artifact = compile(source);
  const captured = artifact.analysis.constants[0].value;
  ok(captured.$ === "ClosureValue");
  equal(captured.environment.map((entry) => entry.name).sort(), [
    "first",
    "second",
  ]);
  const { instance } = await WebAssembly.instantiate(artifact.bytes);
  equal((instance.exports.entry as CallableFunction)(), 42);
});

Deno.test("tuple patterns reject malformed arity and duplicate nested bindings", () => {
  for (
    const [pattern, code] of [
      [tuple(), "product_arity"],
      [tuple(wildcard), "product_arity"],
      [tuple(wildcard, wildcard, wildcard), "product_arity"],
      [tuple(binding("same"), binding("same")), "duplicate_pattern_binding"],
    ] as const
  ) {
    throws(
      () =>
        analyze(
          constant(
            matching(product(integer(1), integer(2)), pattern, integer(42)),
          ),
        ),
      (error) => error instanceof CompilerError && error.code === code,
    );
  }
});

Deno.test("const tuple matching handles 8192 fields and preserves binding order without host recursion", () => {
  const width = 8192;
  const value = {
    $: "ProductValue",
    elements: bendList(Array.from({ length: width }, (_, value) => ({
      $: "U32Value",
      value,
    }))),
  };
  equal(
    evaluator["const_eval.match_pattern"]({
      $: "ProductPattern",
      elements: bendList(Array.from({ length: width }, () => ({
        $: "WildcardPattern",
      }))),
    }, value),
    { $: "Done", value: { $: "Some", value: { $: "Nil" } } },
  );

  const matched = evaluator["const_eval.match_pattern"]({
    $: "ProductPattern",
    elements: bendList(Array.from({ length: width }, (_, index) => ({
      $: "BindingPattern",
      name: `field_${index}`,
    }))),
  }, value);
  ok(matched.$ === "Done" && matched.value.$ === "Some");
  const bindings = bendArray(matched.value.value);
  equal(bindings.length, width);
  for (const [index, binding] of bindings.entries()) {
    equal(binding.name, `field_${index}`);
    equal(binding.value, { $: "U32Value", value: index });
  }
});

Deno.test("const tuple matching reports traversal exhaustion and stops at the first failed field", () => {
  const work = {
    $: "PatternValue",
    pattern: {
      $: "ProductPattern",
      elements: bendList([
        { $: "U32Pattern", value: 1 },
        { $: "WildcardPattern" },
      ]),
    },
    value: {
      $: "ProductValue",
      elements: bendList([
        { $: "U32Value", value: 1 },
        { $: "U32Value", value: 2 },
      ]),
    },
  };
  for (const fuel of [0n, 3n, 5n]) {
    const exhausted = evaluator["const_eval.match_pattern_work"](fuel, work);
    ok(exhausted.$ === "Fail");
    equal(exhausted.error.code, "pattern_complexity");
  }
  equal(evaluator["const_eval.match_pattern_work"](6n, work), {
    $: "Done",
    value: { $: "Some", value: { $: "Nil" } },
  });
  equal(
    evaluator["const_eval.match_pattern_work"](3n, {
      ...work,
      value: {
        $: "ProductValue",
        elements: bendList([
          { $: "U32Value", value: 0 },
          { $: "U32Value", value: 2 },
        ]),
      },
    }),
    { $: "Done", value: { $: "None" } },
  );
});
