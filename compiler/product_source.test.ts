import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import { createNativeCompiler } from "./native.ts";
import { createSourceCompiler } from "./source.ts";
import { SourceError } from "./syntax.ts";

Deno.test("source tuples retain heterogeneous fields through annotations, ADTs, and closures", async () => {
  const source = `data Payload = Payload (U32, Bool)
fn first (pair: (U32, Bool)) => @product.get pair 0
fn unwrap value => case value of
  Payload pair => first pair
const stored = Payload (40, True)
export const expected = unwrap stored + 2
export fn answer () => do:
  let captured = (unwrap stored, False)
  let select = fn () => first captured
  return select () + 2
`;
  const js = await createSourceCompiler();
  const native = await createNativeCompiler();
  try {
    const expected = js.compile(source);
    const actual = await native.compile(source);
    equal(actual, expected);
    const { instance } = await WebAssembly.instantiate(actual.bytes);
    equal((instance.exports.expected as WebAssembly.Global).value, 42);
    equal((instance.exports.answer as CallableFunction)(), 42);
  } finally {
    js.dispose();
    await native.dispose();
  }
});

Deno.test("source projection reports unknown shapes and requires an in-bounds literal index", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    for (
      const [source, code] of [
        ["fn read value => @product.get value 0\n", "unknown_product_shape"],
        ["fn read () => @product.get (1, True) 2\n", "product_index"],
        [
          "fn read index => @product.get (1, True) index\n",
          "product_index_literal",
        ],
      ]
    ) {
      throws(() => compiler.compile(source), (error) => {
        ok(error instanceof SourceError, String(error));
        equal(error.code, code, error.message);
        return true;
      });
    }
  } finally {
    compiler.dispose();
  }
});
