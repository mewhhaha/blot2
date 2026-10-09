import { strict as assert } from "node:assert";
import { compileAndRun } from "./compile_helpers.ts";

Deno.test("packed List field snapshots survive branch reads and loop carries at every width", async () => {
  const functions = Array.from({ length: 16 }, (_, offset) => {
    const width = offset + 1;
    const fields = Array.from(
      { length: width },
      (_, field) => `f${field}: i + ${field}`,
    ).join(", ");
    const zero = Array.from({ length: width }, (_, field) => `f${field}: 0`)
      .join(", ");
    return `
entry const width_${width} = fn count => do:
  let rows = @list.generate count (fn i => {${fields}})
  let previous = {${zero}}
  let total = 0
  for row in rows:
    let snapshot = previous
    previous := row
    if row.f0 == 0:
      total := self + snapshot.f0 + row.f${width - 1}
    else:
      total := self + snapshot.f${width - 1} + row.f0
  return #[total, previous.f0, previous.f${width - 1}]
`;
  });
  await compileAndRun(functions.join("\n"), (guest) => {
    for (let width = 1; width <= 16; width++) {
      const boundary = Math.floor(248 / width);
      for (
        const count of new Set([
          0,
          1,
          2,
          boundary - 1,
          boundary,
          boundary + 1,
          boundary * 2 + 3,
          1000,
        ])
      ) {
        let total = 0;
        let previous = 0;
        let previousLast = 0;
        for (let i = 0; i < count; i++) {
          total += i === 0 ? previous + i + width - 1 : previousLast + i;
          previous = i;
          previousLast = i + width - 1;
        }
        assert.deepEqual(
          guest.call(`width_${width}`, count),
          new Uint32Array([total, previous, previousLast]),
        );
      }
    }
  });
});

Deno.test("packed List tuple bindings preserve every scalar across short and crossing leaves", async () => {
  const functions = Array.from({ length: 15 }, (_, index) => {
    const width = index + 2;
    const values = Array.from({ length: width }, (_, i) => `i + ${i}`).join(
      ", ",
    );
    const names = Array.from({ length: width }, (_, i) => `a${i}`);
    return `
entry const tuple_${width} = fn count => do:
  let values = @list.generate count (fn i => (${values}))
  let total = 0
  for (${names.join(", ")}) in values:
    total := self + ${names.join(" + ")}
  return total
`;
  });
  await compileAndRun(functions.join("\n"), (guest) => {
    for (let width = 2; width <= 16; width++) {
      const boundary = Math.floor(248 / width);
      for (const count of [0, 1, boundary, boundary + 1, 1000]) {
        assert.equal(
          guest.call(`tuple_${width}`, count),
          (width * count * (count - 1) / 2 +
            count * width * (width - 1) / 2) >>> 0,
        );
      }
    }
  });
});

Deno.test("borrowed List fields preserve float bits and live values across collection", async () => {
  const functions = Array.from({ length: 16 }, (_, index) => {
    const width = index + 1;
    const fields = Array.from(
      { length: width },
      (_, i) =>
        `f${i}: ${
          i === 0 || i === width - 1 ? "input[i % input.length]" : "i"
        }`,
    );
    return `
entry const bits_${width} = fn (input: Array F32) => do:
  let count = 257
  let values = @list.generate count (fn i => {${fields.join(", ")}})
  let result = #[]
  for row in values:
    result := #[...self, row.f0, row.f${width - 1}]
  return result
`;
  });
  const source = functions.join("\n") + `
entry const edit_during = fn count => do:
  let values = @list.generate count (fn i => {a: i, b: i + 1, c: i + 2})
  let total = 0
  for row in values:
    let before = row.a
    values := [{a: 100000, b: 200000, c: 300000}, ...self]
    total := self + before + row.c
  return #[total, values.length]
entry const collect = fn count => do:
  let rows = @list.generate 3 (fn i => {a: i, b: i + 1, c: i + 2})
  let total = 0
  for row in rows:
    let first = row.a
    let index = 0
    for ever:
      if index == count:
        break
      let discarded = @array.fill 8192 index
      index := self + 1
    total := self + first + row.c
  return total
`;
  await compileAndRun(source, (guest) => {
    for (const count of [0, 1, 83, 90]) {
      assert.deepEqual(
        guest.call("edit_during", count),
        Uint32Array.of(count * (count + 1), count * 2),
      );
    }
    const words = Uint32Array.of(
      0,
      0x80000000,
      0x7fc01234,
      0xffc05678,
      0x7f800000,
      0xff800000,
      0x3f800000,
    );
    const input = new Float32Array(words.buffer);
    for (let width = 1; width <= 16; width++) {
      const count = 257;
      const result = guest.call(`bits_${width}`, input) as Float32Array;
      const actual = new Uint32Array(
        result.buffer,
        result.byteOffset,
        result.length,
      );
      assert.deepEqual(
        actual,
        Uint32Array.from(
          { length: count * 2 },
          (_, i) => words[Math.floor(i / 2) % words.length],
        ),
      );
    }
    assert.equal(guest.call("collect", 256), 12);
    const warmed = guest.memoryBytes();
    assert.equal(guest.call("collect", 256), 12);
    assert(
      guest.memoryBytes() <= warmed + 65536,
      `warmed=${warmed}, actual=${guest.memoryBytes()}`,
    );
  });
});
