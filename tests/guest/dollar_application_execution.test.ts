import { compileAndRun, equal } from "./compile_helpers.ts";

Deno.test("default dollar preserves primitive arity, demand and nested callback boundaries", async () => {
  await compileAndRun(`
const ignore = func ~(value: U32) => return 42
const twice = func ~(value: U32) => return @u32.add (@demand value) (@demand value)
entry const skipped = func () => return ignore $ @panic "unused demand"
entry const repeated = func (value: U32) => return twice $ @u32.add value 1
entry const generated = func (value: U32) => return do:
  let values = @array.generate 3 $ func index => return do:
    if @u32.eq index 0:
      return value
    return @u32.add value index
  return @u32.add (@array.get values 0) (@array.get values 2)
entry const associated = func (value: U32) => return @u32.add 1 $ @u32.mul 2 $ @u32.add value 1
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
const subtract = func (a: U32) -> (b: U32) => return @u32.sub a b
entry const answer = func () => return 50 $ 5 $ 3
`, guest => equal(guest.call("answer", null), 42));
});
