import {invoke} from './i08_live_authority.mjs';
const pinned=Uint8Array.from(Buffer.from('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','base64'));
// Private one-schema host wrapper. Its source/target pin is rechecked by the
// scratch source gate, but its frame accounting is a local model rather than
// a qualified K1 frame arena or M12 source-callable/manifest admission.
const typedLength=Object.getOwnPropertyDescriptor(Object.getPrototypeOf(Uint8Array.prototype),'length').get;
const uint=x=>Number.isInteger(x)&&x>=0&&x<=0xffffffff;
const abi=0x4b310001,exportId=91,windowBytes=256,frameNeed=768;
export function create(target,frameCapacity=1024,fault=0) {
 if(!(target instanceof Uint8Array) || typedLength.call(target)!==pinned.length ||
    !Uint8Array.prototype.every.call(target,(b,i)=>b===pinned[i]) || !uint(frameCapacity) || frameCapacity>1024 ||
    !uint(fault) || fault>3) throw TypeError('fixture setup');
 let running=false,poisoned=false,frameTop=0,calls=0;
 const inspect=()=>({running,poisoned,frameTop,calls});
 function invokeFrame(input,capacity) {
  if(poisoned)return {status:'Poisoned'};
  if(running)return {status:'Busy'};
  running=true;const prior=frameTop;
  function status(code,required=0,items=0,detail=0,payload=null) {
   const len=payload===null?0:payload.length,out=new Uint8Array(32+len),d=new DataView(out.buffer);
   d.setUint32(0,abi,true);d.setUint32(4,exportId,true);d.setUint32(8,code,true);d.setUint32(12,len,true);
   d.setUint32(16,required,true);d.setUint32(20,items,true);d.setUint32(24,detail,true);d.setUint32(28,0,true);
   if(payload!==null)out.set(payload,32);return {status:code,frame:out};
  }
  try {
   if(!(input instanceof Uint8Array)||!uint(capacity))throw TypeError('input');
   if(capacity>windowBytes-32)return status(1);
   const length=typedLength.call(input);if(length<32||length>windowBytes)return status(1);
   const snap=new Uint8Array(length);Uint8Array.prototype.set.call(snap,input);
   const d=new DataView(snap.buffer),get=p=>d.getUint32(p,true),payload=length-32;
   if(get(0)!==abi||get(4)!==exportId||get(8)!==0||get(12)!==payload||get(16)!==0||get(20)!==0||
      get(24)!==0||get(28)!==0||payload<12)return status(1);
   const n=get(32),offset=get(36);
   if(n>8||(offset&3)!==0||offset<12||offset>payload||n*16>payload-offset)return status(1);
   const end=offset+n*16;for(let p=12;p<payload;p++)if((p<offset||p>=end)&&snap[32+p]!==0)return status(1);
   // This is a checked local frame model only; no actual Wasm frame arena has
   // been established, so it is not a K1 frame-preflight certificate.
   if(frameTop>frameCapacity||frameNeed>frameCapacity-frameTop)return status(5);
   frameTop+=frameNeed;
   if(fault===1)return status(3,0,0,1);
   const rows=snap.subarray(32+offset,32+end),dt=d.getFloat32(40,true);
   let result;
   try {result=invoke(pinned,rows,n,dt,ifault(fault));}
   catch(err) {poisoned=true;return {status:err instanceof WebAssembly.RuntimeError?'Poisoned':'InternalFailure'};}
   calls+=result.calls||0;
   if(result.status==='Poisoned'){poisoned=true;return {status:'Poisoned'};}
   if(result.status==='ReservationFailed')return status(3,0,0,1);
   if(result.status!=='Ok'||result.calls!==1||!result.closed||result.output.length!==n*8){poisoned=true;return {status:'InternalFailure'};}
   const need=8+n*8;if(need>capacity)return status(2,need,n);
   const out=new Uint8Array(need),od=new DataView(out.buffer);od.setUint32(0,n,true);od.setUint32(4,8,true);out.set(result.output,8);
   return status(0,need,n,0,out);
  } finally {frameTop=prior;running=false;}
 }
 return Object.freeze({invoke:invokeFrame,inspect});
}
function ifault(fault){return fault===2?14:fault===3?15:-1;}
