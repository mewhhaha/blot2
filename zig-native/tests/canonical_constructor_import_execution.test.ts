import { instantiateGuest } from "../../compiler/guest.ts";
import { strictEqual } from "node:assert/strict";
export const producerSource = `
data Box a = #Box { value:a }
data Pair = #Pair { x:U32,y:F32 }
const box = #Box
const pair = #Pair
const retain = fn constructor => fn value => constructor value
const ready = retain #Box
const witness = fn () -> Box U32 => @panic "type witness executed"
const advance = fn witness => do:
  use previous <- @state.get witness
  let #Box old = previous
  use @state.set (#Box (@u32.add old 1))
  return old
`;
export const consumerSource = `
import * as model from "./model"
const unwrap = fn box => case box of
  #model.Box value => value
const retain = fn () => do:
  let constructor = #model.Box
  return fn value => unwrap (constructor value)
entry const unsigned = fn (value:U32) => unwrap (model.box value)
entry const floating = fn (value:F32) => unwrap (model.ready value)
entry const captured = fn (value:F32) => (retain ()) value
entry const tuple = fn (value:U32) => case model.pair (value,2.5) of
  #model.Pair (x,y) => @f32.add (@u32.to_f32 x) y
entry const ordered = fn () => do:
  let (#model.Box count,selected) = @state.run (#model.Box 0) (fn () => do:
    use pair <- model.pair (model.advance model.witness,@u32.to_f32 (model.advance model.witness))
    return pair
  )
  let #model.Pair (x,y) = selected
  return @f32.add (@u32.to_f32 (@u32.add (@u32.mul count 10) x)) y
entry const folded = ordered ()
`;
const compiler=Deno.args[0]??new URL("../zig-out/bin/blotc",import.meta.url).pathname;
for(const asynchronous of [false,true])Deno.test(`imported callable record constructors retain source arrows, captures and State argument order (${asynchronous?"JSPI":"sync"})`,async()=>{
 const dir=await Deno.makeTempDir({dir:new URL("../../build",import.meta.url).pathname,prefix:"zig-native-constructor-import-"});
 try{
  await Deno.writeTextFile(dir+"/model.blot",producerSource);await Deno.writeTextFile(dir+"/main.blot",consumerSource);
  const result=await new Deno.Command(compiler,{args:["build-project",dir+"/main.blot",dir+"/program.wasm","--prelude","none"],stdout:"piped",stderr:"piped"}).output();
  const text=new TextDecoder().decode(result.stdout);if(!result.success)throw new Error(text+new TextDecoder().decode(result.stderr));
  const metrics=text.trim().split("\n").map(line=>JSON.parse(line)).find(row=>row.kind==="compilation");strictEqual(metrics.memory.live_bytes,0);
  const bytes=await Deno.readFile(dir+"/program.wasm");strictEqual(WebAssembly.validate(bytes),true);
  const guest=await instantiateGuest(bytes,{asynchronous});
  try{
   strictEqual(guest.read("folded"),21);
   for(let iteration=0;iteration<100;iteration++){
    for(const value of [0,40,0x80000000,0xffffffff]){
     strictEqual(asynchronous?await guest.callAsync("unsigned",value):guest.call("unsigned",value),value);
     strictEqual(asynchronous?await guest.callAsync("tuple",value):guest.call("tuple",value),Math.fround(Math.fround(value)+2.5));
    }
    for(const value of [0,-0,2.5,42.5,Infinity,NaN])for(const name of ["floating","captured"])strictEqual(asynchronous?await guest.callAsync(name,value):guest.call(name,value),value);
    strictEqual(asynchronous?await guest.callAsync("ordered",null):guest.call("ordered",null),21);
   }
  }finally{guest.dispose();}
 }finally{await Deno.remove(dir,{recursive:true});}
});
