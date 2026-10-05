import {compileAndRun,equal} from "./compile_helpers.ts";
const source = await Deno.readTextFile(new URL("./bottom_bindings.blot",import.meta.url));
for(const asynchronous of [false,true]) Deno.test(`diverging binding initializers preserve selected scalar values and effects (${asynchronous?"JSPI":"sync"})`,async()=>{
  await compileAndRun(source,async guest=>{
          equal(guest.read("folded"),42);
          const call=async(name:string,arg:unknown)=>asynchronous?await guest.callAsync(name,arg):guest.call(name,arg);
          let calls=0;
          const capability=(result:number)=>asynchronous?guest.capabilityAsync({parameter:"Unit",result:"U32",call:async()=>{calls++;return result;}}):guest.capability({parameter:"Unit",result:"U32",call:()=>{calls++;return result;}});
          const bad=capability(0),good=capability(1);
          for(let i=0;i<100;i++){
            for(const name of ["guard_bound","guard_wild","guard_tuple","partial_value"]){
              equal(await call(name,true),42);
              let trapped=false;try{await call(name,false);}catch(error){if(!(error instanceof WebAssembly.RuntimeError))throw error;trapped=true;}
              equal(trapped,true);
            }
            equal(await call("guard_float",true),42.5);
            for(const [name,arg] of [["guard_float",false],["tuple_panic",null],["tuple_float",null]] as const){
              let trapped=false;try{await call(name,arg);}catch(error){if(!(error instanceof WebAssembly.RuntimeError))throw error;trapped=true;}
              equal(trapped,true);
            }
            let trapped=false;
            trapped=false;try{await call("observed",bad);}catch(error){if(!(error instanceof WebAssembly.RuntimeError))throw error;trapped=true;}
            equal(trapped,true);equal(calls,3*i+2);
            equal(await call("observed",good),42);equal(calls,3*i+3);
          }
  },{prelude:"none",asynchronous});
});
