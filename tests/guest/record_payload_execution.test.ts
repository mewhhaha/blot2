import { compileAndRun, compileExpectedFailure, equal } from './compile_helpers.ts';
const source=`
type Pair is data = $Pair { x: U32, y: F32 }
type Box a is data = $Box { value: a }
type Wrapped is data = $Wrapped { value: (U32,F32) }
type Action is data = $Action { action: Unit -> F32, offset: U32 }
type Empty is data = $Empty {}
const unbox = func box => return case box of
  $Box value => value
entry const pair_value = func (value:U32) => return case $Pair {y:2.5,x:value} of
  $Pair payload => @f32.add (@u32.to_f32 (@product.get payload 0)) (@product.get payload 1)
entry const tuple_value = func (value:U32) => return case $Pair {y:2.5,x:value} of
  $Pair (x,y) => @f32.add (@u32.to_f32 x) y
entry const named_value = func (value:U32) => return case $Pair {y:2.5,x:value} of
  $Pair {y,x} => @f32.add (@u32.to_f32 x) y
entry const local_value = func (value:U32) => return do:
  let $Pair payload = $Pair {y:2.5,x:value}
  break @f32.add (@u32.to_f32 (@product.get payload 0)) (@product.get payload 1)
entry const one_u32 = func (value:U32) => return unbox ($Box {value})
entry const one_f32 = func (value:F32) => return unbox ($Box {value})
entry const wrapped_value = func (value:F32) => return case $Wrapped {value:(40,value)} of
  $Wrapped payload => @f32.add (@u32.to_f32 (@product.get payload 0)) (@product.get payload 1)
entry const higher_value = func (value:F32) => return case $Action {offset:40,action:func()=> return value} of
  $Action (action,offset) => @f32.add (action ()) (@u32.to_f32 offset)
entry const folded = case $Pair {y:2.5,x:40} of
  $Pair payload => @f32.add (@u32.to_f32 (@product.get payload 0)) (@product.get payload 1)
entry const empty = case $Empty {} of
  $Empty {} => 42
`;
for(const asynchronous of [false,true])Deno.test(`record constructor payload views preserve typed slots and captures (${asynchronous?'JSPI':'sync'})`,async()=>{
 await compileAndRun(source,async guest=>{
  equal(guest.read('folded'),42.5);equal(guest.read('empty'),42);
  for(let iteration=0;iteration<100;iteration++){
   for(const value of [0,7,40,0x80000000,0xffffffff]){
    for(const name of ['pair_value','tuple_value','named_value','local_value']){
     const actual=asynchronous?await guest.callAsync(name,value):guest.call(name,value);
     equal(actual,Math.fround(Math.fround(value)+2.5));
    }
    equal(asynchronous?await guest.callAsync('one_u32',value):guest.call('one_u32',value),value);
   }
   for(const value of [0,-0,2.5,42.5,Infinity,NaN]){
    equal(asynchronous?await guest.callAsync('one_f32',value):guest.call('one_f32',value),value);
    for(const name of ['wrapped_value','higher_value'])equal(asynchronous?await guest.callAsync(name,value):guest.call(name,value),Math.fround(value+40));
   }
  }
 },{asynchronous});
});
Deno.test('record constructor views preserve scalar/arity and coverage rejection',async()=>{
 for(const [source,code]of[
  ['type One is data= $One {value:U32}\nentry const answer=case $One {value:42} of\n  $One payload=>@product.get payload 0\n','type_mismatch'],
  ['type Pair is data= $Pair {x:U32,y:U32}\nentry const answer=case $Pair {x:40,y:2} of\n  $Pair payload=>@u32.add payload 0\n','type_mismatch'],
  ['type Empty is data= $Empty {}\nentry const answer=case $Empty {} of\n  $Empty payload=>42\n','constructor_arity'],
  ['type Pair is data= $Pair {x:U32,y:U32}\nentry const answer=case $Pair {x:40,y:2} of\n  $Pair=>42\n','constructor_arity'],
  ['type Pair is data= $Pair {left:Bool,right:Bool}\nentry const answer=case $Pair {right:true,left:false} of\n  $Pair (true,_)=>0\n  $Pair {left:false,right:false}=>42\n','non_exhaustive_match'],
 ]as const)await compileExpectedFailure(source,code);
});
export const recordPayloadSource=source;
