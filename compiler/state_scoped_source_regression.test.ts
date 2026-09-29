import { ok, strictEqual as equal } from "node:assert/strict";
import { createSourceCompiler } from "./source.ts";

const source = `
type Cell a is effect = {
  get: Unit -> a
  set: a -> Unit
}
type Box a is data = #Box a

const get = fn (witness: p -> a) -> a => Cell.get ()
const set = fn value => Cell.set value
const run = fn initial => fn action => @effect.run Cell.get Cell.set initial action

entry const nested_reader_writer = fn () => do:
  let (#Box written, result) = run (#Box 0) (fn () =>
    @effect.reader Cell.get (fn () => #Box 0) (fn () => #Box 7) (fn () => do:
      use boxed <- get (fn () => #Box 0)
      let #Box count = boxed
      return @effect.writer Cell.set (fn () => #Box 0) (fn value => set value) (fn () => do:
        use set (#Box (@u32.add count 1))
        return count)))
  return @u32.add written result
`;

Deno.test("nested family reader and writer retain their residual operation rows", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    const artifact = compiler.compile(source);
    ok(WebAssembly.validate(artifact.bytes));
    const exports = new WebAssembly.Instance(
      new WebAssembly.Module(artifact.bytes),
    ).exports;
    equal((exports.nested_reader_writer as CallableFunction)(0), 15);
  } finally {
    compiler.dispose();
  }
});
