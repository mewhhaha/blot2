import { compileAndRun, equal } from "./compile_helpers.ts";

Deno.test("packed List loop spans survive every row width, leaf crossings and nested traversals", async () => {
  const functions = Array.from({ length: 16 }, (_, offset) => {
    const width = offset + 1;
    const row = Array.from(
      { length: width },
      (_, field) => `f${field}: i + ${field}`,
    ).join(", ");
    const zero = Array.from({ length: width }, (_, field) => `f${field}: 0`)
      .join(", ");
    const sum = Array.from({ length: width }, (_, field) => `row.f${field}`)
      .join(" + ");
    return `
entry const width_${width} = fn count => do:
  let values = @list.generate count (fn i => {${row}})
  let saved = values
  values := [{${zero}}, ...self, {${zero}}]
  let rows = @list.slice values 1 count
  let result = 0
  for pass in 0..3:
    for row in rows:
      for first in rows:
        result := self + first.f0
        break
      result := self + ${sum}
  for row in saved:
    result := self + ${sum}
  return result
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
        const expected = 4 *
          (width * count * (count - 1) / 2 + count * width * (width - 1) / 2);
        equal(guest.call(`width_${width}`, count), expected >>> 0);
      }
    }
  });
});
