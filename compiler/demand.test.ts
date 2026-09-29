import {
  deepStrictEqual as equal,
  ok,
  rejects,
  throws,
} from "node:assert/strict";
import { createNativeCompiler } from "./native.ts";
import { createNativeIncrementalCompiler } from "./native_incremental.ts";
import { createSourceCompiler } from "./source.ts";
import { SourceError } from "./syntax.ts";

export const demandProgram = `
effect Counter.read: Unit -> U32
effect Counter.write: U32 -> Unit
const increment = fn () => do:
  use previous <- Counter.read ()
  use Counter.write (previous + 1)
  return previous
const twice = fn ~value => do:
  use first <- @force value
  use second <- @force value
  return first + second
const keep = fn ~value => fn () => @force value
const ignore = fn ~value => 42
const identity = fn value => value
const alias = identity twice
const selected_and = and #True
const call_lazy = fn (callback: ~U32 -> U32) => callback (20 + 1)
const pure_twice = fn ~(value: U32) => @force value + @force value
entry const higher_order = fn () => call_lazy pure_twice
entry const memoized = fn () => do:
  let (count, result) = do (@effect.state Counter.read Counter.write 20):
    return alias (increment ())
  return count + result
entry const expected = memoized ()
entry const skipped = ignore (@panic "unused demand")
entry const short_circuit = fn enabled =>
  (#False && (@panic "and forced")) || (#True || (@panic "or forced")) && selected_and enabled
entry const demand_alias = fn enabled => (identity and) enabled (@panic "alias forced")
entry const recovered = fn () => Maybe.unwrap_or_else (@panic "fallback forced") (#Some 42)
entry const escaping = fn () => do:
  let delayed = keep (20 + 1)
  return delayed () + delayed ()
const shared = keep (20 + 1)
entry const static_escape = fn () => shared () + shared ()
entry const escaped_effect = fn () => do:
  let delayed = keep (increment ())
  let (count, result) = do (@effect.state Counter.read Counter.write 20):
    use first <- delayed ()
    use second <- delayed ()
    return first + second
  return count + result
const shared_counter = keep (increment ())
const counter_alias = shared_counter
entry const global_aliases = fn () => do:
  let (count, result) = do (@effect.state Counter.read Counter.write 20):
    use first <- shared_counter ()
    use second <- counter_alias ()
    return first + second
  return count + result
const shared_array = keep [40, 2]
entry const array_sum = fn () => do:
  let values = shared_array ()
  return values[0] + values[1]
entry const changed_copy = fn () => do:
  let values = shared_array ()
  values[0] := 0
  return values[0] + (shared_array ())[0]
entry const skipped_effect = fn () => ignore (increment ())
`;

for (const backend of ["javascript", "native"] as const) {
  Deno.test(`${backend}: demand parameters skip work, memoize effects, and survive aliases and escaping closures`, async () => {
    const compiler = backend === "native"
      ? await createNativeCompiler()
      : await createSourceCompiler();
    try {
      const artifact = await compiler.compile(demandProgram);
      const { instance } = await WebAssembly.instantiate(artifact.bytes);
      const call = (name: string, value = 0) => {
        const fn = instance.exports[name];
        ok(typeof fn === "function", name);
        return fn(value);
      };
      equal((instance.exports.expected as WebAssembly.Global).value, 61);
      equal((instance.exports.skipped as WebAssembly.Global).value, 42);
      equal(call("memoized"), 61);
      equal(call("higher_order"), 42);
      equal(call("short_circuit", 0), 0);
      equal(call("short_circuit", 1), 1);
      equal(call("demand_alias", 0), 0);
      throws(() => call("demand_alias", 1), WebAssembly.RuntimeError);
      equal(call("recovered"), 42);
      equal(call("escaping"), 42);
      equal(call("static_escape"), 42);
      equal(call("escaped_effect"), 61);
      equal(call("skipped_effect"), 42);
      equal(call("global_aliases"), 61);
      equal(call("global_aliases"), 60);
      equal(call("array_sum"), 42);
      equal(call("changed_copy"), 40);
      // Subsequent calls may allocate and reset the arena; the cached array lives.
      for (let index = 0; index < 8; index++) {
        equal(call("escaping"), 42);
        equal(call("array_sum"), 42);
      }
      await rejects(async () =>
        await compiler.compile(`
effect Read: Unit -> U32
const force = fn ~value => @force value
entry const invalid: Unit -> U32 = fn () => force (Read ())
`), (error) => {
        ok(error instanceof SourceError);
        ok(/effect|row/.test(error.message), error.message);
        return true;
      });
    } finally {
      await compiler.dispose();
    }
  });
}

Deno.test("native demand caches match fresh compilation after edits to suspended constants", async () => {
  const reference = await createSourceCompiler();
  const incremental = await createNativeIncrementalCompiler();
  try {
    for (const amount of [40, 41, 42]) {
      const source = `
const keep = fn ~value => fn () => @force value
const saved = keep [${amount}, 2]
const alias = saved
entry const read = fn () => do:
  let first = saved ()
  let second = alias ()
  return first[0] + second[1]
entry const selected = #True && (${amount} < 42)
`;
      const expected = reference.compile(source);
      const actual = await incremental.compile(source);
      equal(actual.artifact.bytes, expected.bytes);
      const { instance } = await WebAssembly.instantiate(actual.artifact.bytes);
      equal((instance.exports.read as CallableFunction)(), amount + 2);
      equal((instance.exports.read as CallableFunction)(), amount + 2);
      equal(
        (instance.exports.selected as WebAssembly.Global).value,
        amount < 42 ? 1 : 0,
      );
    }
  } finally {
    reference.dispose();
    await incremental.dispose();
  }
});
