import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;

function rowPrograms() {
  const functions: string[] = [];
  const cases: { name: string; width: number; fields: number[] }[] = [];
  for (const shape of ["record", "tuple"]) {
    let firstWidth = 1;
    if (shape === "tuple") firstWidth = 2;
    for (let width = firstWidth; width <= 16; width++) {
      const fields: string[] = [];
      const reads: string[] = [];
      for (let field = 0; field < width; field++) {
        const value =
          `input[@u32.add 4 (@u32.rem (@u32.add index ${field}) (@u32.sub (@array.length input) 4))]`;
        if (shape === "record") {
          const name = `f${String(field).padStart(2, "0")}`;
          fields.push(`${name}: ${value}`);
          reads.push(`row.${name}`);
        } else {
          fields.push(value);
          reads.push(`@product.get row ${field}`);
        }
      }
      const order = Array.from({ length: Math.min(width, 4) }, (_, i) => i);
      if (width % 2 !== 0) order.reverse();
      let expression = `@f32.mul (${reads[order[0]]}) factor`;
      for (const field of order.slice(1)) {
        expression = `@f32.add (${expression}) (@f32.mul (${
          reads[field]
        }) factor)`;
      }
      let row = `(${fields.join(", ")})`;
      if (shape === "record") row = `{${fields.join(", ")}}`;
      for (const collection of ["array", "list"]) {
        const name = `${collection}_${shape}_${width}`;
        cases.push({ name, width, fields: order });
        functions.push(`entry const ${name} = func (input: Array F32) => return do:
  let count = @f32.to_u32 input[0]
  let start = @f32.to_u32 input[1]
  let factor = input[3]
  let rows = @${collection}.generate (@u32.add start count) (func index => return ${row})
  let values = @${collection}.slice rows start count
  let total = input[2]
  for row in values:
    total := @f32.add total (${expression})
  break total
`);
      }
    }
  }
  functions.push(`
const consume = func row => return @f32.add (@f32.add (@f32.add (@f32.mul row.a 1.25) (@f32.mul row.b 1.25)) (@f32.mul row.c 1.25)) (@f32.mul row.d 1.25)
entry const shared = func (input: Array F32) => return do:
  let rows = @array.fill 257 {a: input[0], b: input[1], c: input[2], d: input[3]}
  let saved = rows
  rows[0].a := 99.0
  let pressure = @array.fill 8192 123
  break #[consume saved[0], consume rows[0]]
entry const effectful = func (host: F32 -> F32 ! {Foreign}) => return do:
  let rows = @array.fill 5 {a: 1.0, b: 2.0, c: 3.0, d: 4.0}
  let total = 0.0
  for row in rows:
    let first = @f32.mul row.a 1.25
    use second <- host (@f32.mul row.b 1.25)
    let third = @f32.mul row.c 1.25
    let fourth = @f32.mul row.d 1.25
    total := @f32.add total (@f32.add (@f32.add (@f32.add first second) third) fourth)
  break total
`);
  return { source: functions.join("\n"), cases };
}

function reduced(
  values: Float32Array,
  fields: number[],
  row: number,
  factor: number,
) {
  let result = Math.fround(values[(row + fields[0]) % values.length] * factor);
  for (const field of fields.slice(1)) {
    result = Math.fround(
      result + Math.fround(values[(row + field) % values.length] * factor),
    );
  }
  return result;
}

for (const codegenTier of ["optimized", "development"] as const) {
  Deno.test(`checked row products preserve lane order, slices, traps and snapshots (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-row-products-" });
    const entry = `${directory}/main.blot`;
    const compiler = await createZigProjectCompiler({
      executable,
      entry,
      prelude: null,
      codegenTier,
      cacheDirectory: false,
    });
    try {
      const { source, cases } = rowPrograms();
      const built = await compiler.build({ sources: { [entry]: source } });
      assert(built.success, JSON.stringify(built));
      const guest = await instantiateGuest(built.bytes);
      try {
        const inputs = [
          Float32Array.of(16777216, 1, -16777216, 3, -0),
          Float32Array.of(Infinity, -Infinity, 1, NaN),
          Float32Array.of(1e-45, -1e-45, -0, 0),
        ];
        for (const { name, width, fields } of cases) {
          assert.equal(guest.call(name, Float32Array.of(0, 0, -0, 1.25)), -0);
          for (const values of inputs) {
            for (
              const count of [1, 2, 3, 4, 5, Math.floor(248 / width) + 1, 257]
            ) {
              const start = 3;
              const factor = Math.fround(1.25);
              let expected = Math.fround(0.25);
              for (let row = start; row < start + count; row++) {
                expected = Math.fround(
                  expected + reduced(values, fields, row, factor),
                );
              }
              assert.equal(
                guest.call(
                  name,
                  Float32Array.of(count, start, 0.25, factor, ...values),
                ),
                expected,
                name,
              );
            }
          }
          for (const factor of [-0, Infinity, NaN]) {
            const values = Float32Array.of(-0, 0, 1, -1);
            const expected = Math.fround(
              -0 + reduced(values, fields, 0, factor),
            );
            assert.equal(
              guest.call(name, Float32Array.of(1, 0, -0, factor, ...values)),
              expected,
              name,
            );
          }
          assert.throws(
            () => guest.call(name, Float32Array.of(1, 0, 0, 1.25)),
            WebAssembly.RuntimeError,
          );
          assert.equal(
            guest.call(name, Float32Array.of(1, 0, 0, 1.25, 2)),
            fields.length * 2.5,
          );
        }
        const original = Float32Array.of(1, 2, 3, 4);
        assert.deepEqual(
          guest.call("shared", original),
          Float32Array.of(12.5, 135),
        );
        const seen: number[] = [];
        const host = guest.capability({
          parameter: "F32",
          result: "F32",
          call(value) {
            seen.push(value);
            return value;
          },
        });
        assert.equal(guest.call("effectful", host), 62.5);
        assert.deepEqual(seen, [2.5, 2.5, 2.5, 2.5, 2.5]);
      } finally {
        guest.dispose();
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
