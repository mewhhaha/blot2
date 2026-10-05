import {compileAndRun,compileExpectedFailure,equal} from "./compile_helpers.ts";

Deno.test("generic and captured product projections retain mixed slot types",async()=>{
  await compileAndRun(`const first=fn(value:(a,b))=>@product.get value 0
const capture=fn(value:(U32,Bool))=>fn()=>@product.get value 0
entry const answer=fn()=>@u32.add (first (20,#True)) ((capture (22,#False)) ())
entry const folded=answer ()
`,guest=>{equal(guest.read("folded"),42);for(let i=0;i<100;i++)equal(guest.call("answer",null),42);},{prelude:"none"});
});

Deno.test("product arity shape and literal index errors remain distinct",async()=>{
 for(const [expression,code] of [
  ["@product.get (42,#True) 2","product_index"],
  ["@product.get (42,#True) 4294967295","product_index"],
  ["@product.get (42,#True) (0)","product_index_literal"],
  ["@product.get (42,#True) 0.0","product_index_literal"],
  ["@product.get (42,#True) #False","product_index_literal"],
  ["@product.get () 0","type_mismatch"],
  ["(fn value=>@product.get value 0) (42,#True)","unknown_product_shape"],
 ]as const)await compileExpectedFailure(`entry const answer=fn()=>${expression}\n`,code,undefined,{prelude:"none"});
});

Deno.test("projecting Never preserves prior callback effects and traps in sync and JSPI guests",async()=>{
 for(const asynchronous of [false,true])await compileAndRun(`entry const answer: (Unit -> Unit ! {Foreign}) -> U32 ! {Foreign} = fn before => do:
  before ()
  return @product.get (@panic "projected") 0
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
