import { deepStrictEqual as equal, rejects, throws } from "node:assert/strict";
import { createSourceCompiler } from "./source.ts";
import { createNativeCompiler } from "./native.ts";
import { instantiateGuest } from "./guest.ts";
import { SourceError } from "./syntax.ts";

const programs = [
  {
    name:
      "checked collection members and direct indexing work in constants and Wasm",
    source: `
entry const folded = [40, 42][1]
entry const run = fn () => do:
  let a = [40, 2]
  let Some first = a.get(0) else:
    return 0
  let Nothing = a.get(a.length) else:
    return 0
  let Nothing = a.set(4294967295)(99) else:
    return 0
  let Some changed = a.set(1)(42) else:
    return 0
  if 1 < changed.length:
    return changed[1]
  return 0
entry const precedence = fn () => do:
  let sum = fn a => fn b => a + b
  let identity = fn a => a
  return sum identity([40])[0] [2][0]
entry const empty = fn () => do:
  let a: Array U32 = []
  return a.is_empty
`,
    calls: { run: 42, precedence: 42, empty: true },
  },
  {
    name:
      "nested array and record updates preserve aliases and bind self to the old leaf",
    source: `
type Grid a is data = Grid { rows: Array (Array a), count: U32 }
entry const run = fn () => do:
  let grid = Grid { rows: [[1, 2], [3, 4]], count: 0 }
  let old = grid
  let row = grid.rows[0]
  grid.rows[0][1] := self + 40
  grid.count := self + 1
  return old.rows[0][1] * 1000 + row[1] * 100 + grid.rows[0][1] + grid.count
entry const single = fn () => do:
  let pair = Pair { values: (40, 2) }
  let old = pair
  pair.values := (41, 1)
  let (a, b) = pair.values
  let (x, y) = old.values
  return a + b + x + y
type Pair is data = Pair { values: (U32, U32) }
entry const common = fn () => do:
  let count = High { value: 40, tag: 0 }
  count.value := self + 2
  return count.value
type Count is data = Low { value: U32 } | High { value: U32, tag: U32 }
`,
    calls: { run: 2243, single: 84, common: 42 },
  },
  {
    name:
      "array reuse preserves aliases, closures, parameters, and persistent globals",
    source: `
let persistent = [1, 2]
entry const change = fn values => do:
  values[0] := 42
  return values[0]
entry const run = fn () => do:
  let a = [1, 2]
  let old = a
  a[0] := 42
  return old[0] * 100 + a[0]
entry const capture = fn () => do:
  let a = [1, 2]
  let saved = fn () => a[0]
  a[0] := 42
  return saved() * 100 + a[0]
entry const repeated = fn () => do:
  let a = [0]
  a[0] := 40
  let old = a
  a[0] := self + 2
  return old[0] * 100 + a[0]
entry const parameter = fn () => do:
  let a = [1]
  let next = change(a)
  return a[0] * 100 + next
entry const global = fn () => do:
  let next = change(persistent)
  return persistent[0] * 100 + next
entry const loop_alias = fn () => do:
  let original = [1]
  let result = original
  for index in 0..3:
    result := @array.set original 0 (original[0] + 1)
  return original[0] * 100 + result[0]
`,
    calls: {
      run: 142,
      capture: 142,
      repeated: 4042,
      parameter: 142,
      global: 142,
      loop_alias: 102,
    },
  },
  {
    name:
      "consumed local arrays reuse storage across loops within the bounded guest heap",
    source: `
entry const run = fn () => do:
  let a = @array.fill 1024 0
  for index in 0..10000:
    a[0] := self + 1
  return a[0]
entry const unchanged = fn () => do:
  let a = [42]
  for index in 0..0:
    a[0] := 0
  return a[0]
`,
    calls: { run: 10000, unchanged: 42 },
  },
];

for (const { name, source, calls } of programs) {
  Deno.test(name, async () => {
    const js = await createSourceCompiler();
    const native = await createNativeCompiler({ threads: 8 });
    try {
      const artifact = js.compile(source);
      equal(await native.compile(source), artifact);
      const guest = await instantiateGuest(artifact.bytes);
      try {
        if (source.includes("const folded")) equal(guest.read("folded"), 42);
        for (const [entry, result] of Object.entries(calls)) {
          equal(guest.call(entry, null), result, entry);
          equal(guest.call(entry, null), result, `${entry} repeated call`);
        }
      } finally {
        guest.dispose();
      }
    } finally {
      js.dispose();
      await native.dispose();
    }
  });
}

Deno.test("direct indexing and updates retain bounds checks including overflowing indices", async () => {
  const source = `
entry const read = fn (index: U32) => [1, 2][index]
entry const update = fn (index: U32) => do:
  let a = [1, 2]
  a[index] := 42
  return a[0]
entry const empty = fn () => do:
  let a: Array U32 = []
  return a[0]
`;
  const js = await createSourceCompiler();
  const native = await createNativeCompiler();
  try {
    const artifact = js.compile(source);
    equal(await native.compile(source), artifact);
    const guest = await instantiateGuest(artifact.bytes);
    try {
      equal(guest.call("read", 1), 2);
      equal(guest.call("update", 0), 42);
      for (const index of [2, 4294967295]) {
        throws(() => guest.call("read", index), WebAssembly.RuntimeError);
        throws(() => guest.call("update", index), WebAssembly.RuntimeError);
      }
      throws(() => guest.call("empty", null), WebAssembly.RuntimeError);
    } finally {
      guest.dispose();
    }
    for (
      const [source, code] of [
        ["entry const invalid = [1][1]", "array_bounds"],
        ["const run = fn () => [1][0.0]", "type_mismatch"],
        ["const run = fn () => [1][]", "index_arity"],
        ["const run = fn () => [1][0, 1]", "index_arity"],
        [
          "entry const run = fn () => do:\n  missing[0] := 42\n  return 0",
          "unknown_rebinding",
        ],
      ] as const
    ) {
      const matches = (error: unknown) =>
        error instanceof SourceError && error.code === code;
      throws(() => js.compile(source), matches);
      await rejects(() => native.compile(source), matches);
    }
  } finally {
    js.dispose();
    await native.dispose();
  }
});

Deno.test("index adjacency survives incremental identities and invalidates spacing edits", async () => {
  const { createIncrementalCompiler } = await import("./incremental.ts");
  const { createNativeIncrementalCompiler } = await import(
    "./native_incremental.ts"
  );
  const js = await createIncrementalCompiler();
  const native = await createNativeIncrementalCompiler();
  const source = `const consume = fn values => values[0]
entry const run = fn () => consume [42]
`;
  try {
    for (const session of [js, native]) {
      for (const text of [source, source.replace("[42]", "[41]"), source]) {
        const { artifact } = await session.compile(text);
        const { instance } = await WebAssembly.instantiate(artifact.bytes);
        equal(
          (instance.exports.run as CallableFunction)(),
          text.includes("41") ? 41 : 42,
        );
      }
      await rejects(
        () => session.compile(source.replace("consume [", "consume[")),
        (error: unknown) =>
          error instanceof SourceError && error.code === "type_mismatch",
      );
      const { artifact } = await session.compile(source);
      const { instance } = await WebAssembly.instantiate(artifact.bytes);
      equal((instance.exports.run as CallableFunction)(), 42);
    }
  } finally {
    await js.dispose();
    await native.dispose();
  }
});
