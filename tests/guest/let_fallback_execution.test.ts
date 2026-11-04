import {throws} from "node:assert/strict";
import {compileAndRun,equal} from "./compile_helpers.ts";
const source = await Deno.readTextFile(new URL("./let_fallbacks.blot",import.meta.url));

for(const asynchronous of [false,true]) Deno.test(`diverging pattern fallback preserves selected values effects and recovery (${asynchronous?"JSPI":"sync"})`,async()=>{
      await compileAndRun(source,async native=>{
        const guest=native;
        {
          equal(guest.read("folded"),42);
          const call=async(name:string,arg:unknown)=>asynchronous?await guest.callAsync(name,arg):guest.call(name,arg);
          let calls=0;
          const capability=(result:number)=>asynchronous?guest.capabilityAsync({parameter:"Unit",result:"U32",call:async()=>{calls++;return result;}}):guest.capability({parameter:"Unit",result:"U32",call:()=>{calls++;return result;}});
          const bad=capability(0),good=capability(1);
          for(let i=0;i<100;i++){
            equal(await call("matching",null),42);
            for(const name of ["choose","branches","nested"]){
              equal(await call(name,true),42);
              let trapped=false;try{await call(name,false);}catch(error){if(!(error instanceof WebAssembly.RuntimeError))throw error;trapped=true;}
              equal(trapped,true);
            }
            equal(await call("floating",true),42.5);
            let trapped=false;try{await call("floating",false);}catch(error){if(!(error instanceof WebAssembly.RuntimeError))throw error;trapped=true;}
            equal(trapped,true);
            equal(await call("merged",false),42);
            if(!asynchronous)throws(()=>guest.call("merged",true),WebAssembly.RuntimeError);
            trapped=false;try{await call("observed",bad);}catch(error){if(!(error instanceof WebAssembly.RuntimeError))throw error;trapped=true;}
            equal(trapped,true);equal(calls,3*i+2);
            equal(await call("observed",good),42);equal(calls,3*i+3);
          }
        }
      },{prelude:"none",asynchronous});
});
