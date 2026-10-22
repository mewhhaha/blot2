import { strict as assert } from "node:assert";
import { compileAndRun } from "./reduction_helpers.ts";
const stdRoot = new URL("../../std", import.meta.url).pathname;

import { GuestError } from "../../compiler/guest.ts";

Deno.test("private packed cursor versions preserve every row width and raw F32 order", async () => {
  for (const shape of ["record", "tuple"]) {
    let first = 1;
    if (shape === "tuple") first = 2;
    for (let width = first; width <= 16; width++) {
      const fields = Array.from(
        { length: width },
        (_, i) => `@u32.to_f32 (@u32.add i ${i})`,
      );
      let value = `(${fields.join(", ")})`;
      let binding = `(${fields.map((_, i) => `f${i}`).join(", ")})`;
      let sum = fields.map((_, i) => `f${i}`).reduce((left, right) =>
        `@f32.add (${left}) ${right}`
      );
      if (shape === "record") {
        value = `{${fields.map((field, i) => `f${i}: ${field}`).join(", ")}}`;
        binding = "row";
        sum = fields.map((_, i) => `row.f${i}`).reduce((left, right) =>
          `@f32.add (${left}) ${right}`
        );
      }
      await compileAndRun(
        `
entry const run = fn (count: U32) => do:
  let rows = @list.generate count (fn i => ${value})
  let cursor = @list.cursor rows
  let total = 0.0
  for i in 0..count:
    let ${binding} = @cursor.value cursor
    total := @f32.add self (${sum})
    cursor := @cursor.advance self
  break total
entry const probe = fn (seed: U32) => #[seed]
`,
        (guest) => {
          for (const count of [0, 1, 14, 15, 16, 243, 244, 245, 1000]) {
            let total = 0;
            for (let row = 0; row < count; row++) {
              let value = row;
              for (let i = 1; i < width; i++) {
                value = Math.fround(value + row + i);
              }
              total = Math.fround(total + value);
            }
            assert.equal(
              guest.call("run", count),
              total,
              `${shape}/${width}/${count}`,
            );
          }
        },
        { stdRoot },
      );
    }
  }
});

Deno.test("private cursor carriers root actual collections across pressure and keep old forks", async () => {
  await compileAndRun(
    `
entry const run = fn (count: U32) => do:
  let values = @list.generate 1000 (fn i => {x: i, y: @u32.add i 8192})
  let cursor = @list.cursor values
  let original = cursor
  let right = @cursor.advance original
  let total = 0
  let index = 0
  for ever:
    if @u32.eq index count:
      break @u32.add total (@cursor.value original).y
    let garbage = @array.fill 8192 index
    let row = @cursor.value cursor
    total := @u32.add self (@u32.add row.x (@cursor.value right).x)
    cursor := @cursor.advance self
    right := @cursor.advance self
    index := @u32.add self 1
entry const probe = fn (seed: U32) => #[seed]
`,
    (guest) => {
      for (const count of [0, 1, 120, 121, 122, 243, 500, 999]) {
        assert.equal(guest.call("run", count), count * count + 8192);
      }
      const warm = guest.memoryBytes();
      for (let i = 0; i < 8; i++) {
        assert.equal(
          guest.call("run", 999),
          999 * 999 + 8192,
        );
      }
      assert.equal(guest.memoryBytes(), warm);
    },
    { stdRoot },
  );
});

Deno.test("published packed cursors and nested advances keep heap snapshot semantics", async () => {
  await compileAndRun(
    `
entry const run = fn (count: U32) => do:
  let values = @list.generate 600 (fn i => {x: i, bits: 8192})
  let first = @list.cursor values
  let cursor = first
  for index in 0..count:
    cursor := @cursor.advance self
  let readers = #[first, cursor]
  let selected = fn () => (@cursor.value cursor).x
  let index = 0
  for ever:
    if @u32.eq index 32:
      break
    let garbage = @array.fill 8192 index
    index := @u32.add self 1
  break #[(@cursor.value readers[0]).x, (@cursor.value readers[1]).x,
    (@cursor.value (@cursor.advance first)).x, selected (), (@cursor.value first).bits]
`,
    (guest) => {
      for (const count of [0, 1, 120, 121, 122, 243, 500]) {
        assert.deepEqual(
          guest.call("run", count),
          Uint32Array.of(0, count, 1, count, 8192),
        );
      }
    },
    { stdRoot },
  );
});

Deno.test("private cursor snapshots survive JSPI suspension rejection and rebind", async () => {
  await compileAndRun(
    `
entry const run = fn (host: U32 -> U32 ! {Foreign}) => do:
  let values = @list.generate 600 (fn i => {x: i, y: @u32.add i 8192})
  let cursor = @list.cursor values
  let original = cursor
  let total = 0
  for index in 0..300:
    let row = @cursor.value cursor
    use value <- host row.x
    total := @u32.add self value
    cursor := @cursor.advance self
  break #[total, (@cursor.value original).y]
`,
    async (guest) => {
      let reject = false;
      const capability = guest.capabilityAsync({
        parameter: "U32",
        result: "U32",
        call: async (value: number) => {
          await Promise.resolve();
          if (reject && value === 123) throw new Error("cursor host rejection");
          return value;
        },
      });
      assert.deepEqual(
        await guest.callAsync("run", capability),
        Uint32Array.of(44850, 8192),
      );
      reject = true;
      await assert.rejects(
        () => guest.callAsync("run", capability),
        (error: unknown) =>
          error instanceof GuestError && error.code === "host_exception" &&
          error.cause instanceof Error &&
          error.cause.message === "cursor host rejection",
      );
      reject = false;
      assert.deepEqual(
        await guest.callAsync("run", capability),
        Uint32Array.of(44850, 8192),
      );
    },
    { stdRoot, asynchronous: true },
  );
});
