import { strict as assert } from "node:assert";
import { compileAndRun } from "./compile_helpers.ts";

Deno.test("contiguous row sums preserve U32 wrapping, scalar tails and empty inputs", async () => {
  const functions: string[] = [];
  for (const collection of ["array", "list"]) {
    for (let width = 1; width <= 16; width++) {
      const fields = Array.from(
        { length: width },
        (_, i) => `f${i}: input[2 + (index + ${i}) % (input.length - 2)]`,
      );
      const sum = Array.from(
        { length: width },
        (_, i) => `row.f${width - 1 - i}`,
      ).join(" + ");
      functions.push(`
entry const ${collection}_${width} = fn (input: Array U32) => do:
  let count = input[0]
  let initial = input[1]
  let rows = @${collection}.generate count (fn index => {${fields.join(", ")}})
  let total = initial
  for row in rows:
    total := self + ${sum}
  return total
`);
    }
  }
  await compileAndRun(functions.join("\n"), (guest) => {
    const input = Uint32Array.of(
      0xffffffff,
      0x80000000,
      0,
      1,
      0x7fffffff,
      17,
      99,
    );
    const call = (
      name: string,
      values: Uint32Array,
      count: number,
      initial: number,
    ) => guest.call(name, Uint32Array.of(count, initial, ...values));
    for (const collection of ["array", "list"]) {
      for (let width = 1; width <= 16; width++) {
        const name = `${collection}_${width}`;
        assert.equal(
          call(name, new Uint32Array(), 0, 0xffffffff),
          0xffffffff,
        );
        for (const count of [1, Math.floor(248 / width) + 1, 257]) {
          let expected = 0xfffffff7;
          for (let row = 0; row < count; row++) {
            for (let field = width - 1; field >= 0; field--) {
              expected = (expected + input[(row + field) % input.length]) >>> 0;
            }
          }
          assert.equal(call(name, input, count, 0xfffffff7), expected);
        }
        assert.throws(() => call(name, new Uint32Array(), 1, 0));
        let recovered = 0;
        for (let field = width - 1; field >= 0; field--) {
          recovered = (recovered + input[field % input.length]) >>> 0;
        }
        assert.equal(call(name, input, 1, 0), recovered);
      }
    }
  });
});

Deno.test("floating row sums retain source evaluation order", async () => {
  const functions: string[] = [];
  for (const collection of ["array", "list"]) {
    for (let width = 1; width <= 16; width++) {
      const fields = Array.from(
        { length: width },
        (_, field) =>
          `f${field}: input[2 + (index + ${field}) % (input.length - 2)]`,
      );
      const sum = Array.from(
        { length: width },
        (_, field) => `row.f${width % 2 === 0 ? field : width - 1 - field}`,
      ).join(" + ");
      functions.push(`
entry const ${collection}_${width} = fn (input: Array F32) => do:
  let count = @f32.to_u32 input[0]
  let total = input[1]
  let rows = @${collection}.generate count (fn index => {${fields.join(", ")}})
  for row in rows:
    total := self + ${sum}
  return total
`);
    }
  }
  await compileAndRun(functions.join("\n"), (guest) => {
    const inputs = [
      Float32Array.of(1e20, -1e20, 3, 4, -0),
      Float32Array.of(Infinity, -Infinity, 1),
      Float32Array.of(1e-45, -1e-45, -0, 0),
    ];
    const call = (
      name: string,
      count: number,
      initial: number,
      values: Float32Array,
    ) => guest.call(name, Float32Array.of(count, initial, ...values));
    for (const collection of ["array", "list"]) {
      for (let width = 1; width <= 16; width++) {
        const name = `${collection}_${width}`;
        assert.equal(call(name, 0, -0, new Float32Array()), -0);
        for (const input of inputs) {
          for (const count of [1, Math.floor(248 / width) + 1, 257]) {
            let expected = Math.fround(0.25);
            for (let row = 0; row < count; row++) {
              for (let step = 0; step < width; step++) {
                const field = width % 2 === 0 ? step : width - 1 - step;
                expected = Math.fround(
                  expected + input[(row + field) % input.length],
                );
              }
            }
            assert.equal(call(name, count, 0.25, input), expected);
          }
        }
        assert.throws(() => call(name, 1, 0, new Float32Array()));
        let recovered = 0;
        for (let step = 0; step < width; step++) {
          const field = width % 2 === 0 ? step : width - 1 - step;
          recovered = Math.fround(
            recovered + inputs[0][field % inputs[0].length],
          );
        }
        assert.equal(call(name, 1, 0, inputs[0]), recovered);
      }
    }
  });
});
