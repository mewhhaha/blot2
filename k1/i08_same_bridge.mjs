// Scratch private single-owner particle bridge, not M12 or a public ABI.
// Actual source capability/loan provenance, resource/frame proof, arbitrary
// manifests, arithmetic NaN propagation and concurrency remain unqualified.
const encoded='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';
const pinned=Uint8Array.from(Buffer.from(encoded,'base64'));
const ta=Object.getPrototypeOf(Uint8Array.prototype);
const typedLength=Object.getOwnPropertyDescriptor(ta,'length').get;
const uint=x=>Number.isInteger(x)&&x>=0&&x<=0xffffffff;
export function create(bytes,fault=0) {
 if(!(bytes instanceof Uint8Array) || typedLength.call(bytes)!==pinned.length ||
    !Uint8Array.prototype.every.call(bytes,(b,i)=>b===pinned[i]) || !uint(fault) || fault>5) throw TypeError('fixture target');
 const wasm=new WebAssembly.Instance(new WebAssembly.Module(pinned)).exports;
 const memory=new Uint8Array(wasm.memory.buffer),view=new DataView(memory.buffer);
 let running=false,poisoned=false,calls=0,lastClosed=true;
 const inspect=()=>({running,poisoned,calls,lastClosed});
 function call(input,capacity) {
  if(poisoned)return {status:'Poisoned'};
  if(running)return {status:'Busy'};
  running=true;let owner=null,inputState=0,outputState=0;lastClosed=true;
  try {
   if(!(input instanceof Uint8Array) || !uint(capacity) || capacity>224) throw TypeError('input');
   const length=typedLength.call(input);if(length<44 || length>256)return {status:'InvalidInput'};
   // One private snapshot; caller-shared concurrent mutation is not modeled.
   const snapshot=new Uint8Array(length);Uint8Array.prototype.set.call(snapshot,input);
   const d=new DataView(snapshot.buffer);const get=p=>d.getUint32(p,true);
   const payload=length-32;
   if(get(0)!==0x4b310001||get(4)!==91||get(8)!==0||get(12)!==payload||
      get(16)!==0||get(20)!==0||get(24)!==0||get(28)!==0)return {status:'InvalidInput'};
   const count=get(36),offset=get(40);
   if(count>8 || (offset&3)!==0 || offset<12 || offset>payload || count*16>payload-offset)return {status:'InvalidInput'};
   const end=offset+count*16;
   for(let i=12;i<payload;i++) if((i<offset||i>=end) && snapshot[32+i]!==0)return {status:'InvalidInput'};
   const dt=d.getFloat32(32,true);
   const slot=wasm.reserve(fault===1?0xffffffff:count*24);
   if(slot<=0)return {status:'ReservationFailed'};
   owner={slot,gen:view.getUint32(16+(slot-1)*32+16,true)};lastClosed=false;
   if(wasm.input_alloc(slot,owner.gen,count)!==0)throw Error('trusted input allocation invariant');inputState=1;
   if(fault===2)return {status:'InjectedCopyFailure'};
   const inputPtr=view.getUint32(256+(slot-1)*16+8,true);
   if(count)memory.set(snapshot.subarray(32+offset,32+end),inputPtr);
   if(wasm.input_freeze(slot,owner.gen)!==count)throw Error('input freeze invariant');inputState=2;
   if(fault===3)return {status:'InjectedSetupFailure'};
   if(wasm.builder_alloc(slot,owner.gen,count)!==0)throw Error('builder allocation invariant');outputState=1;
   if(fault===4)return {status:'InjectedLanguageFailure'};
   const outputPtr=view.getUint32(320+(slot-1)*16+8,true);
   calls++;if(wasm.project(slot,owner.gen,slot,owner.gen,dt)!==count)throw Error('project invariant');outputState=2;
   if(fault===5)return {status:'InjectedPostCallFailure'};
   const required=8+count*8;if(required>capacity)return {status:'OutputTooSmall',required,count};
   const out=new Uint8Array(required),od=new DataView(out.buffer);od.setUint32(0,count,true);od.setUint32(4,8,true);
   if(count)out.set(memory.subarray(outputPtr,outputPtr+count*8),8);
   return {status:'Ok',payload:out,count};
  } catch(e) {if(e instanceof WebAssembly.RuntimeError){poisoned=true;return {status:'Poisoned'};}throw e;}
  finally {
   // Engine traps poison the instance; source-level error recovery is absent.
   if(!poisoned && owner) {
    if(outputState && wasm.output_end(owner.slot,owner.gen)!==0)poisoned=true;
    if(inputState && (inputState===1?wasm.input_discard(owner.slot,owner.gen):wasm.input_end(owner.slot,owner.gen))!==0)poisoned=true;
    if(!poisoned && wasm.close(owner.slot,owner.gen)!==0)poisoned=true;
    if(!poisoned)lastClosed=view.getUint32(144,true)===0;
   }
   running=false;
  }
 }
 return Object.freeze({call,inspect});
}
