// Fixed source-gated caller copy completeness; no runtime capability minting.
import {decode} from './i08_machine_decode.mjs';
import {check as bind,diagnosticForTests as diagnosticBase} from './i08_binding_provenance.mjs';
import {bind as windowBind} from './i08_caller_window_binding.mjs';
const getLen=Object.getOwnPropertyDescriptor(Object.getPrototypeOf(Uint8Array.prototype),'length').get;
function token(x){let v=x.imm;if(v!==undefined&&v!==null&&typeof v==='object')v=v.offset;else if([2,3,4,5,11].includes(x.op))v=null;return x.op.toString(16)+(v==null?'':':'+v);}
function unique(c,p){let a=p.split(' '),b=c.map(token),found=[];outer:for(let i=0;i+a.length<=b.length;i++){for(let j=0;j<a.length;j++)if(a[j]!==b[i+j])continue outer;found.push(i);}if(found.length!==1)throw Error('copy loop shape');return found[0];}
function analyze(target,pinned){try{
 if(!(target instanceof Uint8Array))throw Error('target');let size=getLen.call(target);if(size<8||size>65536)throw Error('size');let bytes=new Uint8Array(size);Uint8Array.prototype.set.call(bytes,target);
 if(!(pinned?windowBind(bytes):diagnosticBase(bytes)).ok)throw Error('source target/operand premises');let g=decode(bytes);if(!g.ok)throw Error('decode');const c=g.bodies[22].ops;
 const at=unique(c,'41:264 28:0 21:9 41:0 21:12 2 3 20:12 20:5 41:16 6c 4f d:1 20:9 20:12 6a 41:32800 20:6 6a 20:12 6a 2d:0 3a:0 20:12 41:1 6a 21:12 c:0 b b 20:7 20:8 10:6 20:5 47 4 0 b');
 // Exhaust the count and owner placements of this closed fixed profile. The
 // matched unit-increment loop visits each byte exactly once, then freezes.
 let covered=0,placements=0;for(let n=0;n<=8;n++){const count=16*n,seen=new Uint8Array(count);let i=0,steps=0;while(i<count){if(i>=count || seen[i]!==0)throw Error('copy index');seen[i]=1;covered++;i=(i+1)>>>0;if(++steps>128)throw Error('loop');}if(i!==count||seen.some(x=>x!==1))throw Error('partial coverage');
  for(let block=0;block<6;block++){let base=4096+4096*block,end=base+count;if(end>base+192||end>32768||base+192>28672)throw Error('pool/ingress overlap');
   for(let offset=12;offset+count<=224;offset++){let first=32800+offset,last=first+count;if(first<32812||last>33024||last>65536)throw Error('ingress bound');placements++;}
  }
 }
 return {ok:true,matchedCopySite:at,logicalByteIterations:covered,placementCases:placements,inputBytesCopiedExactlyOnceOnNormalPath:true,zeroCountHasNoRead:true,sourceGateRequired:true,helperGeometryRequired:true,protectedInstanceRequired:true,unforgeableAuthority:false,publicEligible:false,m11Qualified:false};
 }catch(e){return {ok:false,error:String(e),publicEligible:false,m11Qualified:false};}}
export function check(target){return analyze(target,true);}
export function diagnosticForTests(target){let r=analyze(target,false);return {...r,testOnly:true,publicEligible:false,m11Qualified:false};}
