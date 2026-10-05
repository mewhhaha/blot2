import {compileAndRun,compileExpectedFailure,equal} from './compile_helpers.ts';
for(const asynchronous of [false,true])Deno.test(`contextual record schemas and guarded bindings (${asynchronous?'JSPI':'sync'})`,async()=>{
 await compileAndRun(`
data Pair=#Pair {x:U32,y:U32}
data Empty=#Empty {}
data Choice a=#Some a|#None
entry const empty=fn()=>case #Empty {} of
  #Empty {}=>42
entry const selected=fn (value:U32)=>do:
  let #Some chosen=#Some value else:
    return 0
  return chosen
entry const reordered=fn (value:U32)=>case #Pair {y:2,x:value} of
  #Pair {x}=>x
entry const generic=fn()=>do:
  let identity=fn value=>value
  let first=identity 42
  let second=identity 1.5
  return first
`,async guest=>{
  equal(asynchronous?await guest.callAsync('empty',null):guest.call('empty',null),42);
  equal(asynchronous?await guest.callAsync('generic',null):guest.call('generic',null),42);
  for(const value of [0,1,42,0xffffffff])for(const name of ['selected','reordered'])equal(asynchronous?await guest.callAsync(name,value):guest.call(name,value),value);
 },{prelude:'none',asynchronous});
});
Deno.test('record and guarded-pattern errors retain their actual source context',async()=>{
 for(const[source,code,message]of[
  ['data Pair=#Pair {x:U32,y:U32}\nentry const answer=#Pair {x:42}\n','missing_record_field','missing record field: y'],
  ['data Pair=#Pair {x:U32,y:U32}\nentry const answer=#Pair {z:missing}\n','unknown_record_field','record has no field named z'],
  ['data Box=#Box U32\nentry const answer=#Box {x:missing}\n','record_constructor','named fields require a declared record constructor'],
  ['data Empty=#Empty\nentry const answer=#Empty {}\n','record_constructor','named fields require a declared record constructor'],
  ['pub const answer=missing\n','unknown_modifier','only `entry` may precede `const` or `let`'],
  ['entry const answer=fn()=>do:\n  let (#True,value)=(#True,42)\n  return value\n','non_exhaustive_match',undefined],
  ['entry const answer=fn()=>do:\n  let value=42 else:\n    0\n  return value\n','guard_fallthrough','let-else fallback must exit its enclosing do block'],
  ['entry const answer=fn()=>do:\n  let (x,y,z)=(1,2)\n  return x\n','product_arity','cannot unify products with different element counts'],
 ]as const)await compileExpectedFailure(source,code,message,{prelude:'none'});
});
