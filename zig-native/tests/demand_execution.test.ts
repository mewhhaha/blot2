import { compileAndRun, compileExpectedFailure, equal } from "./compile_helpers.ts";
import { demandCases } from "./demand_cases.ts";

Deno.test("persistent demanded arrays survive arena resets and local demands retain snapshots", async () => {
  await compileAndRun(`
const delay = fn ~value => value
const pending = delay (@array.fill 3 7)
const alias = pending
entry const read = fn () -> U32 => @array.get (@force pending) 2
entry const read_alias = fn () -> U32 => @array.get (@force alias) 0
entry const pressure = fn (count: U32) -> Array U32 => @array.fill count 99
entry const local = fn (value: U32) -> U32 => do:
  let pending = delay (@array.generate 3 (fn index => @u32.add value index))
  let before = @force pending
  value := 99
  let after = @force pending
  return @u32.add (@array.get before 2) (@array.get after 0)
`, guest => {
    equal(guest.call("read", null), 7);
    for (const size of [32768, 0, 2, 16384]) {
      equal((guest.call("pressure", size) as Uint32Array).length, size);
      equal(guest.call("read_alias", null), 7);
      equal(guest.call("read", null), 7);
      equal(guest.call("local", 20), 42);
    }
  });
});

for (const item of demandCases) {
  if (!("expected" in item)) continue;
  Deno.test(`native demand preserves ${item.name}`, async () => {
    await compileAndRun(item.source, (guest) => {
      const repetitions = "repetitions" in item ? item.repetitions : 1;
      for (let iteration = 0; iteration < repetitions; iteration++) for (const [name, expected] of Object.entries(item.expected)) {
        const argument = "arguments" in item
          ? (item.arguments as Record<string, number>)[name]
          : undefined;
        equal(
          guest.abi.constants.some((value) => value.name === name)
            ? guest.read(name)
            : guest.call(name, argument ?? null),
          expected,
        );
      }
    });
  });
}

Deno.test("native demand rejects eager forcing, mode mismatches and suspended loop escape", async () => {
  for (const item of demandCases) {
    if (!("error" in item)) continue;
    await compileExpectedFailure(item.source, item.error);
  }
});
