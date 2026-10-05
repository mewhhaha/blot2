import { compileAndRun, compileExpectedFailure, equal } from "./compile_helpers.ts";
import { GuestError } from "../../compiler/guest.ts";
import { rejects, throws } from "node:assert/strict";

export const constructorSource = `
data Box a = #Box { value:a }
data Pair = #Pair { x:U32,y:F32 }
data Wrapped = #Wrapped { value:(U32,F32) }
data Action = #Action { action:U32 -> F32 }
const box = #Box
const pair = #Pair
const unbox = fn value => case value of
  #Box payload => payload
const total = fn value => case value of
  #Pair (x,y) => @f32.add (@u32.to_f32 x) y
const invoke = fn constructor => fn value => unbox (constructor value)
const ready = invoke #Box
const retain = fn () => do:
  let constructor = #Box
  return fn value => unbox (constructor value)
entry const unsigned = fn (value:U32) => ready value
entry const floating = fn (value:F32) => unbox (box value)
entry const captured = fn (value:F32) => (retain ()) value
entry const local = fn (value:F32) => do:
  let constructor = #Box
  return unbox (constructor value)
entry const mixed = fn (value:U32) => total (pair (value,2.5))
entry const wrapped = fn (value:F32) => case #Wrapped (40,value) of
  #Wrapped payload => @f32.add (@u32.to_f32 (@product.get payload 0)) (@product.get payload 1)
entry const function_field = fn (value:U32) => case #Action (fn item=>@u32.to_f32 item) of
  #Action action => action value
entry const old_version = fn (value:U32) => do:
  let original = (value,2.5)
  let selected = pair original
  selected.x := 99
  return @f32.add (@u32.to_f32 (@product.get original 0)) selected.y
entry const folded = total (#Pair (40,2.5))
`;
for (const asynchronous of [false,true]) Deno.test(`callable record constructors preserve canonical arrows and owned storage (${asynchronous?"JSPI":"sync"})`,async()=>{
 await compileAndRun(constructorSource,async guest=>{
  equal(guest.read("folded"),42.5);
  for(let iteration=0;iteration<100;iteration++){
   for(const value of [0,7,40,0x80000000,0xffffffff]){
    equal(asynchronous?await guest.callAsync("unsigned",value):guest.call("unsigned",value),value);
    equal(asynchronous?await guest.callAsync("function_field",value):guest.call("function_field",value),Math.fround(value));
    for(const name of ["mixed","old_version"]) equal(asynchronous?await guest.callAsync(name,value):guest.call(name,value),Math.fround(Math.fround(value)+2.5));
   }
   for(const value of [0,-0,2.5,42.5,Infinity,NaN]){
    for(const name of ["floating","captured","local"])equal(asynchronous?await guest.callAsync(name,value):guest.call(name,value),value);
    equal(asynchronous?await guest.callAsync("wrapped",value):guest.call("wrapped",value),Math.fround(value+40));
   }
  }
 },{asynchronous});
});

export const orderedSource = `
data Pair = #Pair { x:U32,y:F32 }
data Callback = #Callback { action:Unit -> F32 ! {Foreign} }
const pair = #Pair
const callback = #Callback
const total = fn value => case value of
  #Pair (x,y) => @f32.add (@u32.to_f32 x) y
const first = fn host => do:
  use host 0
  return 40
const second = fn host => do:
  use host 1
  return 2.5
entry const ordered = fn (host:U32 -> U32 ! {Foreign}) => do:
  use selected <- pair (first host,second host)
  return total selected
entry const boxed = fn (host:Unit -> F32 ! {Foreign}) => case callback host of
  #Callback action => action ()
entry const pure = fn () => 7
`;
Deno.test("callable record constructor arguments run once in source order and retain selected callback rows",async()=>{
 for(const asynchronous of [false,true])await compileAndRun(orderedSource,async guest=>{
  const order:number[]=[];
  const capability=asynchronous?guest.capabilityAsync({parameter:"U32",result:"U32",call:async value=>{await Promise.resolve();order.push(value);return value;}}):guest.capability({parameter:"U32",result:"U32",call:value=>{order.push(value);return value;}});
  let calls=0;
  const callback=asynchronous?guest.capabilityAsync({parameter:"Unit",result:"F32",call:async()=>{await Promise.resolve();calls++;return 42.5;}}):guest.capability({parameter:"Unit",result:"F32",call:()=>{calls++;return 42.5;}});
  for(let iteration=0;iteration<100;iteration++){
   equal(asynchronous?await guest.callAsync("ordered",capability):guest.call("ordered",capability),42.5);
   equal(asynchronous?await guest.callAsync("boxed",callback):guest.call("boxed",callback),42.5);
  }
  equal(order.length,200);equal(calls,100);for(let index=0;index<order.length;index++)equal(order[index],index%2);
  const wrong=guest.capability({parameter:"Unit",result:"U32",call:()=>42});
  const signature=(error:unknown)=>error instanceof GuestError&&error.code==="capability_signature";
  if(asynchronous)await rejects(()=>guest.callAsync("boxed",wrong),signature);else throws(()=>guest.call("boxed",wrong),signature);
  const cause=new Error("first argument failed");let failed=0;
  const bad=asynchronous?guest.capabilityAsync({parameter:"U32",result:"U32",call:async value=>{failed++;equal(value,0);throw cause;}}):guest.capability({parameter:"U32",result:"U32",call:value=>{failed++;equal(value,0);throw cause;}});
  if(asynchronous)await rejects(()=>guest.callAsync("ordered",bad));else throws(()=>guest.call("ordered",bad));
  equal(failed,1);equal(asynchronous?await guest.callAsync("pure",null):guest.call("pure",null),7);
  equal(asynchronous?await guest.callAsync("ordered",capability):guest.call("ordered",capability),42.5);
 },{asynchronous});
});
Deno.test("callable record constructors reject incompatible argument shapes and latent rows",async()=>{
 for(const [source,code]of[
  ["data Pair=#Pair {x:U32,y:F32}\nentry const answer=#Pair 42\n","type_mismatch"],
  ["data Box=#Box {value:F32}\nentry const answer=#Box 42\n","type_mismatch"],
  ["type Read is effect={read:Unit -> U32}\ndata Box=#Box {action:Unit -> U32}\nentry const answer=#Box (fn()=>Read.read ())\n","effect_mismatch"],
 ]as const)await compileExpectedFailure(source,code);
});

export const stateSource = `
data Cell a = #Cell { value:a }
const cell = #Cell
const unsigned_witness = fn () -> Cell U32 => @panic "type witness executed"
const floating_witness = fn () -> Cell F32 => @panic "type witness executed"
entry const unsigned_state = fn (value:U32) => do:
  let (#Cell final,selected) = @state.run (cell value) (fn () => do:
    use @state.set (cell (@u32.add value 1))
    use box <- @state.get unsigned_witness
    let #Cell result = box
    return result
  )
  return @u32.add final selected
entry const floating_state = fn (value:F32) => do:
  let (#Cell final,selected) = @state.run (cell value) (fn () => do:
    use @state.set (cell (@f32.add value 1.0))
    use box <- @state.get floating_witness
    let #Cell result = box
    return result
  )
  return @f32.add final selected
entry const folded_state = @f32.add (@u32.to_f32 (unsigned_state 20)) (floating_state 20.25)
`;
Deno.test("canonical generic constructors preserve independent quantified State identities",async()=>{
 for(const asynchronous of [false,true])await compileAndRun(stateSource,async guest=>{
  equal(guest.read("folded_state"),84.5);
  for(let iteration=0;iteration<100;iteration++){
   for(const value of [0,20,0x80000000,0xffffffff])equal(asynchronous?await guest.callAsync("unsigned_state",value):guest.call("unsigned_state",value),(2*(value+1))>>>0);
   for(const value of [0,-0,20.25,Infinity,NaN])equal(asynchronous?await guest.callAsync("floating_state",value):guest.call("floating_state",value),Math.fround(2*Math.fround(value+1)));
  }
 },{asynchronous});
});
