import {compileAndRun, compileExpectedFailure, equal} from './compile_helpers.ts';

export const bottomFlowSource = `
data Maybe a=#Some a|#None
const stop=fn value=>@panic "first-body"
const ignore=fn ~(value:U32)=>42
entry const direct:Unit->U32=fn()=>do:
  let value=(@panic "callee") 1
  return 42
entry const strict:Unit->U32=fn()=>stop 1 (@panic "later-arg")
entry const product=fn(flag:Bool)=>do:
  let #Some value=if flag then #Some 42 else #None else:
    let stop=(@panic "product",0)
  return value
entry const array=fn(flag:Bool)=>do:
  let #Some value=if flag then #Some 42 else #None else:
    let stop=#[0,@panic "array"]
  return value
entry const merge=fn(flag:Bool)=>do:
  let value=42
  if flag:
    value:=@panic "merge"
  return value
entry const changing=fn(flag:Bool)=>do:
  let value=42
  if flag:
    value:=@panic "merge"
  else:
    value:=1.5
  return value
entry const demand=fn()=>ignore (@panic "suspended")
entry const empty=fn()=>@array.length (@array.generate 0 (fn(index:U32)->U32=>@panic "callback"))
entry const ordered: (U32->U32 ! {Foreign}) -> U32 ! {Foreign}=fn io=>do:
  use (do:
    use first<-io 1
    @panic "callee"
  ) (do:
    use second<-io 2
    return 0
  )
  return 42
`;

for(const asynchronous of [false,true])Deno.test(`bottom values preserve eager order and suspended callbacks (${asynchronous?'JSPI':'sync'})`,async()=>{
 await compileAndRun(bottomFlowSource,async guest=>{
  const call=async(name:string,arg:unknown)=>asynchronous?await guest.callAsync(name,arg):guest.call(name,arg);
  const trap=async(name:string,arg:unknown)=>{
   try{await call(name,arg);}catch(error){if(error instanceof WebAssembly.RuntimeError)return;throw error;}
   throw new Error(`Expected ${name} to trap`);
  };
  for(let repeat=0;repeat<20;repeat++){
   equal(await call('product',true),42);
   equal(await call('array',true),42);
   equal(await call('merge',false),42);
   equal(await call('changing',false),1.5);
   equal(await call('demand',null),42);
   equal(await call('empty',null),0);
   for(const name of ['direct','strict'])await trap(name,null);
   for(const name of ['product','array'])await trap(name,false);
   for(const name of ['merge','changing'])await trap(name,true);
   const trace:number[]=[];
   const capability=asynchronous
    ?guest.capabilityAsync({parameter:'U32',result:'U32',call:async(value:number)=>{trace.push(value);return value;}})
    :guest.capability({parameter:'U32',result:'U32',call:(value:number)=>{trace.push(value);return value;}});
   await trap('ordered',capability);
   equal(trace.join(','),'1');
  }
 },{prelude:'none',asynchronous});
});

Deno.test('bottom prefixes keep static suffix errors and exact guard boundaries',async()=>{
 for(const[source,code]of[
  ['entry const answer:Unit->U32=fn()=>do:\n  let stop=(@panic "stop",0)\n  let bad:U32=#True\n  return 42\n','type_mismatch'],
  ['entry const answer:Unit->U32=fn()=>@u32.add (@panic "stop") #True\n','type_mismatch'],
  ['entry const answer=fn()=>do:\n  let value=42 else:\n    let stop=@array.generate 0 (fn(index:U32)->U32=>@panic "callback")\n  return value\n','guard_fallthrough'],
  ['const ignore=fn ~(value:U32)=>42\nentry const answer=fn()=>do:\n  let value=42 else:\n    let stop=ignore (@panic "suspended")\n  return value\n','guard_fallthrough'],
  ['entry const answer=fn(flag:Bool)=>do:\n  let value=42\n  if flag:\n    value:=@panic "stop"\n  else:\n    value:=@panic "stop"\n  return 42\n','entry_type'],
 ]as const)await compileExpectedFailure(source,code,undefined,{prelude:'none'});
});
