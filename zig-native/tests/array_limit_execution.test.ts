import {compileAndRun,compileExpectedFailure,equal} from "./compile_helpers.ts";

Deno.test("compile-time array limit preserves operand order and leaves generators unvisited",async()=>{
  for(const source of [
    "entry const answer = @array.length (@array.generate 4194304 (fn (index: U32) -> U32 => index))\n",
    "entry const answer = @array.length (@array.generate 4294967295 (fn (index: U32) -> U32 => @panic \"unvisited\"))\n",
    "entry const answer = @array.length (@array.fill 4194304 7)\n",
    "entry const answer = @array.length (@array.fill 4294967295 7)\n",
  ]) await compileExpectedFailure(source,"backend_limit","array length exceeds the 16 MiB bootstrap arena",{prelude:"none"});
  for(const [expression,message] of [
    ['@array.generate 4194304 (@panic "generator operand")',"generator operand"],
    ['@array.fill 4194304 (@panic "fill operand")',"fill operand"],
    ['@array.generate (@panic "count first") (@panic "generator second")',"count first"],
    ['@array.fill (@panic "count first") (@panic "fill second")',"count first"],
  ]) await compileExpectedFailure(`const invalid: Array U32 = ${expression}\nentry const answer: U32 = @array.length invalid\n`,"const_panic",message,{prelude:"none"});
});

Deno.test("compile-time legal arrays preserve empty callbacks and generated scalar values",async()=>{
  await compileAndRun(`
entry const empty = @array.length (@array.generate 0 (fn (index: U32) -> U32 => @panic "unvisited"))
entry const generated = @array.get (@array.generate 3 (fn (index: U32) -> U32 => @u32.add index 40)) 2
entry const filled = @array.get (@array.fill 3 42) 2
entry const small = fn () => @array.get (@array.generate 3 (fn (index: U32) -> U32 => @u32.add index 40)) 2
`,guest=>{
    equal(guest.read("empty"),0);
    equal(guest.read("generated"),42);
    equal(guest.read("filled"),42);
    for(let i=0;i<100;i++)equal(guest.call("small",null),42);
  },{prelude:"none"});
});
