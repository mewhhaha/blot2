import {compileAndRun,compileExpectedFailure,equal} from "./compile_helpers.ts";

Deno.test("generic and captured product projections retain mixed slot types",async()=>{
  await compileAndRun(`const first=func(value:(a,b))=> return @product.get value 0
const capture=func(value:(U32,Bool))=> return func()=> return @product.get value 0
entry const answer=func()=> return @u32.add (first (20,true)) ((capture (22,false)) ())
entry const folded=answer ()
`,guest=>{equal(guest.read("folded"),42);for(let i=0;i<100;i++)equal(guest.call("answer",null),42);},{prelude:"none"});
});

Deno.test("product arity shape and literal index errors remain distinct",async()=>{
 for(const [expression,code] of [
  ["@product.get (42,true) 2","product_index"],
  ["@product.get (42,true) 4294967295","product_index"],
  ["@product.get (42,true) (0)","product_index_literal"],
  ["@product.get (42,true) 0.0","product_index_literal"],
  ["@product.get (42,true) false","product_index_literal"],
  ["@product.get () 0","type_mismatch"],
  ["(func value=> return @product.get value 0) (42,true)","unknown_product_shape"],
 ]as const)await compileExpectedFailure(`entry const answer=func()=> return ${expression}\n`,code,undefined,{prelude:"none"});
});

Deno.test("projecting Never preserves prior callback effects and traps in sync and JSPI guests",async()=>{
 for(const asynchronous of [false,true])await compileAndRun(`entry const answer: (Unit -> Unit ! {Foreign}) -> U32 ! {Foreign} = func before => return do:
  before ()
  break @product.get (@panic "projected") 0
`,async guest=>{
  let count=0;
  const host=asynchronous?guest.capabilityAsync({parameter:"Unit",result:"Unit",call:async()=>{count++;return null;}}):guest.capability({parameter:"Unit",result:"Unit",call:()=>{count++;return null;}});
  for(let i=0;i<20;i++){
    let trapped=false;
    try{if(asynchronous)await guest.callAsync("answer",host);else guest.call("answer",host);}catch(error){if(!(error instanceof WebAssembly.RuntimeError))throw error;trapped=true;}
    equal(trapped,true);equal(count,i+1);
  }
 },{prelude:"none",asynchronous});
});
