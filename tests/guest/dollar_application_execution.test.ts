import { compileAndRun, equal } from "./compile_helpers.ts";

Deno.test("default dollar preserves primitive arity and nested callback boundaries", async () => {
  await compileAndRun(`
const ignore = func value => return 42
const twice = func value => return do:
  let saved = value ()
  break @u32.add saved saved
io const skipped = func () => return ignore $ func () => return @panic "unused callback"
io const repeated = func (value: U32) => return twice $ func () => return @u32.add value 1
io const generated = func (value: U32) => return do:
  let values = @array.generate 3 $ func index => return do:
    if @u32.eq index 0:
      return value
    return @u32.add value index
  return @u32.add (@array.get values 0) (@array.get values 2)
io const associated = func (value: U32) => return @u32.add 1 $ @u32.mul 2 $ @u32.add value 1
`, guest => {
    equal(guest.call("skipped", null), 42);
    equal(guest.call("repeated", 20), 42);
    equal(guest.call("generated", 20), 42);
    equal(guest.call("associated", 20), 43);
  }, { prelude: "none" });
});
