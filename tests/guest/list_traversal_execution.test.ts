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
entry const width_${width} = func count => return do:
  let rows = @list.generate count (func i => return {${fields}})
  let previous = {${zero}}
  let total = 0
  for row in rows:
    let snapshot = previous
    previous := row
    if row.f0 == 0:
      total := self + snapshot.f0 + row.f${width - 1}
    else:
      total := self + snapshot.f${width - 1} + row.f0
  break #[total, previous.f0, previous.f${width - 1}]
`;
  });
  await compileAndRun(functions.join("\n"), (guest) => {
    for (let width = 1; width <= 16; width++) {
      const boundary = Math.floor(244 / width);
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
entry const tuple_${width} = func count => return do:
  let values = @list.generate count (func i => return (${values}))
  let total = 0
  for (${names.join(", ")}) in values:
    total := self + ${names.join(" + ")}
  break total
`;
  });
  await compileAndRun(functions.join("\n"), (guest) => {
    for (let width = 2; width <= 16; width++) {
      const boundary = Math.floor(244 / width);
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
