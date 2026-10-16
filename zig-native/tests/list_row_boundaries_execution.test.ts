import { strict as assert } from "node:assert";
import { compileAndRun } from "./compile_helpers.ts";

// Width seventeen exercises the boxed fallback beyond the packed admission limit.
Deno.test("whole-row List edits preserve source-ordered F32 folds and saved values at every width", async () => {
  const functions: string[] = [];
  const cases: { name: string; width: number }[] = [];
  for (const shape of ["record", "tuple"]) {
    let first = 1;
    if (shape === "tuple") first = 2;
    for (let width = first; width <= 17; width++) {
      const name = `${shape}_${width}`;
      cases.push({ name, width });
      const fields: string[] = [];
      const names: string[] = [];
      for (let field = 0; field < width; field++) {
        const value = `input[(i * ${width} + ${field}) % input.length]`;
        if (shape === "record") {
          fields.push(`f${field}: ${value}`);
          names.push(`row.f${field}`);
        } else {
          fields.push(value);
          names.push(`f${field}`);
        }
      }
      let row = `(${fields.join(", ")})`;
      let binding = `(${names.join(", ")})`;
      if (shape === "record") {
        row = `{${fields.join(", ")}}`;
        binding = "row";
      }
      let savedFirst = `let (first, ${
        Array.from({ length: width - 1 }, () => "_").join(", ")
      }) = @cursor.value cursor`;
      if (shape === "record") {
        savedFirst = "let first = (@cursor.value cursor).f0";
      }
      functions.push(`
const fold_${name} = fn values => do:
  let total = 0.0
  for ${binding} in values:
    total := self + ${names.join(" + ")}
  return total
entry const ${name} = fn (input: Array F32) => do:
  let original = @list.generate 600 (fn i => ${row})
  let saved = original
  let cursor = saved.iter
  let sentinel = @cursor.value cursor
  original := [sentinel, ...self, sentinel]
  let restored = @list.slice original 1 600
  let mixed = @list.slice restored 0 0
  for a in 0..6:
    for b in 0..8:
      mixed := @list.concat self (@list.slice restored (a * 47 + b * 5) (1 + a + b * 2))
  let before = mixed
  mixed := [sentinel, ...self, sentinel]
  mixed := @list.slice self 1 before.length
  let empty = @list.slice saved 0 0
  let short = @list.slice saved ${Math.floor(248 / width)} 2
  let prefix248 = @list.slice saved ${Math.floor(248 / width) - 1} ${
        Math.floor(248 / width) + 2
      }
  let prefix244 = @list.slice saved ${Math.floor(244 / width) - 1} ${
        Math.floor(244 / width) + 2
      }
  let result = #[fold_${name} mixed, fold_${name} before, fold_${name} saved, fold_${name} restored, fold_${name} short, fold_${name} empty, fold_${name} short, fold_${name} prefix248, fold_${name} prefix244]
  ${savedFirst}
  return #[...result, first]
`);
    }
  }
  const input = Float32Array.of(16777216, 0.125, -16777216, -0.25, 3.5, -0);
  await compileAndRun(functions.join("\n"), (guest) => {
    for (const { name, width } of cases) {
      const fold = (indices: number[]) => {
        let total = 0;
        for (const index of indices) {
          for (let field = 0; field < width; field++) {
            total = Math.fround(
              total + input[(index * width + field) % input.length],
            );
          }
        }
        return total;
      };
      const mixed: number[] = [];
      for (let a = 0; a < 6; a++) {
        for (let b = 0; b < 8; b++) {
          const start = a * 47 + b * 5;
          for (let offset = 0; offset < 1 + a + b * 2; offset++) {
            mixed.push(start + offset);
          }
        }
      }
      const all = Array.from({ length: 600 }, (_, i) => i);
      assert.deepEqual(
        guest.call(name, input),
        Float32Array.of(
          fold(mixed),
          fold(mixed),
          fold(all),
          fold(all),
          fold([Math.floor(248 / width), Math.floor(248 / width) + 1]),
          0,
          fold([Math.floor(248 / width), Math.floor(248 / width) + 1]),
          fold(
            Array.from(
              { length: Math.floor(248 / width) + 2 },
              (_, i) => Math.floor(248 / width) - 1 + i,
            ),
          ),
          fold(
            Array.from(
              { length: Math.floor(244 / width) + 2 },
              (_, i) => Math.floor(244 / width) - 1 + i,
            ),
          ),
          input[0],
        ),
      );
    }
  });
});

Deno.test("retained packed List directories survive reset and stay bounded across entries", async () => {
  const source = `
let rows = @list.generate 16384 (fn i => { a: @u32.to_f32 i, b: 0.125, c: -0.25, d: 3.5 })
entry const fold = fn (repeat: U32) => do:
  let total = 0.0
  for pass in 0..repeat:
    for row in rows:
      total := self + row.a + row.b + row.c + row.d
  return total
entry const unused = fn (seed: U32) => #[seed]
`;
  await compileAndRun(source, (guest) => {
    let expected = 0;
    for (let pass = 0; pass < 16; pass++) {
      for (let i = 0; i < 16384; i++) {
        for (const field of [i, 0.125, -0.25, 3.5]) {
          expected = Math.fround(expected + field);
        }
      }
    }
    assert.equal(guest.call("fold", 16), expected);
    const memory = guest.memoryBytes();
    for (let entry = 0; entry < 100; entry++) {
      assert.deepEqual(guest.call("unused", entry), Uint32Array.of(entry));
      assert.equal(guest.call("fold", 16), expected);
      assert.equal(guest.memoryBytes(), memory);
    }
  });
});

Deno.test("static packed List directories retain exact rows and bounded owners across entries", async () => {
  const source: string[] = [];
  const cases: { name: string; width: number }[] = [];
  for (const shape of ["record", "tuple"]) {
    let first = 1;
    if (shape === "tuple") first = 2;
    for (let width = first; width <= 16; width++) {
      const name = `${shape}_${width}`;
      cases.push({ name, width });
      const values = Array.from(
        { length: width },
        (_, field) => `@u32.to_f32 (@u32.add i ${field})`,
      );
      let row = `(${values.join(", ")})`;
      let binding = `(${
        Array.from({ length: width }, (_, field) => `f${field}`).join(", ")
      })`;
      let fields = Array.from({ length: width }, (_, field) => `f${field}`);
      if (shape === "record") {
        row = `{${
          values.map((value, field) => `f${field}: ${value}`).join(", ")
        }}`;
        binding = "row";
        fields = fields.map((field) => `row.${field}`);
      }
      source.push(`
const rows_${name} = @list.generate 300 (fn i => ${row})
entry const ${name} = fn (seed: F32) => do:
  let total = seed
  for ${binding} in rows_${name}:
    total := self + ${fields.join(" + ")}
  return total
`);
    }
  }
  source.push("entry const memory_probe = fn (seed: U32) => #[seed]");
  await compileAndRun(source.join("\n"), (guest, bytes) => {
    const ownership = WebAssembly.Module.customSections(
      new WebAssembly.Module(bytes),
      "blot:ownership",
    )[0];
    assert.deepEqual(Array.from(new Uint8Array(ownership)), [2, 2, 0]);
    const expected = new Map<string, number>();
    for (const { name, width } of cases) {
      let total = 16777216;
      for (let i = 0; i < 300; i++) {
        for (let field = 0; field < width; field++) {
          total = Math.fround(total + i + field);
        }
      }
      expected.set(name, total);
      assert.equal(guest.call(name, 16777216), total);
    }
    const warmed = guest.memoryBytes();
    for (let entry = 0; entry < 20; entry++) {
      assert.deepEqual(
        guest.call("memory_probe", entry),
        Uint32Array.of(entry),
      );
      for (const { name } of cases) {
        assert.equal(guest.call(name, 16777216), expected.get(name));
      }
      assert.equal(guest.memoryBytes(), warmed);
    }
  });
});

Deno.test("late static List traversal retains no unrelated pressure allocation", async () => {
  const source = `
const rows = @list.generate 600 (fn i => { a: @u32.to_f32 i, b: 0.125, c: -0.25, d: 3.5 })
let witness = @list.generate 600 (fn i => { a: i, b: i, c: i })
const read = fn (seed: F32) => do:
  let total = seed
  for row in rows:
    total := self + row.a + row.b + row.c + row.d
  return total
entry const pressure = fn (count: U32) => do:
  let unrelated = @array.generate count (fn i => i)
  let total = read (@u32.to_f32 count)
  return total + @u32.to_f32 unrelated[count - 1]
entry const witness_length = fn () => witness.length
entry const memory_probe = fn (seed: U32) => #[seed]
`;
  await compileAndRun(source, async (_guest, bytes) => {
    const module = new WebAssembly.Module(bytes);
    const ownership = new Uint8Array(
      WebAssembly.Module.customSections(module, "blot:ownership")[0],
    );
    const { exports } = await WebAssembly.instantiate(module);
    const memory = exports["blot:memory"] as WebAssembly.Memory;
    const reset = exports["blot:reset"] as (root: number) => number;
    const pressure = exports.pressure as (count: number) => number;
    const base = reset(0);
    const expected = (count: number) => {
      let total = count;
      for (let i = 0; i < 600; i++) {
        for (const value of [i, 0.125, -0.25, 3.5]) {
          total = Math.fround(total + value);
        }
      }
      return Math.fround(total + count - 1);
    };
    assert.equal(pressure(131072), expected(131072));
    const after = reset(0);
    // The tracing ABI's reset result is its base. Counted roots independently
    // reclaim pressure through their ordinary owner/collector path.
    if (ownership[1] === 0) assert.equal(after, base);
    const warmed = memory.buffer.byteLength;
    for (let entry = 0; entry < 100; entry++) {
      assert.equal(pressure(131072), expected(131072));
      const next = reset(0);
      if (ownership[1] === 0) assert.equal(next, base);
      assert.equal(memory.buffer.byteLength, warmed);
    }
  });
});

Deno.test("late dynamic slice and concat traversal retain no unrelated pressure allocation", async () => {
  for (
    const construction of [
      "@list.slice original 1 599",
      "@list.concat (@list.slice original 1 299) (@list.slice original 300 300)",
    ]
  ) {
    const source = `
let original = @list.generate 600 (fn i => { a: @u32.to_f32 i, b: 0.125, c: -0.25, d: 3.5 })
let rows = ${construction}
const read = fn (seed: F32) => do:
  let total = seed
  for row in rows:
    total := self + row.a + row.b + row.c + row.d
  return total
entry const rows_length = fn () => rows.length
entry const cursor_probe = fn (repeat: U32) => do:
  let cursor = rows.iter
  for i in 0..repeat:
    cursor := @cursor.advance self
  return (@cursor.value cursor).a
entry const pressure = fn (count: U32) => do:
  let unrelated = @array.generate count (fn i => i)
  let total = read (@u32.to_f32 count)
  return total + @u32.to_f32 unrelated[count - 1]
entry const memory_probe = fn (seed: U32) => #[seed]
`;
    await compileAndRun(source, async (_guest, bytes) => {
      const module = new WebAssembly.Module(bytes);
      const ownership = new Uint8Array(
        WebAssembly.Module.customSections(module, "blot:ownership")[0],
      );
      const { exports } = await WebAssembly.instantiate(module);
      assert.equal((exports.rows_length as () => number)(), 599);
      assert.equal((exports.cursor_probe as (repeat: number) => number)(0), 1);
      assert.deepEqual(
        [...ownership],
        [2, 2, 0],
        "dynamic packed traversal has complete ownership",
      );
      const memory = exports["blot:memory"] as WebAssembly.Memory;
      const reset = exports["blot:reset"] as (root: number) => number;
      const pressure = exports.pressure as (count: number) => number;
      const base = reset(0);
      const expected = (count: number) => {
        let total = count;
        for (let i = 1; i < 600; i++) {
          for (const value of [i, 0.125, -0.25, 3.5]) {
            total = Math.fround(total + value);
          }
        }
        return Math.fround(total + count - 1);
      };
      assert.equal(pressure(131072), expected(131072));
      if (ownership[1] === 0) assert.equal(reset(0), base);
      const warmed = memory.buffer.byteLength;
      for (let entry = 0; entry < 100; entry++) {
        assert.equal(pressure(131072), expected(131072));
        if (ownership[1] === 0) assert.equal(reset(0), base);
        assert.equal(memory.buffer.byteLength, warmed);
      }
    });
  }
});
