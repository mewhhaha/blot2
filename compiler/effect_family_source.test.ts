import {
  deepStrictEqual as equal,
  ok,
  rejects,
  throws,
} from "node:assert/strict";
import { createNativeCompiler } from "./native.ts";
import { createSourceCompiler } from "./source.ts";
import { SourceError } from "./syntax.ts";

const source = `
type State a is effect = {
  get: Unit -> a
  set: a -> Unit
}
type Get a is effect = Unit -> a

entry const combined = fn () => do:
  let (count, (fraction, observed)) = do (@effect.state (State.get U32) (State.set U32) 40):
    return do (@effect.state (State.get F32) (State.set F32) 1.25):
      use old_count <- State.get U32 ()
      use old_fraction <- State.get F32 ()
      use State.set U32 (@u32.add old_count 2)
      use State.set F32 (@f32.add old_fraction 0.5)
      return @f32.add (@u32.to_f32 old_count) old_fraction
  return @f32.add (@u32.to_f32 count) (@f32.add fraction observed)

const integer_get = @effect.provider (Get U32) (fn () => 7)
const fraction_get = @effect.provider (Get F32) (fn () => 0.5)
entry const read_both = fn () => do integer_get:
  return do fraction_get:
    use integer <- Get U32 ()
    use fraction <- Get F32 ()
    return @f32.add (@u32.to_f32 integer) fraction

entry const state = fn () => combined ()
entry const state_at_compile_time = combined ()
entry const single = fn () => read_both ()
entry const single_at_compile_time = read_both ()
`;

Deno.test("effect families specialize grouped and single operations by type", async () => {
  const reference = await createSourceCompiler({ prelude: "none" });
  const native = await createNativeCompiler({ prelude: "none" });
  try {
    const artifact = reference.compile(source);
    equal(await native.compile(source), artifact);
    ok(WebAssembly.validate(artifact.bytes));
    const exports = new WebAssembly.Instance(
      new WebAssembly.Module(artifact.bytes),
    ).exports;
    const state = exports.state;
    const single = exports.single;
    const state_at_compile_time = exports.state_at_compile_time;
    const single_at_compile_time = exports.single_at_compile_time;
    ok(typeof state === "function");
    ok(typeof single === "function");
    ok(state_at_compile_time instanceof WebAssembly.Global);
    ok(single_at_compile_time instanceof WebAssembly.Global);
    equal(state(0), 85);
    equal(state_at_compile_time.value, 85);
    equal(single(0), 7.5);
    equal(single_at_compile_time.value, 7.5);
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("effect families reject incorrect type arity and duplicate members", async () => {
  const reference = await createSourceCompiler({ prelude: "none" });
  const native = await createNativeCompiler({ prelude: "none" });
  try {
    for (
      const [invalid, code] of [
        [
          `type Get a is effect = Unit -> a\nconst wrong = fn () => Get U32 F32 ()`,
          "type_arity",
        ],
        [
          `type State a is effect = {\n  get: Unit -> a\n  get: a -> Unit\n}`,
          "duplicate_name",
        ],
      ]
    ) {
      let expected: SourceError | undefined;
      throws(() => reference.compile(invalid), (error) => {
        ok(error instanceof SourceError, String(error));
        equal(error.code, code);
        expected = error;
        return true;
      });
      await rejects(() => native.compile(invalid), (error) => {
        ok(error instanceof SourceError, String(error));
        ok(expected);
        equal(
          [error.code, error.message, error.start, error.end],
          [expected.code, expected.message, expected.start, expected.end],
        );
        return true;
      });
    }
  } finally {
    reference.dispose();
    await native.dispose();
  }
});
