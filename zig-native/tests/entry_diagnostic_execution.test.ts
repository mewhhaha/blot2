import { compileAndRun, compileExpectedFailure, equal } from "./compile_helpers.ts";
Deno.test("generic public interfaces reject after concrete retained inference", async () => {
  for (const source of [
    "entry const identity = fn value => value\n",
    "const identity = fn value => value\nentry const alias = identity\n",
    "entry const update = fn value => do:\n  value.lower := 42\n  return value\n",
    "entry const update = fn value => do:\n  value.Upper := 42\n  return value\n",
  ]) await compileExpectedFailure(source, "entry_type");
  await compileAndRun("const make = fn offset => fn (value: U32) => @u32.add offset value\nentry const selected = make 21\nentry const folded = selected 21\n", guest => {
    equal(guest.read("folded"), 42);
    for (const value of [0, 21, 0xffffffff]) equal(guest.call("selected", value), (value + 21) >>> 0);
  });
});
Deno.test("anonymous record rejection precedes unknown children and named records remain distinct", async () => {
  for (const source of ["entry const x = { lower: 0 }\n", "entry const x = ({ lower: missing }).lower\n"])
    await compileExpectedFailure(source, "unsupported_expression");
  await compileExpectedFailure("entry const x = #Missing { lower: 0 }\n", "unknown_constructor");
  await compileAndRun("type Box is data = #Box { lower: U32 }\nentry const x = (#Box { lower: 42 }).lower\n", guest => equal(guest.read("x"), 42));
});
