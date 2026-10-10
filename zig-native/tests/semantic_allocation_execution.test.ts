import { deepStrictEqual as equal } from "node:assert/strict";
import { compileAndRun } from "./compile_helpers.ts";

Deno.test("frozen publication preserves wide scalar captures and distinct factories in Wasm", async () => {
  const width = 32;
  const bindings = Array.from(
    { length: width },
    (_, i) => `  let c${i} = @u32.add seed ${i}`,
  );
  let sum = `c${width - 1}`;
  for (let i = width - 2; i >= 0; i--) sum = `(@u32.add c${i} ${sum})`;
  const source = `const make: U32 -> (U32 -> U32 ! {}) = fn seed => do:
${bindings.join("\n")}
  return fn value => @u32.add value ${sum}
const first = make 1
const second = make 2
entry const one: U32 -> U32 = fn value => first value
entry const two: U32 -> U32 = fn value => second value
`;
  await compileAndRun(source, (guest) => {
    for (const value of [0, 42, 0xFFFF_FFFF]) {
      equal(
        guest.call("one", value),
        (value + width + width * (width - 1) / 2) >>> 0,
      );
      equal(
        guest.call("two", value),
        (value + 2 * width + width * (width - 1) / 2) >>> 0,
      );
    }
  }, { prelude: "none" });
});
