// Private, single-use same-instance witness. Trusted compiler-verified target,
// JS intrinsics, nonconcurrent caller, pool internals and no hostile reentrant
// callbacks are assumptions. This is not a portable authority receipt, K1
// source loan admission, host ABI, frame proof or general M12 implementation.
const pinned=Uint8Array.from(Buffer.from('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','base64'));
const typedLength=Object.getOwnPropertyDescriptor(Object.getPrototypeOf(Uint8Array.prototype),'length').get;
export function invoke(target,input,count,dt,corrupt=-1) {
 if(!(target instanceof Uint8Array) || typedLength.call(target)!==pinned.length ||
    !Uint8Array.prototype.every.call(target,(b,i)=>b===pinned[i])) throw TypeError('target');
 if(!(input instanceof Uint8Array) || !Number.isInteger(count) || count<0 || count>8 || typedLength.call(input)!==count*16 ||
    typeof dt!=='number' || !Number.isInteger(corrupt) || corrupt < -1 || corrupt>15) throw TypeError('input');
 const snapshot=new Uint8Array(count*16);Uint8Array.prototype.set.call(snapshot,input);
 const e=new WebAssembly.Instance(new WebAssembly.Module(pinned)).exports;
 const m=new Uint8Array(e.memory.buffer),d=new DataView(m.buffer),get=p=>d.getUint32(p,true),set=(p,v)=>d.setUint32(p,v,true);
 const id=e.reserve(192);if(id!==1)return {status:'ReservationFailed',calls:0};
 const generation=get(32);let inputState=0,outputState=0,calls=0;
 try {
  if(e.input_alloc(id,generation,count)!==0)throw Error('input_alloc');inputState=1;
  const ptr=get(264);if(count)m.set(snapshot,ptr);
  if(e.input_freeze(id,generation)!==count)throw Error('input_freeze');inputState=2;
  if(e.builder_alloc(id,generation,8)!==0)throw Error('builder_alloc');outputState=1;
  // Adversarial test only; corrupt actual live metadata before validation.
  const mutate=[16,20,24,28,32,36,144,256,260,264,268,320,324,328];
  if(corrupt>=0 && corrupt<14)set(mutate[corrupt],get(mutate[corrupt])^1);
  // Reconstruct from the live Wasm allocator and descriptor bytes, not from
  // a caller-provided numeric ledger. Input must still be immutable and both
  // distinct ranges must fit inside the exact allocated frontier.
  const valid=get(16)===4096 && get(20)===192 && get(24)===4096 && get(28)===count*16+64 &&
    get(32)===generation && generation!==0 && get(36)===1 && get(144)===1 &&
    get(256)===2 && get(260)===generation && get(264)===(count?4096:0) && get(268)===count &&
    get(320)===1 && get(324)===generation && get(328)===4096+count*16 && get(332)===0 && get(384)===8 &&
    (count===0 || Uint8Array.prototype.every.call(snapshot,(b,i)=>b===m[4096+i]));
  if(!valid)return {status:'InvalidLiveState',calls:0,disposed:true};
  if(corrupt===14)throw new WebAssembly.RuntimeError("injected pre-call trap");
  const outPtr=get(328);calls++;
  if(e.project(id,generation,id,generation,dt)!==count)throw Error('project');outputState=2;
  if(corrupt===15)throw new WebAssembly.RuntimeError('injected post-call trap');
  if(get(320)!==2 || get(324)!==generation || get(332)!==count || get(328)!==(count?outPtr:0))throw Error('output');
  const out=new Uint8Array(count*8);if(count)out.set(m.subarray(outPtr,outPtr+count*8));
  if(e.output_end(id,generation)!==0)throw Error('output_end');outputState=0;
  if(e.input_end(id,generation)!==0)throw Error('input_end');inputState=0;
  if(e.close(id,generation)!==0 || get(144)!==0)throw Error('close');
  return {status:'Ok',calls,output:out,closed:true};
 } catch(err) {return {status:err instanceof WebAssembly.RuntimeError?'Poisoned':'InternalFailure',calls,disposed:true};}
 // Fresh instance is discarded on every failure. Forced metadata corruption
 // never attempts to close through damaged numeric state.
}
