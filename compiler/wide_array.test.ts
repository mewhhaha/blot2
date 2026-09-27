import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import generated from "../generated/compiler/compiler.js";
import { toBendModel } from "./bend_abi.ts";
import { bendArray, type BendList, bendList } from "./bend_list.ts";
import { createSourceCompiler } from "./source.ts";
import { createNativeCompiler } from "./native.ts";

type Raw = { readonly $: string; readonly [field: string]: unknown };
type ReferenceResult =
  | {
    readonly $: "Done";
    readonly value: {
      readonly names: BendList<string>;
      readonly lambdas: BendList<bigint>;
    };
  }
  | { readonly $: "Fail"; readonly error: { readonly code: string } };
const backend = generated as unknown as {
  "dependency.references"(fuel: bigint, work: Raw): ReferenceResult;
};

Deno.test("8,192-element source arrays compile and execute with native/JS parity", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  const native = await createNativeCompiler({ prelude: "none" });
  try {
    const count = 8192;
    const literals = Array.from({ length: count }, (_, index) => index).join(
      ",",
    );
    const source = "entry const values = fn () => [" + literals +
      "]\nentry const answer = fn () => @array.get (values ()) 8191\nentry const at = fn (index: U32) => @array.get (values ()) index\nentry const count = fn () => @array.length (values ())\n";
    const artifact = await native.compile(source);
    equal(artifact, compiler.compile(source));
    ok(WebAssembly.validate(artifact.bytes));
    const instance = new WebAssembly.Instance(
      new WebAssembly.Module(artifact.bytes),
    );
    const exports = instance.exports as Record<
      string,
      (argument: number) => number
    >;
    equal(exports.answer(0), count - 1);
    equal(exports.count(0), count);
    for (const index of [0, 1, 127, 128, 4095, 4096, count - 1]) {
      equal(exports.at(index), index);
    }
    throws(() => exports.at(count), WebAssembly.RuntimeError);
  } finally {
    compiler.dispose();
    await native.dispose();
  }
});

Deno.test("wide dependency collection preserves call and lambda preorder exactly", () => {
  const count = 8192;
  const expressions: Raw[] = Array.from({ length: count }, (_, index) => ({
    $: "LambdaExpr",
    identity: BigInt(index),
    parameter: "unused",
    parameter_type: { $: "None" },
    result_type: { $: "None" },
    body: {
      $: "CallExpr",
      callee: "call_" + index,
      argument: { $: "FunctionExpr", name: "argument_" + index },
    },
  }));
  const result = backend["dependency.references"](65536n, {
    $: "dependency.Expression",
    value: toBendModel({ $: "ArrayExpr", elements: bendList(expressions) }),
  });
  ok(result.$ === "Done");
  equal(
    bendArray(result.value.names),
    expressions.flatMap((_, index) => [
      "call_" + index,
      "argument_" + index,
    ]),
  );
  equal(
    bendArray(result.value.lambdas),
    expressions.map((_, index) => BigInt(index)),
  );
  const enough = backend["dependency.references"](2n, {
    $: "dependency.Expressions",
    values: bendList(toBendModel([{ $: "FunctionExpr", name: "first" }])),
  });
  ok(enough.$ === "Done");
  equal(bendArray(enough.value.names), ["first"]);
  const exhausted = backend["dependency.references"](1n, {
    $: "dependency.Expressions",
    values: bendList(toBendModel([{ $: "FunctionExpr", name: "first" }])),
  });
  ok(exhausted.$ === "Fail");
  equal(exhausted.error.code, "expression_complexity");
});
