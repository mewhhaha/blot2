import { compileAndRun, equal } from "./compile_helpers.ts";

Deno.test("runtime ordinary scalar wrappers support partial and higher-order calls", async () => {
  await compileAndRun(`
const add = fn left => fn right => @u32.add left right
const plus_one = add 1
const apply = fn callable => fn value => callable value
entry const run = fn (value: U32) -> U32 => add (apply plus_one value) 1
entry const convert = fn (value: U32) -> F32 => do:
  let conversion = fn (input: U32) -> F32 => @u32.to_f32 input
  return conversion value
`, guest => {
    equal(guest.call("run", 40), 42);
    equal(guest.call("run", 0xffffffff), 1);
    for (const value of [0, 1, 16777217, 0xffffffff]) equal(guest.call("convert", value), Math.fround(value));
  });
});

Deno.test("runtime panic remains lazy while unused definitions still pass semantic checking", async () => {
  await compileAndRun(`
const unused = @panic "unused trap"
entry const run = fn (flag: Bool) -> U32 => if flag then 42 else @panic "runtime trap"
`, guest => {
    equal(guest.call("run", true), 42);
    let trapped = false;
    try { guest.call("run", false); } catch (error) { trapped = error instanceof WebAssembly.RuntimeError; }
    equal(trapped, true);
    equal(guest.call("run", true), 42);
  });
});
