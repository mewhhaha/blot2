import { compileAndRun, compileExpectedFailure, equal } from "./compile_helpers.ts";
Deno.test("generic public interfaces reject after concrete retained inference", async () => {
  for (const source of [
    "io const identity = func value => return value\n",
    "const identity = func value => return value\nio const alias = identity\n",
    "io const update = func value => return do:\n  value.lower := 42\n  break value\n",
    "io const update = func value => return do:\n  value.Upper := 42\n  break value\n",
  ]) await compileExpectedFailure(source, "entry_type");
  await compileAndRun("const make = func offset => return func (value: U32) => return @u32.add offset value\nio const selected = make 21\nio const folded = selected 21\n", guest => {
    equal(guest.read("folded"), 42);
    for (const value of [0, 21, 0xffffffff]) equal(guest.call("selected", value), (value + 21) >>> 0);
  });
});
Deno.test("structural records validate children and named records remain distinct", async () => {
  await compileExpectedFailure("io const x = { lower: 0 }\n", "entry_type");
  await compileExpectedFailure("io const x = ({ lower: missing }).lower\n", "unknown_value");
  await compileExpectedFailure("io const x = $Missing { lower: 0 }\n", "unknown_constructor");
  await compileAndRun("type Box is data = $Box { lower: U32 }\nio const x = ($Box { lower: 42 }).lower\n", guest => equal(guest.read("x"), 42));
});
