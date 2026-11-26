import {rejects} from "node:assert/strict";
import {compileAndRun,equal} from "./compile_helpers.ts";

// Constants run at instantiation, so impossible array lengths and panicking
// operands trap there.
Deno.test("impossible constant array lengths trap at instantiation",async()=>{
  for(const source of [
    "io const answer = @array.length (@array.generate 4294967295 (func (index: U32) : U32 => return @panic \"unvisited\"))\n",
    "io const answer = @array.length (@array.fill 4294967295 7)\n",
  ]) await rejects(compileAndRun(source,()=>{},{prelude:"none"}),WebAssembly.RuntimeError);
});

Deno.test("panicking constant array operands trap at instantiation",async()=>{
  for(const expression of [
    '@array.generate 4194304 (@panic "generator operand")',
    '@array.fill 4194304 (@panic "fill operand")',
    '@array.generate (@panic "count first") (@panic "generator second")',
    '@array.fill (@panic "count first") (@panic "fill second")',
  ]) await rejects(compileAndRun(`const invalid: Array U32 = ${expression}\nio const answer: U32 = @array.length invalid\n`,()=>{},{prelude:"none"}),WebAssembly.RuntimeError);
});

Deno.test("compile-time legal arrays preserve empty callbacks and generated scalar values",async()=>{
  await compileAndRun(`
io const empty = @array.length (@array.generate 0 (func (index: U32) : U32 => return @panic "unvisited"))
io const generated = @array.get (@array.generate 3 (func (index: U32) : U32 => return @u32.add index 40)) 2
io const filled = @array.get (@array.fill 3 42) 2
io const small = func () => return @array.get (@array.generate 3 (func (index: U32) : U32 => return @u32.add index 40)) 2
`,guest=>{
    equal(guest.read("empty"),0);
    equal(guest.read("generated"),42);
    equal(guest.read("filled"),42);
    for(let i=0;i<100;i++)equal(guest.call("small",null),42);
  },{prelude:"none"});
});
