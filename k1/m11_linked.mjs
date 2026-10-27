// Private fixed target/source resource and partial slot composition. Source
// sidecar must be emitted by separately checked source/target gate. It is not
// a receipt for hostile callers, a portable certificate, or M11 qualification.
import {verifyFlow} from './i08_flow_verify.mjs';
const typedLength=Object.getOwnPropertyDescriptor(Object.getPrototypeOf(Uint8Array.prototype),'length').get;
const expected=[2,256,3,512,4,176,40,6,0,768,0, 0,24,32,8,128,20,160,16,176,256];
function readResource(bytes) {
 if(!(bytes instanceof Uint8Array))throw Error('resource bytes');const n=typedLength.call(bytes);if(n!==8+4*expected.length)throw Error('size');
 const copy=new Uint8Array(n);Uint8Array.prototype.set.call(copy,bytes);
 if(String.fromCharCode(...copy.subarray(0,8))!=='I08RES01')throw Error('edition');const d=new DataView(copy.buffer);
 const values=expected.map((v,i)=>{const x=d.getUint32(8+4*i,true);if(x!==v)throw Error('source resource');return x;});return values;
}
export function inspectLinked(target,resource) {try {
 const r=readResource(resource);const flow=verifyFlow(target);
 if(!flow.ok || !flow.adapterAndShimSlotsVerified || flow.machineDepth!==r[7])throw Error('flow');
 const tuples=[[49152,49176],[49184,49192],[49280,49300],[49312,49328]];
 const a=flow.adapter.filter(x=>x.address>=49152&&x.address<49920),s=flow.shim.filter(x=>x.address>=49152&&x.address<49920);
 const allowed=x=>tuples.some(([lo,hi])=>x.address>=lo&&x.address+4<=hi);
 if(a.length===0||s.length===0||!a.every(allowed)||!s.every(allowed))throw Error('slot');
 const kernelReserved=[49152+r[19],49152+r[19]+r[20]];
 if(a.concat(s).some(x=>x.address<kernelReserved[1] && x.address+4>kernelReserved[0]))throw Error('overlap');
 if(r[5]>r[9]||r[3]>r[9]-r[5]||r[6]>r[3]||r[1]>r[3]-r[6])throw Error('resource overflow');
 return {ok:true,sourceContractDepths:[r[0],r[2]],wrapperSourceArithmeticLowerBound:r[4],sourceFrames:[r[1],r[3]],
  actualMachineDepth:r[7],declaredEnvelope:r[5]+r[3],physicalReservation:r[9],
  adapterAndShimFrameAccesses:a.length+s.length,sourceCallClassificationQualified:false,
  helperFrameEffectsQualified:false,callerWorkerDynamicAccessesQualified:false,m11Qualified:false};
 }catch{return {ok:false,m11Qualified:false};}}
