import {compileAndRun,compileExpectedFailure,equal} from './compile_helpers.ts';
for(const asynchronous of [false,true])Deno.test(`contextual record schemas and guarded bindings (${asynchronous?'JSPI':'sync'})`,async()=>{
 await compileAndRun(`
type Pair is data= $Pair {x:U32,y:U32}
type Empty is data= $Empty {}
type Choice a is data= $Some a| $None
entry const empty=func()=> return case $Empty {} of
  $Empty {}=>42
entry const selected=func (value:U32)=> return do:
  let $Some chosen= $Some value else:
    break 0
  break chosen
entry const reordered=func (value:U32)=> return case $Pair {y:2,x:value} of
  $Pair {x}=>x
entry const generic=func()=> return do:
  let identity=func value=> return value
  let first=identity 42
  let second=identity 1.5
  break first
`,async guest=>{
  equal(asynchronous?await guest.callAsync('empty',null):guest.call('empty',null),42);
  equal(asynchronous?await guest.callAsync('generic',null):guest.call('generic',null),42);
  for(const value of [0,1,42,0xffffffff])for(const name of ['selected','reordered'])equal(asynchronous?await guest.callAsync(name,value):guest.call(name,value),value);
 },{prelude:'none',asynchronous});
});
Deno.test('record and guarded-pattern errors retain their actual source context',async()=>{
 for(const[source,code,message]of[
  ['type Pair is data= $Pair {x:U32,y:U32}\nentry const answer= $Pair {x:42}\n','missing_record_field','missing record field: y'],
  ['type Pair is data= $Pair {x:U32,y:U32}\nentry const answer= $Pair {z:missing}\n','unknown_record_field','record has no field named z'],
  ['type Box is data= $Box U32\nentry const answer= $Box {x:missing}\n','record_constructor','named fields require a declared record constructor'],
  ['type Empty is data= $Empty\nentry const answer= $Empty {}\n','record_constructor','named fields require a declared record constructor'],
  ['pub const answer=missing\n','unknown_modifier','only `entry` may precede `const` or `let`'],
  ['entry const answer=func()=> return do:\n  let (true,value)=(true,42)\n  break value\n','non_exhaustive_match',undefined],
  ['entry const answer=func()=> return do:\n  let value=42 else:\n    0\n  break value\n','guard_fallthrough','let-else fallback must exit its enclosing do block'],
  ['entry const answer=func()=> return do:\n  let (x,y,z)=(1,2)\n  break x\n','product_arity','cannot unify products with different element counts'],
 ]as const)await compileExpectedFailure(source,code,message,{prelude:'none'});
});
