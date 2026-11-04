import { compileAndRun, equal } from "./compile_helpers.ts";

Deno.test("runtime ordinary scalar wrappers support partial and higher-order calls", async () => {
  await compileAndRun(`
const add = func left => return func right => return @u32.add left right
const plus_one = add 1
const apply = func callable => return func value => return callable value
entry const run = func (value: U32) : U32 => return add (apply plus_one value) 1
entry const convert = func (value: U32) : F32 => return do:
  let conversion = func (input: U32) : F32 => return @u32.to_f32 input
  break conversion value
`, guest => {
    equal(guest.call("run", 40), 42);
    equal(guest.call("run", 0xffffffff), 1);
    for (const value of [0, 1, 16777217, 0xffffffff]) equal(guest.call("convert", value), Math.fround(value));
  });
});

Deno.test("runtime panic remains lazy while unused definitions still pass semantic checking", async () => {
  await compileAndRun(`
const unused = @panic "unused trap"
entry const run = func (flag: Bool) : U32 => return if flag then 42 else @panic "runtime trap"
`, guest => {
    equal(guest.call("run", true), 42);
    let trapped = false;
    try { guest.call("run", false); } catch (error) { trapped = error instanceof WebAssembly.RuntimeError; }
    equal(trapped, true);
    equal(guest.call("run", true), 42);
  });
});
