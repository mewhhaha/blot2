import { compileAndRun, equal } from "./compile_helpers.ts";

Deno.test("default dollar preserves primitive arity, demand and nested callback boundaries", async () => {
  await compileAndRun(`
const ignore = fn ~(value: U32) => 42
const twice = fn ~(value: U32) => @u32.add (@force value) (@force value)
entry const skipped = fn () => ignore $ @panic "unused demand"
entry const repeated = fn (value: U32) => twice $ @u32.add value 1
entry const generated = fn (value: U32) => do:
  let values = @array.generate 3 $ fn index => do:
    if @u32.eq index 0:
      return value
    return @u32.add value index
  return @u32.add (@array.get values 0) (@array.get values 2)
entry const associated = fn (value: U32) => @u32.add 1 $ @u32.mul 2 $ @u32.add value 1
`, guest => {
    equal(guest.call("skipped", null), 42);
    equal(guest.call("repeated", 20), 42);
    equal(guest.call("generated", 20), 42);
    equal(guest.call("associated", 20), 43);
  }, { prelude: "none" });
});

Deno.test("explicit dollar fixity overrides grouping even with the standard prelude", async () => {
  await compileAndRun(`
infixl 60 ($) = subtract
const subtract = fn (a: U32) (b: U32) => @u32.sub a b
entry const answer = fn () => 50 $ 5 $ 3
`, guest => equal(guest.call("answer", null), 42));
});
