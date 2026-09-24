import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import { createSourceCompiler } from "./source.ts";
import { createNativeCompiler } from "./native.ts";
import { SourceError } from "./syntax.ts";

const programs = [
  {
    name: "state providers preserve floating point state values",
    source: `
effect Value.read: Unit -> F32
effect Value.write: F32 -> Unit
const answer = fn () => do:
  let (next, previous) = do (@effect.state Value.read Value.write 1.25):
    use value <- Value.read ()
    use Value.write (@f32.add value 2.5)
    return value
  return @f32.add next previous
const run = fn () => answer ()
const expected = answer ()
`,
    expected: 5,
  },
  {
    name: "state providers return successor state and result in const and Wasm",
    source: `
effect Counter.read: Unit -> U32
effect Counter.write: U32 -> Unit
const counter = @effect.state Counter.read Counter.write 10
const increment = fn () => do:
  use value <- Counter.read ()
  use Counter.write (@u32.add value 1)
  return value
const twice = fn action => do:
  use first <- action ()
  use second <- action ()
  return @u32.add first second
const answer = fn () => do:
  let (next, total) = do counter:
    return twice increment
  return @u32.add next total
const run = fn () => answer ()
const expected = answer ()
`,
    expected: 33,
  },
  {
    name: "nested state scopes shadow and forward unrelated operations",
    source: `
effect Counter.read: Unit -> U32
effect Counter.write: U32 -> Unit
effect Other.read: Unit -> U32
effect Other.write: U32 -> Unit
const answer = fn () => do:
  let (outer, (other, inner)) = do (@effect.state Counter.read Counter.write 10):
    return do (@effect.state Other.read Other.write 20):
      use nested_result <- do (@effect.state Counter.read Counter.write 1):
        use current <- Counter.read ()
        use Counter.write (@u32.add current 1)
        use previous <- Other.read ()
        use Other.write (@u32.add previous 3)
        return previous
      let (nested, observed) = nested_result
      use current <- Counter.read ()
      use Counter.write (@u32.add current 4)
      return @u32.add nested observed
  return @u32.add outer (@u32.add other inner)
const run = fn () => answer ()
const expected = answer ()
`,
    expected: 59,
  },
  {
    name: "state providers compose with ordinary forwarding providers",
    source: `
effect Counter.read: Unit -> U32
effect Counter.write: U32 -> Unit
effect Input.read: Unit -> U32
const doubled = fn () => do:
  use value <- Counter.read ()
  return @u32.mul value 2
const doubling = @effect.provider Counter.read doubled
const input = @effect.provider Input.read (fn () => 3)
const answer = fn () => do input:
  use completed <- do (@effect.state Counter.read Counter.write 5):
    use observed <- do doubling:
      use value <- Counter.read ()
      use amount <- Input.read ()
      use Counter.write (@u32.add value amount)
      return value
    use current <- Counter.read ()
    return @u32.add current observed
  let (state, result) = completed
  return @u32.add state result
const run = fn () => answer ()
const expected = answer ()
`,
    expected: 36,
  },
  {
    name: "state writes preserve old arrays and reusable provider defaults",
    source: `
effect Values.read: Unit -> Array U32
effect Values.write: Array U32 -> Unit
const original = [10, 20]
const values = @effect.state Values.read Values.write original
const replace = fn () => do:
  use before <- Values.read ()
  use Values.write (@array.set before 0 99)
  return @array.get before 0
const answer = fn () => do:
  let (next, before) = do values:
    return replace ()
  let (fresh, ignored) = do values:
    return ()
  return @u32.add (@array.get next 0) (@u32.add before (@array.get fresh 0))
const run = fn () => answer ()
const expected = answer ()
`,
    expected: 119,
  },
  {
    name: "loops thread state and escaping closures use their call scope",
    source: `
effect Counter.read: Unit -> U32
effect Counter.write: U32 -> Unit
const answer = fn () => do:
  let (ignored, delayed) = do (@effect.state Counter.read Counter.write 999):
    return fn () => Counter.read ()
  let (next, result) = do (@effect.state Counter.read Counter.write 1):
    for index in 0..4:
      use value <- Counter.read ()
      use Counter.write (@u32.add value index)
    return delayed ()
  return @u32.add next result
const run = fn () => answer ()
const expected = answer ()
`,
    expected: 14,
  },
];

for (const program of programs) {
  Deno.test(program.name, async () => {
    const compiler = await createSourceCompiler({ prelude: "none" });
    try {
      const artifact = compiler.compile(program.source);
      ok(WebAssembly.validate(artifact.bytes));
      const { exports } = new WebAssembly.Instance(
        new WebAssembly.Module(artifact.bytes),
      );
      const run = exports.run;
      ok(typeof run === "function");
      equal(run(0), program.expected);
      equal(run(0), program.expected, "each scope must receive fresh state");
      const expected = exports.expected;
      ok(expected instanceof WebAssembly.Global);
      equal(expected.value, program.expected);
    } finally {
      compiler.dispose();
    }
  });
}

Deno.test("state providers reject invalid operation signatures and initializers", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    for (
      const [source, code] of [
        [
          `effect Read: U32 -> U32\neffect Write: U32 -> Unit\nconst provider = @effect.state Read Write 0`,
          "type_mismatch",
        ],
        [
          `effect Read: Unit -> U32\neffect Write: U32 -> U32\nconst provider = @effect.state Read Write 0`,
          "type_mismatch",
        ],
        [
          `effect Read: Unit -> U32\neffect Write: F32 -> Unit\nconst provider = @effect.state Read Write 0`,
          "type_mismatch",
        ],
        [
          `effect Read: Unit -> U32\neffect Write: U32 -> Unit\nconst provider = @effect.state Read Write 0.0`,
          "type_mismatch",
        ],
        [
          `effect Both: Unit -> Unit\nconst provider = @effect.state Both Both ()`,
          "invalid_state_provider",
        ],
        [
          `effect Read: Unit -> U32\neffect Write: U32 -> Unit\nconst run: Unit -> Unit = fn () => Write 3`,
          "effect_mismatch",
        ],
      ]
    ) {
      throws(() => compiler.compile(source), (error) => {
        ok(error instanceof SourceError, String(error));
        equal(error.code, code);
        return true;
      });
    }
  } finally {
    compiler.dispose();
  }
});

Deno.test("state resolvers have exact native and JavaScript parity", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  const native = await createNativeCompiler({ prelude: "none" });
  try {
    for (const program of programs) {
      equal(
        await native.compile(program.source),
        compiler.compile(program.source),
      );
    }
  } finally {
    compiler.dispose();
    await native.dispose();
  }
});
