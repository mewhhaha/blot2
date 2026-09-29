import {
  deepStrictEqual as equal,
  ok,
  rejects,
  throws,
} from "node:assert/strict";
import { createSourceCompiler } from "./source.ts";
import { createNativeCompiler } from "./native.ts";
import { createIncrementalCompiler } from "./incremental.ts";
import { createNativeIncrementalCompiler } from "./native_incremental.ts";
import { instantiateGuest } from "./guest.ts";
import { SourceError } from "./syntax.ts";

const programs = [
  {
    name: "unnamed ranges, explicit iterator bindings, and unbounded loops",
    source: `
entry const run = fn () => do:
  let total = 0
  for 0..5:
    total := self + 1
  for let value in [2, 3]:
    total := self + value
  for ever:
    total := self + 1
    if total == 13:
      return total
`,
    exports: [["run", 13]],
  },
  {
    name: "ranges carry immutable successors in const evaluation and Wasm",
    source: `
entry const sum = fn limit => do:
  let total = 0
  for index in 0..limit:
    total := self + index
  return total
entry const folded = sum 10
entry const run = fn (limit: U32) => sum limit
entry const reversed = fn () => do:
  let total = 42
  for index in 9..2:
    total := self + index
  return total
entry const maximum = fn () => do:
  let total = 0
  for index in 4294967294..4294967295:
    total := self + 1
  return total
`,
    exports: [["folded", 45], ["run", 45, 10], ["reversed", 42], [
      "maximum",
      1,
    ]],
  },
  {
    name: "array loops destructure elements and specialize generic arithmetic",
    source: `
const total = fn values => do:
  let sum = @array.get values 0
  for index in 1..(@array.length values):
    sum := self + @array.get values index
  return sum
entry const folded = total [1.5, 2.5, 3.0]
entry const run = fn () => do:
  let count = 0
  let sum = 0.0
  for (amount, weight) in [(2, 1.5), (3, 2.0)]:
    count := self + amount
    sum := self + U32.to_f32 amount * weight
  return U32.to_f32 count + sum + total [1.0, 2.0]
entry const integers = fn () => total [10, 20, 12]
`,
    exports: [["folded", 7], ["run", 17], ["integers", 42]],
  },
  {
    name: "nested loops preserve lexical scope and captured iteration values",
    source: `
entry const run = fn () => do:
  let total = 0
  for row in 0..3:
    for column in 0..4:
      total := self + row * 10 + column
  return total
entry const captured = fn () => do:
  let callbacks = @array.fill 3 (fn () => 0)
  for index in 0..3:
    callbacks := @array.set self index (fn () => index)
  return (@array.get callbacks 0) () * 100 + (@array.get callbacks 1) () * 10 + (@array.get callbacks 2) ()
entry const scoped = fn () => do:
  let total = 42
  for index in [1, 2]:
    let total = index
    total := self + 1
  return total
entry const shadow_after_successor = fn () => do:
  let total = 0
  for index in 0..3:
    total := self + 1
    let total = 99
    total := self + 1
  return total
entry const nested_do = fn () => do:
  let total = 0
  for index in 0..3:
    let amount = do:
      return index + 1
    total := self + amount
  return total
`,
    exports: [["run", 138], ["captured", 12], ["scoped", 42], [
      "shadow_after_successor",
      3,
    ], ["nested_do", 6]],
  },
  {
    name: "return inside for exits the enclosing do block",
    source: `
entry const first = fn values => do:
  for value in values:
    if value > 10:
      return value
  return 0
entry const folded = first [1, 42, 99]
entry const run = fn () => first [2, 12, 42]
entry const empty = fn () => first []
entry const nested = fn () => do:
  for outer in 0..4:
    for inner in 0..3:
      if outer + inner == 3:
        return outer * 10 + inner
  return 99
`,
    exports: [["folded", 42], ["run", 12], ["empty", 0], ["nested", 12]],
  },
] as const;

async function exercise(
  bytes: Uint8Array<ArrayBuffer>,
  expected: readonly (readonly [string, number, number?])[],
) {
  const { instance } = await WebAssembly.instantiate(bytes);
  for (const [name, value, argument] of expected) {
    const exported = instance.exports[name];
    equal(
      exported instanceof WebAssembly.Global
        ? exported.value
        : (exported as CallableFunction)(argument),
      value,
      name,
    );
  }
}

for (const program of programs) {
  Deno.test(`for loops: ${program.name}`, async () => {
    const compiler = await createSourceCompiler();
    try {
      const artifact = compiler.compile(program.source);
      await exercise(artifact.bytes, program.exports);
    } finally {
      compiler.dispose();
    }
  });
}

Deno.test("for loops evaluate range bounds and array expressions once and preserve effect order", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(`
effect Read : U32 -> U32
const numbers = fn () => do:
  use value <- Read 4
  return [value, value + 1]
entry const run = fn (probe: U32 -> U32 ! {Foreign}) => do (@effect.provider Read probe):
  for index in (Read 0)..(Read 3):
    use Read (index + 10)
  for value in (numbers ()):
    use Read (value + 20)
  return 42
`);
    const guest = await instantiateGuest(artifact.bytes);
    try {
      const observed: number[] = [];
      const probe = guest.capability({
        parameter: "U32",
        result: "U32",
        call: (value) => {
          observed.push(value);
          return value;
        },
      });
      equal(guest.call("run", probe), 42);
      equal(observed, [0, 3, 10, 11, 12, 4, 24, 25]);
    } finally {
      guest.dispose();
    }
  } finally {
    compiler.dispose();
  }
});

Deno.test("for loops use constant stack and enforce the const step budget", async () => {
  const compiler = await createSourceCompiler();
  try {
    const source = `
entry const sum = fn limit => do:
  let total = 0
  for index in 0..limit:
    total := @u32.add self index
  return total
entry const run = fn () => sum 100000
`;
    await exercise(compiler.compile(source).bytes, [["run", 704982704]]);
    throws(
      () =>
        compiler.compile(source + "\nentry const costly = sum 100000", {
          const_steps: 50n,
        }),
      (error: unknown) => {
        ok(error instanceof SourceError);
        equal(error.code, "const_budget");
        return true;
      },
    );
  } finally {
    compiler.dispose();
  }
});

const invalidPrograms = [
  ["for index in 0.0..3:", "type_mismatch"],
  ["for index in 0..#False:", "type_mismatch"],
  ["for index in 3:", "type_mismatch"],
  ["for (a, b) in [1]:", "type_mismatch"],
] as const;

Deno.test("for loops reject invalid iterables, bounds, escaping locals and state type changes", async () => {
  const compiler = await createSourceCompiler();
  try {
    const cases = [
      ...invalidPrograms.map((
        [loop, code],
      ) => [
        `entry const run = fn () => do:\n  ${loop}\n    use ()\n  return 0`,
        code,
      ]),
      [
        "entry const run = fn () => do:\n  for index in 0..3:\n    use ()\n  return index",
        "unknown_value",
      ],
      [
        "entry const run = fn () => do:\n  let total = 0\n  for index in 0..3:\n    total := #True\n  return total",
        "type_mismatch",
      ],
    ];
    for (const [source, code] of cases) {
      throws(() => compiler.compile(source), (error: unknown) => {
        ok(error instanceof SourceError, String(error));
        equal(error.code, code, error.message);
        return true;
      });
    }
  } finally {
    compiler.dispose();
  }
});

Deno.test("for loops update JavaScript incremental caches after bound changes", async () => {
  const compiler = await createIncrementalCompiler();
  try {
    for (const endpoint of [3, 5, 1]) {
      const source =
        `entry const run = fn () => do:\n  let total = 0\n  for index in 0..${endpoint}:\n    total := self + index\n  return total`;
      const result = await compiler.compile(source);
      await exercise(result.artifact.bytes, [[
        "run",
        endpoint * (endpoint - 1) / 2,
      ]]);
    }
  } finally {
    await compiler.dispose();
  }
});

Deno.test("for loops retain native compiler and incremental cache parity", async () => {
  const js = await createSourceCompiler();
  const native = await createNativeCompiler();
  const incremental = await createIncrementalCompiler();
  const nativeIncremental = await createNativeIncrementalCompiler();
  try {
    for (const program of programs) {
      equal(await native.compile(program.source), js.compile(program.source));
    }
    for (const endpoint of [3, 5, 1]) {
      const source =
        `entry const run = fn () => do:\n  let total = 0\n  for index in 0..${endpoint}:\n    total := self + index\n  return total`;
      const expected = await incremental.compile(source);
      const actual = await nativeIncremental.compile(source);
      equal(actual.artifact, expected.artifact);
      await exercise(actual.artifact.bytes, [[
        "run",
        endpoint * (endpoint - 1) / 2,
      ]]);
    }
    await rejects(
      native.compile(
        "entry const run = fn () => do:\n  for index in 0.0..3:\n    use ()\n  return 0",
      ),
      (error: unknown) => {
        ok(error instanceof SourceError);
        equal(error.code, "type_mismatch");
        return true;
      },
    );
  } finally {
    js.dispose();
    await native.dispose();
    await incremental.dispose();
    await nativeIncremental.dispose();
  }
});
